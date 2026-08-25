import Foundation

final class CodexAppServerClient: @unchecked Sendable {
    enum ClientError: LocalizedError {
        case codexNotFound, noLoadedThread, malformedResponse, server(String)
        var errorDescription: String? {
            switch self {
            case .codexNotFound: "codex executable not found"
            case .noLoadedThread: "no loaded Codex thread; launch the CLI with codex --remote ws://127.0.0.1:4500"
            case .malformedResponse: "malformed app-server response"
            case .server(let message): "app-server: \(message)"
            }
        }
    }

    var onStatus: (@Sendable (StatusPacket) -> Void)?
    var onReady: (@Sendable () -> Void)?

    private let queue = DispatchQueue(label: "CodexBridge.app-server")
    private var server: Process?
    private var transport: AppServerTransport?
    private var nextID = 1
    private var callbacks: [Int: (Result<[String: Any], Error>) -> Void] = [:]
    private var selectedThreadID: String?
    private var effort: Effort = .unknown
    private var model: ModelChoice = .unknown
    private var status: BridgeStatus = .disconnected
    private var threadStatuses: [String: BridgeStatus] = [:]

    func start() throws {
        if ProcessInfo.processInfo.environment["CODEX_DESKTOP_SHARED"] == "1" {
            return try startDesktopShared()
        }

        let configuredURL = ProcessInfo.processInfo.environment["CODEX_APP_SERVER_URL"]
        let endpoint = configuredURL ?? "ws://127.0.0.1:4500"
        guard let url = URL(string: endpoint) else { throw ClientError.server("invalid URL: \(endpoint)") }

        if configuredURL == nil {
            let codex = try Self.findCodex()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: codex)
            process.arguments = ["app-server", "--listen", endpoint]
            process.standardOutput = FileHandle.standardError
            process.standardError = FileHandle.standardError
            try process.run()
            server = process
            Thread.sleep(forTimeInterval: 0.25)
        }

