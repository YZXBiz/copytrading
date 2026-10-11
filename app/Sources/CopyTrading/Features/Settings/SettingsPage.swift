/// One page of Settings, listed down a sidebar of their own.
enum SettingsPage: String, CaseIterable, Identifiable, Hashable {
    case general
    case appearance
    case updates
    case engine
    case agents
    case backups
    case logs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .updates: "Updates"
        case .engine: "Engine"
        case .agents: "Agent Access"
        case .backups: "Backups"
        case .logs: "Logs"
        }
    }

    /// The quiet line under the page's title.
    var lede: String {
        switch self {
        case .general: "How CopyTrading opens, and how it tells the time."
        case .appearance: "Light, dark, or as your Mac is set."
        case .updates: "New versions, and when to look for them."
        case .engine: "The local engine that reads posts and places orders."
        case .agents: "What other apps on this Mac may ask CopyTrading to do."
        case .backups: "Copies of your setup, kept on this Mac."
        case .logs: "What the engine wrote down, with keys removed."
        }
    }

    var symbol: String {
        switch self {
        case .general: "switch.2"
        case .appearance: "textformat"
        case .updates: "arrow.down.circle"
        case .engine: "cpu"
        case .agents: "terminal"
        case .backups: "externaldrive"
        case .logs: "doc.text.magnifyingglass"
        }
    }
}
