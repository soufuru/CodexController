import Foundation
import Testing
@testable import CodexBridge

@Test func statusPacketEncoding() {
    #expect(StatusPacket(status: .working, effort: .high, model: .sol).data == Data([0x02, 0x03, 0x01]))
    #expect(StatusPacket(status: .awaitingApproval, effort: .medium, model: .luna).data == Data([0x06, 0x02, 0x03]))
}

@Test func commandValuesStayStable() {
    #expect(Command.fast.rawValue == 0x01)
    #expect(Command.deep.rawValue == 0x03)
    #expect(Command.stop.rawValue == 0x12)
    #expect(Command.modelSol.rawValue == 0x20)
    #expect(Command.modelTerra.model == .terra)
}

@Test func modelIdentifiersMatchCodexCatalog() {
    #expect(ModelChoice.sol.identifier == "gpt-5.6-sol")
    #expect(ModelChoice.terra.identifier == "gpt-5.6-terra")
    #expect(ModelChoice.luna.identifier == "gpt-5.6-luna")
    #expect(CodexAppServerClient.modelChoice(for: "gpt-5.6-terra") == .terra)
}

@Test func distinguishesApprovalsFromNormalQuestions() {
    #expect(CodexAppServerClient.isApprovalRequest("item/commandExecution/requestApproval"))
    #expect(CodexAppServerClient.isApprovalRequest("item/fileChange/requestApproval"))
    #expect(CodexAppServerClient.isApprovalRequest("item/permissions/requestApproval"))
    #expect(CodexAppServerClient.isApprovalRequest("execCommandApproval"))
    #expect(!CodexAppServerClient.isApprovalRequest("item/tool/requestUserInput"))
}

@Test func aggregatesActivityAcrossAllThreads() {
    #expect(CodexAppServerClient.aggregateStatus([.working, .done], fallback: .done) == .working)
    #expect(CodexAppServerClient.aggregateStatus([.waitingForUser], fallback: .done) == .waitingForUser)
    #expect(CodexAppServerClient.aggregateStatus([.working, .awaitingApproval], fallback: .done) == .awaitingApproval)
    #expect(CodexAppServerClient.aggregateStatus([], fallback: .done) == .done)
}

@Test func mapsActiveThreadFlagsToVisibleStatus() {
    #expect(CodexAppServerClient.statusForActiveThread(flags: []) == .working)
    #expect(CodexAppServerClient.statusForActiveThread(flags: ["waitingOnUserInput"]) == .waitingForUser)
    #expect(CodexAppServerClient.statusForActiveThread(flags: ["waitingOnApproval"]) == .awaitingApproval)
    #expect(CodexAppServerClient.statusForActiveThread(flags: ["waitingOnUserInput", "waitingOnApproval"]) == .awaitingApproval)
}
