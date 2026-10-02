import DesktopCore
import Foundation

@MainActor
func runAssistantProposalTests() async throws {
    try await decidingAnAssistantProposalClearsTheSheetWithAgentAccessOff()
    try await lockingDropsProposalsWithAgentAccessOff()
    try await lockingStopsTheAssistantBeforeDiscardingProposals()
    try await anEngineExitForgetsTheConversationAndProposals()
    try theApprovalSheetNamesTheAssistant()
    print("CopyTradingContractTests: assistant proposals clear after a decision, on lock, and when the engine exits")
}

private struct ProposalFailure: Error, CustomStringConvertible {
    let description: String
}

private func verifyProposal(_ condition: Bool, _ message: String) throws {
    guard condition else { throw ProposalFailure(description: message) }
}

private struct AllowingOwner: AppOwnerAuthenticator {
    func authenticate(localizedReason: String) async throws {}
    func invalidate() async {}
}

private func proposal(_ id: String, state: String, path: String? = nil) throws -> AgentProposal {
    let requester = path.map { "\"\($0)\"" } ?? "null"
    return try JSONDecoder().decode(
        AgentProposal.self,
        from: Data(
            """
            {"proposal_id":"\(id)","state":"\(state)","digest":"d-\(id)","created_at":"2026-10-01T15:00:00Z",\
            "expires_at":"2026-10-01T15:05:00Z","requested_by":{"pid":null,"path":\(requester)},"outcome":null,\
            "subject":{"kind":"resume_account","account_id":"primary"}}
            """.utf8))
}

@MainActor
private func theApprovalSheetNamesTheAssistant() throws {
    let assistant = try proposal("a", state: "pending", path: "CopyTrading Assistant")
    try verifyProposal(
        assistant.approvalHeading == "The assistant is asking for approval",
        "the assistant's request was headed \(assistant.approvalHeading)")
    try verifyProposal(assistant.requester == "CopyTrading Assistant", "the assistant was named \(assistant.requester)")
    for other in [nil, "/usr/local/bin/some-agent"] {
        let heading = try proposal("b", state: "pending", path: other).approvalHeading
        try verifyProposal(heading == "An agent is asking for approval", "another caller was headed \(heading)")
    }
    let preference = AppLanguagePreference.shared
    let original = preference.language
    defer { preference.select(original) }
    preference.select(.simplifiedChinese)
    try verifyProposal(
        assistant.approvalHeading == "助手请求批准" && assistant.requester == "CopyTrading 助手",
        "in 简体中文 the assistant's request read \(assistant.approvalHeading), from \(assistant.requester)")
}

/// The order in which the engine heard about a lock.
private actor EngineLog {
    private(set) var entries: [String] = []
    func record(_ entry: String) { entries.append(entry) }
}

/// The engine's assistant, which only records that it was told to forget.
private struct ForgettingAssistant: AssistantOperations {
    let log: EngineLog

    func assistantAsk(
        conversationID: String, text: String, context: AssistantAskContext,
        provider: TradingProviderConfiguration, providerAPIKey: String
    ) async throws -> String { "t-1" }
    func assistantTurn(turnID: String, after: Int) async throws -> AssistantTurnPage {
        AssistantTurnPage(turnID: turnID, done: true, events: [])
    }
    func assistantCancel(turnID: String) async throws -> Bool { true }
    func assistantReset() async throws { await log.record("assistant_reset") }
}

/// The engine's queue: a proposal stays pending until it is decided or discarded.
private actor FakeQueue: AgentProposalOperations {
    private var states: [String: String]
    private(set) var discards = 0
    private let log: EngineLog?

    init(pending ids: [String], log: EngineLog? = nil) {
        states = Dictionary(uniqueKeysWithValues: ids.map { ($0, "pending") })
        self.log = log
    }

    func agentProposals() async throws -> [AgentProposal] {
        try states.keys.sorted().map { try proposal($0, state: states[$0] ?? "pending") }
    }

    func approveProposal(id: String, digest: String) async throws -> AgentProposal {
        states[id] = "succeeded"
        return try proposal(id, state: "succeeded")
    }

    func rejectProposal(id: String) async throws -> AgentProposal {
        states[id] = "rejected"
        return try proposal(id, state: "rejected")
    }

    func discardProposals() async throws -> Int {
        await log?.record("discard_proposals")
        discards += 1
        states = states.filter { $0.value != "pending" }
        return 0
    }
}

