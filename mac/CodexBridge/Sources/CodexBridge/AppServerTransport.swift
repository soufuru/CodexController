import Foundation

protocol AppServerTransport: AnyObject {
    var onMessage: (@Sendable (Data) -> Void)? { get set }
    var onError: (@Sendable (Error) -> Void)? { get set }

    func start() throws
    func send(text: String)
    func stop()
}

final class URLSessionAppServerTransport: AppServerTransport, @unchecked Sendable {
    var onMessage: (@Sendable (Data) -> Void)?
    var onError: (@Sendable (Error) -> Void)?

    private let url: URL
    private var session: URLSession?
    private var socket: URLSessionWebSocketTask?

    init(url: URL) {
        self.url = url
    }

    func start() {
        let session = URLSession(configuration: .ephemeral)
        let socket = session.webSocketTask(with: url)
        socket.maximumMessageSize = 16 * 1024 * 1024
        self.session = session
        self.socket = socket
        socket.resume()
        receiveNext()
    }

    func send(text: String) {
        guard let socket else { return }
        Task { try? await socket.send(.string(text)) }
    }

    func stop() {
        socket?.cancel(with: .goingAway, reason: nil)
        session?.invalidateAndCancel()
    }

    private func receiveNext() {
        guard let socket else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                let message = try await socket.receive()
                switch message {
                case .string(let text): onMessage?(Data(text.utf8))
                case .data(let data): onMessage?(data)
                @unknown default: break
                }
                receiveNext()
            } catch {
                onError?(error)
            }
        }
    }
}

/// WebSocket-over-stdio transport. `codex app-server proxy` forwards these bytes
/// to the daemon's Unix-domain control socket, which lets Codex Desktop and this
/// bridge use the same app-server without exposing a TCP listener.
final class ProxyAppServerTransport: AppServerTransport, @unchecked Sendable {
    enum TransportError: LocalizedError {
        case proxyExited
        case badHandshake(String)
        case oversizedFrame

        var errorDescription: String? {
            switch self {
            case .proxyExited: "codex app-server proxy exited"
            case .badHandshake(let response): "WebSocket handshake failed: \(response)"
            case .oversizedFrame: "app-server sent an oversized WebSocket frame"
            }
        }
    }

    var onMessage: (@Sendable (Data) -> Void)?
    var onError: (@Sendable (Error) -> Void)?

    private let codexPath: String
    private let socketPath: String
    private let queue = DispatchQueue(label: "CodexBridge.proxy-websocket")
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var receiveBuffer = Data()
    private var fragmentedMessage = Data()
    private var fragmentedOpcode: UInt8?

    init(codexPath: String, socketPath: String) {
        self.codexPath = codexPath
        self.socketPath = socketPath
    }

    func start() throws {
        let process = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: codexPath)
        process.arguments = ["app-server", "proxy", "--sock", socketPath]
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.standardError
        try process.run()

        self.process = process
        input = stdinPipe.fileHandleForWriting
        output = stdoutPipe.fileHandleForReading

        let key = Data(UUID().uuidString.utf8.prefix(16)).base64EncodedString()
        let request = "GET /rpc HTTP/1.1\r\n"
            + "Host: localhost\r\n"
            + "Upgrade: websocket\r\n"
            + "Connection: Upgrade\r\n"
            + "Sec-WebSocket-Key: \(key)\r\n"
            + "Sec-WebSocket-Version: 13\r\n\r\n"
        try input?.write(contentsOf: Data(request.utf8))