        let transport = URLSessionAppServerTransport(url: url)
        try connect(transport, description: endpoint)
    }

    func handle(_ command: Command) {
        queue.async { [weak self] in self?.resolveThreadAndApply(command) }
    }

    func stop() {
        transport?.stop()
        if server?.isRunning == true { server?.terminate() }
    }

    private func startDesktopShared() throws {
        let socketPath = NSString(string: ProcessInfo.processInfo.environment["CODEX_APP_SERVER_SOCKET"]
            ?? "~/.codex/app-server-control/app-server-control.sock").expandingTildeInPath
        let codex = try Self.findCodex(preferDesktop: true)

        if !FileManager.default.fileExists(atPath: socketPath) {
            try FileManager.default.createDirectory(
                atPath: (socketPath as NSString).deletingLastPathComponent,
                withIntermediateDirectories: true
            )
            let process = Process()
            process.executableURL = URL(fileURLWithPath: codex)
            process.arguments = [
                "-c", "features.code_mode_host=true", "app-server",
                "--listen", "unix://\(socketPath)", "--analytics-default-enabled"
            ]
            process.standardOutput = FileHandle.standardError
            process.standardError = FileHandle.standardError
            try process.run()
            server = process
            for _ in 0..<40 where !FileManager.default.fileExists(atPath: socketPath) {
                Thread.sleep(forTimeInterval: 0.05)
            }
            guard FileManager.default.fileExists(atPath: socketPath) else {
                throw ClientError.server("shared daemon did not create \(socketPath)")
            }
        }

        let proxy = ProxyAppServerTransport(codexPath: codex, socketPath: socketPath)
        try connect(proxy, description: "unix://\(socketPath) (Desktop shared)")
    }

    private func connect(_ transport: AppServerTransport, description: String) throws {
        self.transport = transport
        transport.onMessage = { [weak self] data in
            guard let client = self else { return }
            client.queue.async { client.consume(data) }
        }
        transport.onError = { [weak self] error in
            guard let client = self else { return }
            client.queue.async { client.report(error) }
        }
        try transport.start()

        request("initialize", params: [
            "clientInfo": ["name": "codex_bridge", "title": "Codex BLE Bridge", "version": "0.2.0"],
            "capabilities": ["experimentalApi": true]
        ]) { [weak self] result in
            guard case .success = result else {
                self?.publish(.error)
                return
            }
            self?.notify("initialized", params: [:])
            self?.publish(.idle)
            print("Connected to Codex app-server at \(description)")
            self?.onReady?()
        }
    }

    func probeLoadedThreads(completion: @escaping @Sendable () -> Void) {
        queue.async { [weak self] in
            guard let self else { return completion() }
            self.request("thread/loaded/list", params: [:]) { [weak self] result in
                guard let self else { return completion() }
                guard case .success(let response) = result,
                      let resultObject = response["result"] as? [String: Any],
                      let ids = resultObject["data"] as? [String] else {
                    print("Probe: thread/loaded/list failed: \(result)")
                    return completion()
                }
                print("Probe: loaded thread order = \(ids)")
                guard !ids.isEmpty else { return completion() }

                var remaining = ids.count
                for id in ids {
                    self.request("thread/read", params: ["threadId": id, "includeTurns": false]) { result in
                        if case .success(let response) = result,
                           let thread = (response["result"] as? [String: Any])?["thread"] as? [String: Any] {
                            let name = thread["name"] as? String ?? thread["preview"] as? String ?? "(untitled)"
                            let updatedAt = thread["updatedAt"] ?? "?"
                            let status = thread["status"] ?? "?"
                            print("Probe: \(id) updatedAt=\(updatedAt) status=\(status) name=\(name)")
                        } else {
                            print("Probe: thread/read failed for \(id): \(result)")
                        }
                        remaining -= 1
                        if remaining == 0 { completion() }
                    }
                }
            }
        }
    }

    private func resolveThreadAndApply(_ command: Command) {
        if command == .stop {
            guard let threadID = selectedThreadID else { return report(ClientError.noLoadedThread) }
            request("thread/read", params: ["threadId": threadID, "includeTurns": true]) { [weak self] result in
                guard let self else { return }
                guard case .success(let response) = result,
                      let thread = (response["result"] as? [String: Any])?["thread"] as? [String: Any],
                      let turns = thread["turns"] as? [[String: Any]],
                      let turnID = turns.last?["id"] as? String else { return self.report(ClientError.malformedResponse) }
                self.request("turn/interrupt", params: ["threadId": threadID, "turnId": turnID]) { _ in }
            }
            return
        }

        if let pinned = ProcessInfo.processInfo.environment["CODEX_THREAD_ID"], !pinned.isEmpty {
            selectedThreadID = pinned
            return apply(command, to: pinned)
        }

        request("thread/loaded/list", params: [:]) { [weak self] result in
            guard let self else { return }
            guard case .success(let response) = result,
                  let resultObject = response["result"] as? [String: Any],
                  let ids = resultObject["data"] as? [String],
                  !ids.isEmpty else { return self.report(ClientError.noLoadedThread) }
            print("Loaded thread order: \(ids)")

            // Keep targeting the thread that most recently emitted activity.
            // `thread/loaded/list` is not ordered by Desktop focus, so choosing
            // its last entry can silently update a different loaded thread.
            if let selectedThreadID, ids.contains(selectedThreadID) {
                print("Using last active Desktop thread \(selectedThreadID)")
                return self.apply(command, to: selectedThreadID)
            }
            self.selectBestLoadedThread(from: ids, command: command)
        }
    }

    private func selectBestLoadedThread(from ids: [String], command: Command) {
        var remaining = ids.count
        var best: (id: String, score: Int, updatedAt: Int64, index: Int)?

        for (index, id) in ids.enumerated() {
            request("thread/read", params: ["threadId": id, "includeTurns": false]) { [weak self] result in
                guard let self else { return }
                defer {
                    remaining -= 1
                    if remaining == 0 {
                        if let selected = best {
                            print("Selected Desktop thread \(selected.id) (score=\(selected.score))")
                            self.selectedThreadID = selected.id
                            self.apply(command, to: selected.id)
                        } else {
                            self.report(ClientError.noLoadedThread)
                        }
                    }
                }
                guard case .success(let response) = result,
                      let thread = (response["result"] as? [String: Any])?["thread"] as? [String: Any] else { return }

                let status = thread["status"] as? [String: Any]
                let statusType = status?["type"] as? String
                let name = thread["name"] as? String ?? ""
                let preview = thread["preview"] as? String ?? ""
                let canAcceptInput = thread["canAcceptDirectInput"] as? Bool ?? false
                let updatedAt = (thread["updatedAt"] as? NSNumber)?.int64Value ?? 0

                // The Desktop may keep several internal/blank threads loaded.
                // Prefer the visibly active one, then a real user thread, and
                // use recency plus load order only as tie-breakers.
                var score = 0
                if statusType == "active" { score += 10_000 }
                if !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { score += 1_000 }
                if !preview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { score += 500 }
                if canAcceptInput { score += 100 }

                if best == nil
                    || score > best!.score
                    || (score == best!.score && updatedAt > best!.updatedAt)
                    || (score == best!.score && updatedAt == best!.updatedAt && index > best!.index) {
                    best = (id, score, updatedAt, index)
                }
            }
        }
    }

    private func apply(_ command: Command, to threadID: String) {
        var params: [String: Any] = ["threadId": threadID]
        let requestedModel = command.model
        switch command {
        case .fast:
            params["serviceTier"] = "priority"
        case .normal:
            params["serviceTier"] = NSNull()
            params["effort"] = "medium"
            effort = .medium
        case .deep:
            params["serviceTier"] = NSNull()
            params["effort"] = "high"
            effort = .high
        case .modelSol, .modelTerra, .modelLuna:
            guard let identifier = requestedModel?.identifier else {
                return report(ClientError.malformedResponse)
            }
            params["model"] = identifier
        default:
            return report(ClientError.server("command 0x\(String(command.rawValue, radix: 16)) is reserved for the next PoC"))
        }
        print("Applying \(command) to thread \(threadID): \(params)")
        publishAggregate(fallback: .working)
        request("thread/settings/update", params: params) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                if let requestedModel { self.model = requestedModel }
                print("Applied \(command) to thread \(threadID)")
                self.publishAggregate(fallback: .done)
            case .failure(let error): self.report(error)
            }
        }
    }

    private func request(_ method: String, params: [String: Any], completion: @escaping (Result<[String: Any], Error>) -> Void) {
        let id = nextID
        nextID += 1
        callbacks[id] = completion
        send(["id": id, "method": method, "params": params])
    }

    private func notify(_ method: String, params: [String: Any]) {
        send(["method": method, "params": params])
    }

    private func send(_ object: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else { return }
        transport?.send(text: text)
    }

    private func consume(_ data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if let id = object["id"] as? Int, let callback = callbacks.removeValue(forKey: id) {
            if let error = object["error"] as? [String: Any] {
                callback(.failure(ClientError.server(error["message"] as? String ?? "unknown error")))
            } else {
                callback(.success(object))
            }
        } else if let method = object["method"] as? String {
            consumeNotification(method: method, object: object)
        }
    }

    private func consumeNotification(method: String, object: [String: Any]) {
        let params = object["params"] as? [String: Any]
        if method == "thread/status/changed",
           let threadID = params?["threadId"] as? String,
           let threadStatus = params?["status"] as? [String: Any],
           let type = threadStatus["type"] as? String {
            switch type {
            case "active":
                selectedThreadID = threadID
                let activeFlags = threadStatus["activeFlags"] as? [String] ?? []
                threadStatuses[threadID] = Self.statusForActiveThread(flags: activeFlags)
                print("Desktop active thread changed to \(threadID)")
                publishAggregate(fallback: .working)
            case "idle":
                let wasActive = threadStatuses.removeValue(forKey: threadID) != nil
                let fallback: BridgeStatus = wasActive || status == .done ? .done : .idle
                publishAggregate(fallback: fallback)
            case "systemError":
                threadStatuses.removeValue(forKey: threadID)
                publishAggregate(fallback: .error)
            default:
                break
            }
        } else if method == "turn/started" {
            if let threadID = params?["threadId"] as? String {
                selectedThreadID = threadID
                threadStatuses[threadID] = .working
                publishAggregate(fallback: .working)
            } else {
                publish(.working)
            }
        } else if method == "turn/completed" {
            if let threadID = params?["threadId"] as? String {
                threadStatuses.removeValue(forKey: threadID)
            } else if let selectedThreadID {
                threadStatuses.removeValue(forKey: selectedThreadID)
            }
            publishAggregate(fallback: .done)
        } else if method == "thread/settings/updated",
                  let threadID = params?["threadId"] as? String,
                  let settings = params?["threadSettings"] as? [String: Any] {
            if let identifier = settings["model"] as? String,
               let updatedModel = Self.modelChoice(for: identifier) {
                model = updatedModel
            }
            print("Settings updated for \(threadID): model=\(settings["model"] ?? "nil") effort=\(settings["effort"] ?? "nil") serviceTier=\(settings["serviceTier"] ?? "nil")")
        } else if Self.isApprovalRequest(method) {
            updateThreadStatus(from: params, to: .awaitingApproval)
        } else if method.contains("requestUserInput") {
            updateThreadStatus(from: params, to: .waitingForUser)
        } else if method == "serverRequest/resolved" {
            updateThreadStatus(from: params, to: .working)
        } else if method == "thread/closed",
                  let threadID = params?["threadId"] as? String {
            threadStatuses.removeValue(forKey: threadID)
            publishAggregate(fallback: .idle)
        }
    }

    static func aggregateStatus(_ statuses: [BridgeStatus], fallback: BridgeStatus) -> BridgeStatus {
        if statuses.contains(where: { $0 == .awaitingApproval }) { return .awaitingApproval }
        if statuses.contains(where: { $0 == .working }) { return .working }
        if statuses.contains(where: { $0 == .waitingForUser }) { return .waitingForUser }
        return fallback
    }

    static func statusForActiveThread(flags: [String]) -> BridgeStatus {
        if flags.contains("waitingOnApproval") { return .awaitingApproval }
        if flags.contains("waitingOnUserInput") { return .waitingForUser }
        return .working
    }

    static func isApprovalRequest(_ method: String) -> Bool {
        method.contains("requestApproval")
            || method == "applyPatchApproval"
            || method == "execCommandApproval"
    }

    private func updateThreadStatus(from params: [String: Any]?, to nextStatus: BridgeStatus) {
        if let threadID = params?["threadId"] as? String {
            threadStatuses[threadID] = nextStatus
            publishAggregate(fallback: nextStatus)
        } else {
            publish(nextStatus)
        }
    }

    static func modelChoice(for identifier: String) -> ModelChoice? {
        [.sol, .terra, .luna].first { $0.identifier == identifier }
    }

    private func publish(_ nextStatus: BridgeStatus) {
        status = nextStatus
        onStatus?(StatusPacket(status: nextStatus, effort: effort, model: model))
    }

    private func publishAggregate(fallback: BridgeStatus) {
        publish(Self.aggregateStatus(Array(threadStatuses.values), fallback: fallback))
    }

    private func report(_ error: Error) {
        fputs("CodexBridge: \(error.localizedDescription)\n", stderr)
        publish(.error)
    }

    private static func findCodex(preferDesktop: Bool = false) throws -> String {
        let desktop = "/Applications/ChatGPT.app/Contents/Resources/codex"
        var candidates = [
            ProcessInfo.processInfo.environment["CODEX_BIN"],
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            desktop
        ].compactMap { $0 }
        if preferDesktop, FileManager.default.isExecutableFile(atPath: desktop) {
            candidates.removeAll(where: { $0 == desktop })
            candidates.insert(desktop, at: 0)
        }
        guard let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw ClientError.codexNotFound
        }
        return path
    }
}