@MainActor
private func unlockedModel(_ queue: FakeQueue) async throws -> AppModel {
    let model = AppModel(
        appUnlock: AppUnlock(authenticator: AllowingOwner(), ownerCheckRequired: false), agentProposalOperations: queue)
    await model.windowDidOpen(UUID())?.value
    try verifyProposal(model.isTradingUnlocked, "The test model did not unlock")
    try verifyProposal(!model.isAgentRelayListening, "Agent access should be off in this check")
    return model
}

@MainActor
private func decidingAnAssistantProposalClearsTheSheetWithAgentAccessOff() async throws {
    let queue = FakeQueue(pending: ["p-1", "p-2"])
    let model = try await unlockedModel(queue)
    await model.refreshAssistantProposals()
    guard let first = model.pendingAgentProposal else { throw ProposalFailure(description: "The proposal did not open the sheet") }
    await model.approveAgentProposal(first)
    try verifyProposal(
        model.pendingAgentProposal?.id == "p-2", "Approving left the decided proposal pending: \(model.agentProposals.map(\.state))")
    guard let second = model.pendingAgentProposal else { throw ProposalFailure(description: "The second proposal vanished") }
    await model.rejectAgentProposal(second)
    try verifyProposal(model.pendingAgentProposal == nil, "Rejecting left the sheet up")
}

@MainActor
private func lockingDropsProposalsWithAgentAccessOff() async throws {
    let queue = FakeQueue(pending: ["p-1"])
    let model = try await unlockedModel(queue)
    await model.refreshAssistantProposals()
    try verifyProposal(model.pendingAgentProposal != nil, "The proposal did not load")
    await model.lockAccess()
    try verifyProposal(model.agentProposals.isEmpty, "Locking kept a proposal on screen")
    let discards = await queue.discards
    try verifyProposal(discards == 1, "Locking did not ask the engine to discard proposals: \(discards)")
}

/// A turn still running could propose after the discard, so the assistant is stopped first; the
/// panel is closed so the next unlock starts without it.
@MainActor
private func lockingStopsTheAssistantBeforeDiscardingProposals() async throws {
    let log = EngineLog()
    let model = try await unlockedModel(FakeQueue(pending: ["p-1"], log: log))
    model.assistant.connect(
        operations: { ForgettingAssistant(log: log) }, interpreter: { nil }, hasModel: { false }, refreshProposals: {})
    model.assistant.isOpen = true
    await model.lockAccess()
    let entries = await log.entries
    try verifyProposal(
        entries == ["assistant_reset", "discard_proposals"], "Locking told the engine in this order: \(entries)")
    try verifyProposal(!model.assistant.isOpen, "The assistant panel stayed open through a lock")
}

@MainActor
private func anEngineExitForgetsTheConversationAndProposals() async throws {
    let queue = FakeQueue(pending: ["p-1"])
    let model = try await unlockedModel(queue)
    await model.refreshAssistantProposals()
    model.assistant.connect(
        operations: { nil }, interpreter: { nil }, hasModel: { false }, refreshProposals: {})
    await model.assistant.ask("Hello", context: AssistantAskContext(screen: "today"))
    try verifyProposal(model.assistant.messages.count == 2, "The refused question was not kept for this check")
    model.handle(.childExited(child: .engine, status: 1, restarting: true))
    for _ in 0..<100 where !model.assistant.messages.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
    try verifyProposal(model.assistant.messages.isEmpty, "The transcript outlived the engine")
    try verifyProposal(model.agentProposals.isEmpty, "A proposal outlived the engine")
}