        var response = Data()
        let terminator = Data("\r\n\r\n".utf8)
        while !response.contains(terminator) {
            guard process.isRunning, let byte = try output?.read(upToCount: 1), !byte.isEmpty else {
                throw TransportError.proxyExited
            }
            response.append(byte)
            if response.count > 16 * 1024 {
                throw TransportError.badHandshake("response headers exceeded 16 KiB")
            }
        }
        let responseText = String(decoding: response, as: UTF8.self)
        guard responseText.hasPrefix("HTTP/1.1 101 ") else {
            throw TransportError.badHandshake(responseText.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        output?.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                self?.onError?(TransportError.proxyExited)
                return
            }
            guard let transport = self else { return }
            transport.queue.async { transport.consume(data) }
        }
    }

    func send(text: String) {
        let frame = WebSocketFrameCodec.clientFrame(opcode: 0x1, payload: Data(text.utf8))
        queue.async { [weak self] in
            do {
                try self?.input?.write(contentsOf: frame)
            } catch {
                self?.onError?(error)
            }
        }
    }

    func stop() {
        output?.readabilityHandler = nil
        input?.closeFile()
        output?.closeFile()
        if process?.isRunning == true { process?.terminate() }
    }

    private func consume(_ data: Data) {
        receiveBuffer.append(data)
        do {
            while let frame = try WebSocketFrameCodec.popServerFrame(from: &receiveBuffer) {
                switch frame.opcode {
                case 0x0:
                    fragmentedMessage.append(frame.payload)
                    if frame.final {
                        if fragmentedOpcode == 0x1 { onMessage?(fragmentedMessage) }
                        fragmentedMessage.removeAll(keepingCapacity: true)
                        fragmentedOpcode = nil
                    }
                case 0x1:
                    if frame.final {
                        onMessage?(frame.payload)
                    } else {
                        fragmentedOpcode = frame.opcode
                        fragmentedMessage = frame.payload
                    }
                case 0x8:
                    onError?(TransportError.proxyExited)
                case 0x9:
                    try input?.write(contentsOf: WebSocketFrameCodec.clientFrame(opcode: 0xA, payload: frame.payload))
                default:
                    break
                }
            }
        } catch {
            onError?(error)
        }
    }
}

struct WebSocketFrame: Equatable {
    let final: Bool
    let opcode: UInt8
    let payload: Data
}

enum WebSocketFrameCodec {
    static func clientFrame(opcode: UInt8, payload: Data) -> Data {
        var result = Data([0x80 | opcode])
        let count = payload.count
        if count < 126 {
            result.append(UInt8(0x80 | count))
        } else if count <= Int(UInt16.max) {
            result.append(0x80 | 126)
            appendBigEndian(UInt64(count), byteCount: 2, to: &result)
        } else {
            result.append(0x80 | 127)
            appendBigEndian(UInt64(count), byteCount: 8, to: &result)
        }

        var generator = SystemRandomNumberGenerator()
        let mask = (0..<4).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        result.append(contentsOf: mask)
        result.append(contentsOf: payload.enumerated().map { index, byte in byte ^ mask[index % 4] })
        return result
    }

    static func popServerFrame(from buffer: inout Data) throws -> WebSocketFrame? {
        guard buffer.count >= 2 else { return nil }
        let first = buffer[buffer.startIndex]
        let second = buffer[buffer.startIndex + 1]
        let masked = second & 0x80 != 0
        var payloadLength = UInt64(second & 0x7F)
        var cursor = 2

        if payloadLength == 126 {
            guard buffer.count >= cursor + 2 else { return nil }
            payloadLength = readBigEndian(buffer, offset: cursor, byteCount: 2)
            cursor += 2
        } else if payloadLength == 127 {
            guard buffer.count >= cursor + 8 else { return nil }
            payloadLength = readBigEndian(buffer, offset: cursor, byteCount: 8)
            cursor += 8
        }
        guard payloadLength <= 16 * 1024 * 1024 else {
            throw ProxyAppServerTransport.TransportError.oversizedFrame
        }

        let maskLength = masked ? 4 : 0
        guard buffer.count >= cursor + maskLength + Int(payloadLength) else { return nil }
        let start = buffer.startIndex
        let mask = masked ? Array(buffer[(start + cursor)..<(start + cursor + 4)]) : []
        cursor += maskLength
        var payload = Data(buffer[(start + cursor)..<(start + cursor + Int(payloadLength))])
        if masked {
            for index in payload.indices {
                payload[index] ^= mask[payload.distance(from: payload.startIndex, to: index) % 4]
            }
        }
        buffer.removeFirst(cursor + Int(payloadLength))
        return WebSocketFrame(final: first & 0x80 != 0, opcode: first & 0x0F, payload: payload)
    }

    private static func appendBigEndian(_ value: UInt64, byteCount: Int, to data: inout Data) {
        for shift in stride(from: (byteCount - 1) * 8, through: 0, by: -8) {
            data.append(UInt8((value >> UInt64(shift)) & 0xFF))
        }
    }

    private static func readBigEndian(_ data: Data, offset: Int, byteCount: Int) -> UInt64 {
        (0..<byteCount).reduce(0) { value, index in
            (value << 8) | UInt64(data[data.startIndex + offset + index])
        }
    }
}
