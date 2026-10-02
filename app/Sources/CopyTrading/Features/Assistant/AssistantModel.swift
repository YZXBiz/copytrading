import DesktopCore
import Foundation
import Observation

/// The owner's conversation with the assistant: the question goes to the engine, and the answer is
/// read back by polling while it is being written. Nothing here outlives a lock, a quit, or a stop.
@MainActor @Observable
final class AssistantModel {
    var isOpen = false
    private(set) var messages: [AssistantMessage] = []
    private(set) var isAnswering = false
    /// Bumped by ⌘J so an open panel takes the keyboard back to its composer.
    private(set) var focusRequest = 0

    @ObservationIgnored private let pollInterval: Duration
    @ObservationIgnored private var conversationID = AssistantModel.newConversationID()
    @ObservationIgnored private var turnID: String?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    /// Set when a step line interrupts written text, so the words after it start a new paragraph.
    @ObservationIgnored private var breakBeforeText = false
    /// Bumped by every reset, so a page that arrives after one is dropped.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var operations: @MainActor () -> (any AssistantOperations)? = { nil }
    @ObservationIgnored private var resolveInterpreter: @MainActor () -> (TradingProviderConfiguration, String)? = { nil }
    @ObservationIgnored private var resolveHasModel: @MainActor () -> Bool = { false }
    @ObservationIgnored private var refreshProposals: @MainActor () async -> Void = {}

    init(pollInterval: Duration = .milliseconds(250)) {
        self.pollInterval = pollInterval
    }

    /// Hands the model what it needs from the app: the running engine, the interpreter to answer
    /// with, a cheap "is there a model" check for the panel, and how to reload approvals.
    func connect(
        operations: @escaping @MainActor () -> (any AssistantOperations)?,
        interpreter: @escaping @MainActor () -> (TradingProviderConfiguration, String)?,
        hasModel: @escaping @MainActor () -> Bool,
        refreshProposals: @escaping @MainActor () async -> Void
    ) {
        self.operations = operations
        resolveInterpreter = interpreter
        resolveHasModel = hasModel
        self.refreshProposals = refreshProposals
    }

    /// The model and key that answer; nil while locked or while no interpreter is set up.
    var interpreter: (TradingProviderConfiguration, String)? { resolveInterpreter() }

    /// Whether an interpreter is set up, without reading the Keychain; the panel shows its "no model" line on false.
    var hasModel: Bool { resolveHasModel() }

    /// Open the panel, or when it is already open, send the keyboard back to its composer.
    func open() {
        if isOpen { focusRequest += 1 } else { isOpen = true }
    }

    func ask(_ text: String, context: AssistantAskContext) async {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isAnswering else { return }
        messages.append(AssistantMessage(author: .owner, text: question))
        messages.append(AssistantMessage(author: .assistant))
        guard let operations = operations(), let (provider, key) = interpreter else {
            fail(L10n.string("Unlock CopyTrading and set up a model under Interpreter in Connections, then ask again."))
            return
        }
        isAnswering = true
        breakBeforeText = false
        let started = generation
        do {
            let turn = try await operations.assistantAsk(
                conversationID: conversationID, text: question, context: context, provider: provider,
                providerAPIKey: key)
            guard started == generation else {
                // A reset landed while the engine was starting this turn; stop it so nothing runs unseen.
                _ = try? await operations.assistantCancel(turnID: turn)
                return
            }
            turnID = turn
            pollTask = Task { [weak self] in await self?.poll(turn: turn, using: operations, generation: started) }
        } catch {
            guard started == generation else { return }
            fail(L10n.string("The assistant could not start: %@", error.localizedDescription))
        }
    }

    /// Asks the engine to stop writing; the answer so far stays, and polling ends on its `done`.
    func stop() async {
        guard isAnswering, let turnID, let operations = operations() else { return }
        _ = try? await operations.assistantCancel(turnID: turnID)
    }

    /// Forgets the conversation here and in the engine: on lock, quit, and engine stop.
    func reset() async {
        generation += 1
        pollTask?.cancel()
        pollTask = nil
        turnID = nil
        messages = []
        isAnswering = false
        conversationID = Self.newConversationID()
        guard let operations = operations() else { return }
        try? await operations.assistantReset()
    }

    private func poll(turn: String, using operations: any AssistantOperations, generation started: Int) async {
        var after = 0
        while !Task.isCancelled {
            let page: AssistantTurnPage
            do {
                page = try await operations.assistantTurn(turnID: turn, after: after)
            } catch {
                guard !Task.isCancelled, started == generation else { return }
                fail(L10n.string("The assistant stopped answering: %@", error.localizedDescription))
                return
            }
            guard !Task.isCancelled, started == generation else { return }
            for event in page.events {
                after = max(after, event.seq)
                await apply(event)
                // Refreshing approvals suspends; a reset during it ends this page.
                guard !Task.isCancelled, started == generation else { return }
            }
            guard started == generation else { return }
            if page.done || page.events.contains(where: { $0.kind == .done }) {
                finish()
                return
            }
            try? await Task.sleep(for: pollInterval)
        }
    }

    private func apply(_ event: AssistantEvent) async {
        guard let index = messages.indices.last, messages[index].author == .assistant else { return }
        switch event.kind {
        case .text:
            guard let text = event.text, !text.isEmpty else { return }
            if breakBeforeText, !messages[index].text.isEmpty { messages[index].text += "\n\n" }
            breakBeforeText = false
            messages[index].text += text
        case .step:
            if let text = event.text { messages[index].steps.append(text) }
            breakBeforeText = true
        case .link: if let link = event.link { messages[index].links.append(link) }
        case .proposal:
            if let id = event.proposalID { messages[index].proposalIDs.append(id) }
            await refreshProposals()
        case .error: messages[index].errorText = event.text ?? L10n.string("The assistant could not answer.")
        case .done: break
        }
    }

    private func fail(_ text: String) {
        if let index = messages.indices.last, messages[index].author == .assistant {
            messages[index].errorText = text
        }
        finish()
    }

    private func finish() {
        isAnswering = false
        pollTask = nil
        turnID = nil
    }

    private static func newConversationID() -> String {
        "c-" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(12)
    }
}
