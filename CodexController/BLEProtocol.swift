import CoreBluetooth
import Foundation

enum CodexBLE {
    static let serviceUUID = CBUUID(string: "7D2A0001-8F6B-4A7A-9C31-4B746B994001")
    static let commandUUID = CBUUID(string: "7D2A0002-8F6B-4A7A-9C31-4B746B994001")
    static let statusUUID = CBUUID(string: "7D2A0003-8F6B-4A7A-9C31-4B746B994001")
}

enum CodexCommand: UInt8 {
    case fast = 0x01
    case normal = 0x02
    case deep = 0x03
    case newTask = 0x10
    case review = 0x11
    case stop = 0x12
    case modelSol = 0x20
    case modelTerra = 0x21
    case modelLuna = 0x22
}

enum CodexStatus: UInt8, Sendable {
    case disconnected = 0x00
    case idle = 0x01
    case working = 0x02
    case waitingForUser = 0x03
    case done = 0x04
    case error = 0x05
    case awaitingApproval = 0x06

    var label: String {
        switch self {
        case .disconnected: "Disconnected"
        case .idle: "Idle"
        case .working: "Working"
        case .waitingForUser: "Waiting for user"
        case .done: "Done"
        case .error: "Error"
        case .awaitingApproval: "Approval required"
        }
    }
}

enum ReasoningLevel: UInt8, Sendable {
    case unknown = 0x00
    case low = 0x01
    case medium = 0x02
    case high = 0x03
    case xhigh = 0x04

    var label: String {
        switch self {
        case .unknown: "Unknown"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        case .xhigh: "Extra High"
        }
    }
}

enum CodexModel: UInt8, CaseIterable, Identifiable, Sendable {
    case unknown = 0x00
    case sol = 0x01
    case terra = 0x02
    case luna = 0x03

    var id: UInt8 { rawValue }

    static var selectable: [CodexModel] { [.sol, .terra, .luna] }

    var label: String {
        switch self {
        case .unknown: "Unknown"
        case .sol: "Sol"
        case .terra: "Terra"
        case .luna: "Luna"
        }
    }

    var command: CodexCommand? {
        switch self {
        case .unknown: nil
        case .sol: .modelSol
        case .terra: .modelTerra
        case .luna: .modelLuna
        }
    }
}
