/// The five things a first setup needs, in the order the guide walks through them.
enum SetupStep: Int, CaseIterable, Identifiable, Hashable {
    case discord
    case interpreter
    case account
    case guru
    case start

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .discord: "Connect Discord"
        case .interpreter: "Choose an interpreter"
        case .account: "Add a broker account"
        case .guru: "Pick who to copy"
        case .start: "Check and start copying"
        }
    }

    /// One word for the step, where the steps are drawn as a route.
    var shortTitle: String {
        switch self {
        case .discord: "Discord"
        case .interpreter: "Interpreter"
        case .account: "Account"
        case .guru: "Guru"
        case .start: "Start"
        }
    }

    var detail: String {
        switch self {
        case .discord: "The channels your gurus post in, and the token CopyTrading reads them with."
        case .interpreter: "The AI model that turns each post into an exact order."
        case .account: "Where orders go. Start with an Alpaca paper account: it trades pretend money at real prices."
        case .guru: "Each guru's channel, how to read their calls, and how much each account puts in."
        case .start:
            "CopyTrading tests every connection and reads your examples while you watch. Nothing is saved or traded before this."
        }
    }

    var symbol: String {
        switch self {
        case .discord: "bubble.left.and.text.bubble.right"
        case .interpreter: "sparkles"
        case .account: "building.columns"
        case .guru: "person.crop.circle.badge.checkmark"
        case .start: "play.circle"
        }
    }
}
