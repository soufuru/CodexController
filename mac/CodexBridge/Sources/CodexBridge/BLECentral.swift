import CoreBluetooth
import Foundation

final class BLECentral: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate, @unchecked Sendable {
    private var manager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var statusCharacteristic: CBCharacteristic?
    private let appServer: CodexAppServerClient
    private var pendingStatus = StatusPacket(status: .disconnected, effort: .unknown, model: .unknown)

    init(appServer: CodexAppServerClient) {
        self.appServer = appServer
        super.init()
        appServer.onStatus = { [weak self] packet in self?.write(packet) }
        manager = CBCentralManager(delegate: self, queue: .main)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else {
            print("Bluetooth unavailable: \(central.state.rawValue)")
            return
        }
        print("Scanning for Codex Remote…")
        central.scanForPeripherals(withServices: [BLEIdentifiers.service])
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        self.peripheral = peripheral
        peripheral.delegate = self
        central.stopScan()
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("Connected to \(peripheral.name ?? "iPhone")")
        peripheral.discoverServices([BLEIdentifiers.service])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                        timestamp: CFAbsoluteTime, isReconnecting: Bool, error: Error?) {
        statusCharacteristic = nil
        self.peripheral = nil
        central.scanForPeripherals(withServices: [BLEIdentifiers.service])
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        peripheral.services?.forEach { peripheral.discoverCharacteristics(
            [BLEIdentifiers.command, BLEIdentifiers.status], for: $0
        ) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for characteristic in service.characteristics ?? [] {
            if characteristic.uuid == BLEIdentifiers.command {
                peripheral.setNotifyValue(true, for: characteristic)
            } else if characteristic.uuid == BLEIdentifiers.status {
                statusCharacteristic = characteristic
                write(pendingStatus)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == BLEIdentifiers.command,
              let byte = characteristic.value?.first,
              let command = Command(rawValue: byte) else { return }
        print("Received command 0x\(String(byte, radix: 16))")
        appServer.handle(command)
    }

    private func write(_ packet: StatusPacket) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            pendingStatus = packet
            guard let peripheral, let characteristic = statusCharacteristic else { return }
            let type: CBCharacteristicWriteType = characteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
            peripheral.writeValue(packet.data, for: characteristic, type: type)
        }
    }
}
