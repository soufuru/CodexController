import CoreBluetooth
import Foundation

enum BLEIdentifiers {
    static var service: CBUUID { CBUUID(string: "7D2A0001-8F6B-4A7A-9C31-4B746B994001") }
    static var command: CBUUID { CBUUID(string: "7D2A0002-8F6B-4A7A-9C31-4B746B994001") }
    static var status: CBUUID { CBUUID(string: "7D2A0003-8F6B-4A7A-9C31-4B746B994001") }
}

enum Command: UInt8 {
    case fast = 0x01
    case normal = 0x02
    case deep = 0x03
    case fastOff = 0x04
    case deepOff = 0x05
    case newTask = 0x10
    case review = 0x11
    case stop = 0x12
    case modelSol = 0x20
    case modelTerra = 0x21
    case modelLuna = 0x22

    var model: ModelChoice? {
        switch self {
        case .modelSol: .sol
        case .modelTerra: .terra
        case .modelLuna: .luna
        default: nil
        }
    }
}

enum BridgeStatus: UInt8 {
    case disconnected = 0x00, idle = 0x01, working = 0x02
    case waitingForUser = 0x03, done = 0x04, error = 0x05
    case awaitingApproval = 0x06
}

enum Effort: UInt8 {
    case unknown = 0x00, low = 0x01, medium = 0x02, high = 0x03, xhigh = 0x04
}

enum ExecutionMode: UInt8 {
    case unknown = 0x00, standard = 0x01, fast = 0x02, deep = 0x03, fastAndDeep = 0x04

    var isFastEnabled: Bool {
        self == .fast || self == .fastAndDeep
    }

    var isDeepEnabled: Bool {
        self == .deep || self == .fastAndDeep
    }

    func settingFast(_ enabled: Bool) -> ExecutionMode {
        switch (enabled, isDeepEnabled) {
        case (true, true): .fastAndDeep
        case (true, false): .fast
        case (false, true): .deep
        case (false, false): .standard
        }
    }

    func settingDeep(_ enabled: Bool) -> ExecutionMode {
        switch (isFastEnabled, enabled) {
        case (true, true): .fastAndDeep
        case (true, false): .fast
        case (false, true): .deep
        case (false, false): .standard
        }
    }
}

enum ModelChoice: UInt8 {
    case unknown = 0x00, sol = 0x01, terra = 0x02, luna = 0x03

    var identifier: String? {
        switch self {
        case .unknown: nil
        case .sol: "gpt-5.6-sol"
        case .terra: "gpt-5.6-terra"
        case .luna: "gpt-5.6-luna"
        }
    }
}

struct StatusPacket: Equatable {
    let status: BridgeStatus
    let effort: Effort
    let model: ModelChoice
    let executionMode: ExecutionMode

    var data: Data { Data([status.rawValue, effort.rawValue, model.rawValue, executionMode.rawValue]) }
}
