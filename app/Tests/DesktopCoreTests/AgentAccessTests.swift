import DesktopCore
import Foundation

func runAgentAccessTests() async throws {
    try agentAccessIsRememberedPrivately()
    try agentProposalsAndAuditDecodeFromTheEngine()
    try await approvalNeedsAFreshOwnerConfirmation()
}

private func agentAccessIsRememberedPrivately() throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "copytrading-agent-access-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = AgentAccessStore(stateRoot: root)

    let initial = try store.load()
    try verify(initial == .off, "agents must be off until the owner chooses otherwise")
    try store.save(.propose)
    let saved = try store.load()
    try verify(saved == .propose, "the owner's choice must survive a restart")
    let mode = try FileManager.default.attributesOfItem(atPath: store.url.path)[.posixPermissions] as? NSNumber
    try verify(mode?.intValue == 0o600, "the access setting must be owner-only")

    try Data("{\"access\":\"everything\"}".utf8).write(to: store.url)
    try verifyThrows(
        { _ = try store.load() },
        matching: { ($0 as? AgentAccessStoreError) == .invalidSetting },
        "an unknown saved level must never grant access")

    try FileManager.default.removeItem(at: store.url)
    let elsewhere = root.appending(path: "elsewhere.json")
    try Data("{\"access\":\"propose\"}".utf8).write(to: elsewhere)
    try FileManager.default.createSymbolicLink(at: store.url, withDestinationURL: elsewhere)
    try verifyThrows(
        { _ = try store.load() },
        matching: { ($0 as? AgentAccessStoreError) == .unsafeLocation },
        "a symlinked setting must never grant access")
}

private func agentProposalsAndAuditDecodeFromTheEngine() throws {
    let decoder = JSONDecoder()
    let listed = try decoder.decode(EngineResponse.self, from: contractFixture("agent-proposals-response.json"))
    guard case .agentProposals(let proposals) = listed.success?.result else {
        throw VerificationFailure(description: "proposal list did not decode")
    }
    try verify(
        proposals.count == 2 && proposals.allSatisfy { $0.state == .pending },
        "both waiting proposals must decode")
    try verify(
        proposals[0].subject == .resumeAccount(accountID: "paper"),
        "a resume proposal must name its account")
    guard case .manualOrder(let order) = proposals[1].subject else {
        throw VerificationFailure(description: "the manual order proposal lost its order")
    }
    try verify(
        order.symbol == "ABC" && order.quantity == "12" && order.limitPrice == "25.00"
            && order.environment == .paper,
        "the owner must see exactly the previewed order")
    try verify(
        proposals[0].requestedBy.path == "/usr/bin/agent" && proposals[0].digest.count == 64,
        "the requester and digest must reach the approval sheet")

    let single = try decoder.decode(EngineResponse.self, from: contractFixture("agent-proposal-response.json"))
    guard case .agentProposal(let proposal) = single.success?.result else {
        throw VerificationFailure(description: "a single proposal did not decode")
    }
    try verify(proposal.id.hasPrefix("p-"), "a proposal must keep its identifier")

    let audit = try decoder.decode(EngineResponse.self, from: contractFixture("agent-audit-response.json"))
    guard case .agentAudit(let entries) = audit.success?.result else {
        throw VerificationFailure(description: "the audit trail did not decode")
    }
    try verify(
        entries.contains { $0.operation == "propose_manual_order" && $0.outcome == "proposed" },
        "the audit trail must list agent proposals")
    try verify(Set(entries.map(\.id)).count == entries.count, "audit rows need distinct identities")
}

private func approvalNeedsAFreshOwnerConfirmation() async throws {
    let authenticator = ControlledOwnerAuthenticator()
    let unlock = AppUnlock(authenticator: authenticator)

    do {
        try await unlock.confirm(localizedReason: "Approve")
        throw VerificationFailure(description: "a locked app confirmed an approval")
    } catch AppUnlockError.authenticationCancelled {
        // Expected: approvals need an unlocked app.
    }

    let window = UUID()
    let opening = Task { try await unlock.openWindow(window) }
    try await waitForAuthenticationCalls(1, from: authenticator)
    await authenticator.complete()
    try await opening.value

    let confirming = Task { try await unlock.confirm(localizedReason: "Approve") }
    try await waitForAuthenticationCalls(2, from: authenticator)
    await authenticator.complete()
    try await confirming.value

    let interrupted = Task { try await unlock.confirm(localizedReason: "Approve") }
    try await waitForAuthenticationCalls(3, from: authenticator)
    await unlock.lock()
    await authenticator.complete()
    do {
        try await interrupted.value
        throw VerificationFailure(description: "locking during the prompt still confirmed the approval")
    } catch AppUnlockError.authenticationCancelled {
        // Expected: a lock cancels a pending confirmation.
    }
}
