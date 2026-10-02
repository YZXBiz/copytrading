import DesktopCore
import Foundation

@MainActor
func runAssistantModelTests() async throws {
    try await anAnswerStreamsIntoTheTranscript()
    try await pollingStopsOnceTheAnswerIsDone()
    try await wordsBeforeAStepAndWordsAfterItAreSeparateParagraphs()
    try focusIsRequestedOnlyWhenThePanelIsAlreadyOpen()
    try await resettingDropsTheConversationAndTellsTheEngine()
    try await anErrorEventBecomesPlainText()
    try await aProposalRefreshesTheApprovalsOnce()
    try await anAnswerNeedsAnUnlockedModel()
    try await resettingWhileTheEngineStartsATurnCancelsThatTurn()
    try await aResetDuringAProposalRefreshEndsTheOldPage()
    try await resettingNeedsNoEngine()
    try interpreterResolutionPrefersTheSavedConfiguration()
    print("CopyTradingContractTests: the assistant streams answers by polling, stops, resets on lock, and asks for proposals")
}

private struct AssistantTestFailure: Error, CustomStringConvertible {
    let description: String
}

private func verifyAssistant(_ condition: Bool, _ message: String) throws {
    guard condition else { throw AssistantTestFailure(description: message) }
}

/// Plays a scripted answer: each `turn` call returns the next page, and the last page repeats.
private actor FakeAssistant: AssistantOperations {
    private var pages: [AssistantTurnPage]
    private(set) var turnCalls = 0
    private(set) var resets = 0
    private(set) var cancels: [String] = []
    private(set) var asks: [String] = []
    private(set) var afters: [Int] = []

    private let askDelay: Duration
    private(set) var askStarts = 0

    init(pages: [AssistantTurnPage], askDelay: Duration = .zero) {
        self.pages = pages
        self.askDelay = askDelay
    }

    func assistantAsk(
        conversationID: String, text: String, context: AssistantAskContext,
        provider: TradingProviderConfiguration, providerAPIKey: String
    ) async throws -> String {
        askStarts += 1
        try? await Task.sleep(for: askDelay)
        asks.append("\(conversationID)|\(text)|\(context.screen)|\(provider.model)|\(providerAPIKey)")
        return "t-1"
    }

    func assistantTurn(turnID: String, after: Int) async throws -> AssistantTurnPage {
        turnCalls += 1
        afters.append(after)
        guard pages.count > 1 else { return pages[0] }
        return pages.removeFirst()
    }

    func assistantCancel(turnID: String) async throws -> Bool {
        cancels.append(turnID)
        return true
    }

    func assistantReset() async throws { resets += 1 }
}

private func page(done: Bool, _ events: [AssistantEvent]) -> AssistantTurnPage {
    AssistantTurnPage(turnID: "t-1", done: done, events: events)
}

private let provider = TradingProviderConfiguration(name: .deepseek, model: "deepseek-flash")
private let context = AssistantAskContext(screen: "today")

@MainActor
private func model(
    _ fake: FakeAssistant, interpreter: (TradingProviderConfiguration, String)? = (provider, "key"),
    refreshProposals: @escaping @MainActor () async -> Void = {}
) -> AssistantModel {
    let model = AssistantModel(pollInterval: .milliseconds(20))
    model.connect(
        operations: { fake }, interpreter: { interpreter }, hasModel: { interpreter != nil },
        refreshProposals: refreshProposals)
    return model
}

