/// The outside services CopyTrading connects to, each a section of Connections.
enum ConnectionKind: String, CaseIterable, Identifiable, Hashable {
    case discord
    case interpreter
    case alerts

    var id: String { rawValue }

    @MainActor var sectionTitle: String {
        switch self {
        case .discord: L10n.string("Your Discord Connection")
        case .interpreter: L10n.string("Your Interpreter")
        case .alerts: L10n.string("Your Alerts")
        }
    }

    /// What the section is for: under its title once connected, under the offer before that.
    @MainActor var purpose: String {
        switch self {
        case .discord: L10n.string("Where your gurus post their calls")
        case .interpreter: L10n.string("The AI model that reads each post")
        case .alerts: L10n.string("Optional: a Telegram message for every order and problem")
        }
    }

    /// What an empty section offers.
    @MainActor var addTitle: String {
        switch self {
        case .discord: L10n.string("Connect Discord")
        case .interpreter: L10n.string("Choose Your Interpreter")
        case .alerts: L10n.string("Add Telegram Alerts")
        }
    }
}
