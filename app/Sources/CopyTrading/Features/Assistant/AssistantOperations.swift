import DesktopCore

/// What the assistant needs from the engine: ask, read the answer so far, cancel, and forget.
protocol AssistantOperations: Sendable {
    func assistantAsk(
        conversationID: String, text: String, context: AssistantAskContext,
        provider: TradingProviderConfiguration, providerAPIKey: String
    ) async throws -> String
    func assistantTurn(turnID: String, after: Int) async throws -> AssistantTurnPage
    func assistantCancel(turnID: String) async throws -> Bool
    func assistantReset() async throws
}

extension EngineActions: AssistantOperations {}
