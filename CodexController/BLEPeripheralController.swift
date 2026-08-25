import CoreBluetooth
import Combine
import Foundation

@MainActor
final class BLEPeripheralController: NSObject, ObservableObject {
    @Published private(set) var bluetoothState = "Starting…"
    @Published private(set) var isConnected = false
    @Published private(set) var status: CodexStatus = .disconnected
    @Published private(set) var reasoning: ReasoningLevel = .unknown
    @Published private(set) var model: CodexModel = .unknown

    private var manager: CBPeripheralManager!
    private var commandCharacteristic: CBMutableCharacteristic?
    private var statusCharacteristic: CBMutableCharacteristic?
    private var pendingCommand: Data?
    private var lastBridgeActivity: Date?
    private var connectionWatchdog: Timer?

    private static let bridgeTimeout: TimeInterval = 6

    override init() {
        super.init()
        manager = CBPeripheralManager(delegate: self, queue: nil)
        connectionWatchdog = Timer.scheduledTimer(
            timeInterval: 1,
            target: self,
            selector: #selector(checkBridgeHeartbeat),
            userInfo: nil,
            repeats: true
        )
    }

    func send(_ command: CodexCommand) {
        guard isConnected, let commandCharacteristic else { return }
        let packet = Data([command.rawValue])
        if !manager.updateValue(packet, for: commandCharacteristic, onSubscribedCentrals: nil) {
            pendingCommand = packet
        }
    }

    func selectModel(_ model: CodexModel) {
        guard let command = model.command else { return }
        send(command)
    }

    private func publishService() {
        let command = CBMutableCharacteristic(
            type: CodexBLE.commandUUID,
            properties: [.read, .notify],
            value: nil,
            permissions: [.readable]
        )
        let status = CBMutableCharacteristic(
            type: CodexBLE.statusUUID,
            properties: [.read, .write, .writeWithoutResponse],
            value: nil,
            permissions: [.readable, .writeable]
        )
        let service = CBMutableService(type: CodexBLE.serviceUUID, primary: true)
        service.characteristics = [command, status]
        commandCharacteristic = command
        statusCharacteristic = status
        manager.add(service)
    }

    private func applyStatusPacket(_ data: Data) {
        guard let statusByte = data.first, let nextStatus = CodexStatus(rawValue: statusByte) else { return }
        lastBridgeActivity = Date()
        isConnected = true
        bluetoothState = "Connected"
        status = nextStatus
        if data.count > 1, let nextReasoning = ReasoningLevel(rawValue: data[data.startIndex + 1]) {
            reasoning = nextReasoning
        }
        if data.count > 2, let nextModel = CodexModel(rawValue: data[data.startIndex + 2]) {
            model = nextModel
        }
    }

    private func expireStaleConnection(now: Date = Date()) {
        guard isConnected,
              let lastBridgeActivity,
              now.timeIntervalSince(lastBridgeActivity) > Self.bridgeTimeout else { return }
        self.lastBridgeActivity = nil
        isConnected = false
        bluetoothState = "Waiting for bridge"
        status = .disconnected
    }

    @objc private func checkBridgeHeartbeat() {
        expireStaleConnection()
    }
}

extension BLEPeripheralController: CBPeripheralManagerDelegate {
    nonisolated func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        Task { @MainActor in
            switch peripheral.state {
            case .poweredOn:
                bluetoothState = "Advertising"
                publishService()
            case .poweredOff: bluetoothState = "Bluetooth is off"
            case .unauthorized: bluetoothState = "Bluetooth permission denied"
            case .unsupported: bluetoothState = "Bluetooth unsupported"
            default: bluetoothState = "Bluetooth unavailable"
            }
        }
    }

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        Task { @MainActor in
            guard error == nil else {
                bluetoothState = "Service error"
                status = .error
                return
            }
            manager.startAdvertising([
                CBAdvertisementDataServiceUUIDsKey: [CodexBLE.serviceUUID],
                CBAdvertisementDataLocalNameKey: "Codex Remote"
            ])
        }
    }

    nonisolated func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didSubscribeTo characteristic: CBCharacteristic
    ) {
        Task { @MainActor in
            isConnected = true
            bluetoothState = "Connected"
            status = .idle
            lastBridgeActivity = Date()
        }
    }

    nonisolated func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didUnsubscribeFrom characteristic: CBCharacteristic
    ) {
        Task { @MainActor in
            isConnected = false
            bluetoothState = "Advertising"
            status = .disconnected
            lastBridgeActivity = nil
        }
    }

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        Task { @MainActor in
            if request.characteristic.uuid == CodexBLE.statusUUID {
                request.value = Data([status.rawValue, reasoning.rawValue, model.rawValue])
                manager.respond(to: request, withResult: .success)
            } else {
                manager.respond(to: request, withResult: .requestNotSupported)
            }
        }
    }

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        Task { @MainActor in
            for request in requests where request.characteristic.uuid == CodexBLE.statusUUID {
                if let value = request.value { applyStatusPacket(value) }
                manager.respond(to: request, withResult: .success)
            }
        }
    }

    nonisolated func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        Task { @MainActor in
            guard let pendingCommand, let commandCharacteristic else { return }
            if manager.updateValue(pendingCommand, for: commandCharacteristic, onSubscribedCentrals: nil) {
                self.pendingCommand = nil
            }
        }
    }
}
