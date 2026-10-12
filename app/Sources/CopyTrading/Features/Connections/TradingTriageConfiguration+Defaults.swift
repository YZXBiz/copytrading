import DesktopCore

extension TradingTriageConfiguration {
    /// OpenAI's decision model, the chat filter Connections offers. Its 0.9 bar sits well above
    /// the surest wrong "chat" seen on guru slang (跑路了 at 0.57), so only plain small talk skips
    /// the reader.
    static let openAIDecisions = TradingTriageConfiguration(provider: .openAIDecisions, model: "gpt-6-luna")
}