@MainActor
private func waitUntil(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<250 {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return condition()
}

@MainActor
private func anAnswerStreamsIntoTheTranscript() async throws {
    let fake = FakeAssistant(pages: [
        page(done: false, [AssistantEvent(seq: 1, kind: .step, text: "Looked at Today")]),
        page(
            done: false,
            [AssistantEvent(seq: 2, kind: .text, text: "Hello, "), AssistantEvent(seq: 3, kind: .text, text: "world")]),
        page(
            done: true,
            [
                AssistantEvent(seq: 4, kind: .link, link: AssistantLink(kind: "guru", id: "alex", title: "Alex")),
                AssistantEvent(seq: 5, kind: .done),
            ]),
    ])
    let assistant = model(fake)
    await assistant.ask("How is it going?", context: context)
    try verifyAssistant(await waitUntil { !assistant.isAnswering }, "The answer never finished")
    try verifyAssistant(assistant.messages.count == 2, "An answer is one owner message and one assistant message")
    let owner = assistant.messages[0]
    let answer = assistant.messages[1]
    try verifyAssistant(owner.author == .owner && owner.text == "How is it going?", "The owner message was not kept")
    try verifyAssistant(answer.author == .assistant && answer.text == "Hello, world", "The text events were not joined: \(answer.text)")
    try verifyAssistant(answer.steps == ["Looked at Today"], "The step was not kept")
    try verifyAssistant(answer.links == [AssistantLink(kind: "guru", id: "alex", title: "Alex")], "The link was not kept")
    try verifyAssistant(answer.errorText == nil, "A clean answer carried an error")
    let asks = await fake.asks
    try verifyAssistant(asks.count == 1, "The question was not sent once")
    let parts = asks[0].split(separator: "|").map(String.init)
    try verifyAssistant(
        parts[0].range(of: "^c-[0-9a-f]{12}$", options: .regularExpression) != nil
            && parts[1...] == ["How is it going?", "today", "deepseek-flash", "key"],
        "The question did not carry the conversation, context, model, and key: \(asks[0])")
    let afters = await fake.afters
    try verifyAssistant(
        afters.first == 0 && afters.contains(1) && afters.contains(3), "Polling did not resume after the last event: \(afters)")
}

@MainActor
private func wordsBeforeAStepAndWordsAfterItAreSeparateParagraphs() async throws {
    let fake = FakeAssistant(pages: [
        page(
            done: true,
            [
                AssistantEvent(seq: 1, kind: .text, text: "Let me check."),
                AssistantEvent(seq: 2, kind: .step, text: "Read recent posts"),
                AssistantEvent(seq: 3, kind: .text, text: "Zhao posted twice."),
                AssistantEvent(seq: 4, kind: .done),
            ])
    ])
    let assistant = model(fake)
    await assistant.ask("What happened?", context: context)
    try verifyAssistant(await waitUntil { !assistant.isAnswering }, "The answer never finished")
    try verifyAssistant(
        assistant.messages[1].text == "Let me check.\n\nZhao posted twice.",
        "A step did not start a new paragraph: \(assistant.messages[1].text)")
}

@MainActor
private func focusIsRequestedOnlyWhenThePanelIsAlreadyOpen() throws {
    let assistant = AssistantModel()
    assistant.open()
    try verifyAssistant(assistant.isOpen && assistant.focusRequest == 0, "Opening the panel needs no focus request")
    assistant.open()
    try verifyAssistant(assistant.focusRequest == 1, "A second open did not ask the composer for focus")
}

@MainActor
private func pollingStopsOnceTheAnswerIsDone() async throws {
    let fake = FakeAssistant(pages: [
        page(done: true, [AssistantEvent(seq: 1, kind: .text, text: "Hi"), AssistantEvent(seq: 2, kind: .done)])
    ])
    let assistant = model(fake)
    await assistant.ask("Hi", context: context)
    try verifyAssistant(await waitUntil { !assistant.isAnswering }, "The answer never finished")
    let settled = await fake.turnCalls
    try await Task.sleep(for: .milliseconds(600))
    let later = await fake.turnCalls
    try verifyAssistant(settled == later, "Polling went on after the answer was done: \(settled) then \(later)")
}

@MainActor
private func resettingDropsTheConversationAndTellsTheEngine() async throws {
    let fake = FakeAssistant(pages: [page(done: false, [AssistantEvent(seq: 1, kind: .step, text: "Thinking")])])
    let assistant = model(fake)
    await assistant.ask("Anything", context: context)
    try verifyAssistant(await waitUntil { assistant.messages.last?.steps == ["Thinking"] }, "The answer never started")
    try verifyAssistant(assistant.isAnswering, "A running answer was not marked as answering")
    await assistant.reset()
    try verifyAssistant(assistant.messages.isEmpty, "Reset kept the transcript")
    try verifyAssistant(!assistant.isAnswering, "Reset left the assistant answering")
    let resets = await fake.resets
    try verifyAssistant(resets == 1, "Reset did not tell the engine")
    let calls = await fake.turnCalls
    try await Task.sleep(for: .milliseconds(200))
    let later = await fake.turnCalls
    try verifyAssistant(calls == later, "Polling survived a reset")
    try verifyAssistant(assistant.messages.isEmpty, "A late page wrote into the cleared transcript")
    await assistant.ask("Again", context: context)
    let asks = await fake.asks
    let first = asks[0].split(separator: "|")[0]
    let second = asks[1].split(separator: "|")[0]
    try verifyAssistant(first != second, "A reset did not start a new conversation")
    await assistant.reset()
}

@MainActor
private func anErrorEventBecomesPlainText() async throws {
    let fake = FakeAssistant(pages: [
        page(
            done: true,
            [
                AssistantEvent(seq: 1, kind: .error, text: "The model could not be reached.", code: "model_unreachable"),
                AssistantEvent(seq: 2, kind: .done),
            ])
    ])
    let assistant = model(fake)
    await assistant.ask("Hi", context: context)
    try verifyAssistant(await waitUntil { !assistant.isAnswering }, "The failed answer never finished")
    try verifyAssistant(
        assistant.messages.last?.errorText == "The model could not be reached.", "The error text did not reach the message")
}

@MainActor
private func aProposalRefreshesTheApprovalsOnce() async throws {
    let fake = FakeAssistant(pages: [
        page(done: false, [AssistantEvent(seq: 1, kind: .proposal, proposalID: "p-1")]),
        page(done: true, [AssistantEvent(seq: 2, kind: .done)]),
    ])
    var refreshes = 0
    let assistant = model(fake) { refreshes += 1 }
    await assistant.ask("Pause the engine", context: context)
    try verifyAssistant(await waitUntil { !assistant.isAnswering }, "The answer never finished")
    try await Task.sleep(for: .milliseconds(100))
    try verifyAssistant(refreshes == 1, "A proposal refreshed the approvals \(refreshes) times, not once")
    try verifyAssistant(assistant.messages.last?.proposalIDs == ["p-1"], "The proposal was not kept on the message")
}

@MainActor
private func anAnswerNeedsAnUnlockedModel() async throws {
    let fake = FakeAssistant(pages: [page(done: true, [AssistantEvent(seq: 1, kind: .done)])])
    let assistant = model(fake, interpreter: nil)
    try verifyAssistant(!assistant.hasModel, "A missing model was reported as present")
    await assistant.ask("Hi", context: context)
    let asks = await fake.asks
    try verifyAssistant(asks.isEmpty, "A question was sent without a model")
    try verifyAssistant(!assistant.isAnswering, "A refused question left the assistant answering")
    try verifyAssistant(assistant.messages.last?.errorText != nil, "A refused question gave no reason")
}

@MainActor
private func interpreterResolutionPrefersTheSavedConfiguration() throws {
    var draft = ConnectionsDraft()
    draft.provider = .openai
    draft.modelName = "gpt-draft"
    draft.providerAPIKey = "typed-key"
    let drafted = AppModel.assistantInterpreter(saved: nil, draft: draft)
    try verifyAssistant(
        drafted?.0.name == .openai && drafted?.0.model == "gpt-draft" && drafted?.1 == "typed-key",
        "A complete draft was not used")
    draft.providerAPIKey = ""
    try verifyAssistant(AppModel.assistantInterpreter(saved: nil, draft: draft) == nil, "A draft without its key was used")
    draft.provider = .openAICompatible
    try verifyAssistant(
        AppModel.assistantInterpreter(saved: nil, draft: draft) == nil, "A compatible draft without a base URL was used")
    draft.providerBaseURL = "http://localhost:11434/v1"
    let local = AppModel.assistantInterpreter(saved: nil, draft: draft)
    try verifyAssistant(local?.0.name == .openAICompatible && local?.1 == "", "A keyless local draft was not used")
    draft.modelName = "  "
    try verifyAssistant(AppModel.assistantInterpreter(saved: nil, draft: draft) == nil, "A draft without a model was used")
}

@MainActor
private func resettingWhileTheEngineStartsATurnCancelsThatTurn() async throws {
    let fake = FakeAssistant(
        pages: [page(done: false, [AssistantEvent(seq: 1, kind: .step, text: "Thinking")])], askDelay: .milliseconds(300))
    let assistant = model(fake)
    let asking = Task { await assistant.ask("Slow start", context: context) }
    for _ in 0..<100 where await fake.askStarts == 0 { try await Task.sleep(for: .milliseconds(10)) }
    await assistant.reset()
    await asking.value
    let cancelled = await waitForCancel(fake)
    try verifyAssistant(cancelled == ["t-1"], "A turn started during a reset was left running: \(cancelled)")
    try verifyAssistant(assistant.messages.isEmpty && !assistant.isAnswering, "The late turn came back into the transcript")
    let calls = await fake.turnCalls
    try verifyAssistant(calls == 0, "A turn cancelled before it was read was polled anyway")
}

private func waitForCancel(_ fake: FakeAssistant) async -> [String] {
    for _ in 0..<100 {
        let cancels = await fake.cancels
        if !cancels.isEmpty { return cancels }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return await fake.cancels
}

@MainActor
private func aResetDuringAProposalRefreshEndsTheOldPage() async throws {
    let fake = FakeAssistant(pages: [
        page(done: false, [AssistantEvent(seq: 1, kind: .proposal, proposalID: "p-1"), AssistantEvent(seq: 2, kind: .text, text: "LATE")]),
        page(done: true, [AssistantEvent(seq: 3, kind: .done)]),
    ])
    let box = TestBox()
    let assistant = model(fake) {
        guard !box.refreshed, let holder = box.model else { return }
        box.refreshed = true
        await holder.reset()
        await holder.ask("Second", context: context)
    }
    box.model = assistant
    await assistant.ask("First", context: context)
    try verifyAssistant(await waitUntil { box.refreshed && !assistant.isAnswering }, "The second question never finished")
    try await Task.sleep(for: .milliseconds(100))
    try verifyAssistant(assistant.messages.count == 2, "The new conversation has the wrong messages: \(assistant.messages.count)")
    try verifyAssistant(
        assistant.messages.last?.text == "", "An event from the old page landed in the new message: \(assistant.messages.last?.text ?? "")")
    try verifyAssistant(assistant.messages.last?.proposalIDs == [], "A proposal from the old page landed in the new message")
}

@MainActor
private func resettingNeedsNoEngine() async throws {
    let fake = FakeAssistant(pages: [page(done: false, [AssistantEvent(seq: 1, kind: .step, text: "Thinking")])])
    let box = TestBox()
    let assistant = AssistantModel(pollInterval: .milliseconds(20))
    assistant.connect(
        operations: { box.reachable ? fake : nil }, interpreter: { (provider, "key") }, hasModel: { true }, refreshProposals: {})
    await assistant.ask("Anything", context: context)
    try verifyAssistant(await waitUntil { assistant.messages.last?.steps == ["Thinking"] }, "The answer never started")
    box.reachable = false
    await assistant.reset()
    try verifyAssistant(assistant.messages.isEmpty && !assistant.isAnswering, "A reset with no engine kept the transcript")
    let resets = await fake.resets
    try verifyAssistant(resets == 0, "A reset reached an engine that was not there")
}

@MainActor
private final class TestBox {
    var model: AssistantModel?
    var refreshed = false
    var reachable = true
}
