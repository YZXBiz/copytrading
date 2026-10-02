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
