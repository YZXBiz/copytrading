/// The outside services CopyTrading connects to, each a section of Connections.
enum ConnectionKind: String, CaseIterable, Identifiable, Hashable {
    case discord
    case interpreter
    /// The decision model that sorts small talk out before the interpreter reads (ADR-0012).
    case chatFilter
    case alerts

    var id: String { rawValue }

    /// The section's name in Connections.
    @MainActor var title: String {
        switch self {
        case .discord: L10n.string("Discord")
        case .interpreter: L10n.string("Interpreter")
        case .chatFilter: L10n.string("Chat filter")
        case .alerts: L10n.string("Alerts")
        }
    }

    /// One plain sentence under the section's name: what the service does for you.
    @MainActor var explanation: String {
        switch self {
        case .discord: L10n.string("Where your gurus post their calls. CopyTrading reads the channels as you.")
        case .interpreter:
            L10n.string(
                "The AI model that reads each post. A service uses your own key and bills you for what it reads; a model on this Mac costs nothing."
            )
        case .chatFilter:
            L10n.string(
                "Skips small talk before the interpreter reads it, whichever one you use. About 15¢ per 1,000 posts on your OpenAI key.")
        case .alerts: L10n.string("A message in Telegram or a Discord channel for every order and problem.")
        }
    }
}
