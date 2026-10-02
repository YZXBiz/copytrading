/// The Settings sidebar's groups, each under its own heading.
enum SettingsPageGroup: String, CaseIterable, Identifiable {
    case general
    case engine
    case data

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General Settings"
        case .engine: "Engine & Agents"
        case .data: "Your Data"
        }
    }

    var pages: [SettingsPage] {
        switch self {
        case .general: [.general, .appearance, .updates]
        case .engine: [.engine, .agents]
        case .data: [.backups, .logs]
        }
    }
}
