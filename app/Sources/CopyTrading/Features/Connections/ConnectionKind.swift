/// The outside services CopyTrading connects to, each a section of Connections.
enum ConnectionKind: String, CaseIterable, Identifiable, Hashable {
    case discord
    case interpreter
    case alerts

    var id: String { rawValue }

    /// The section's name in Connections.
    @MainActor var title: String {
        switch self {
        case .discord: L10n.string("Discord")
        case .interpreter: L10n.string("Interpreter")
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
        case .alerts: L10n.string("Optional: a message in Telegram or a Discord channel for every order and problem.")
        }
    }
}
