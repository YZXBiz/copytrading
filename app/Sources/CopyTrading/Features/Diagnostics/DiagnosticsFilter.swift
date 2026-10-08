import DesktopCore

/// Which journal records the Diagnostics list shows.
enum DiagnosticsFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case captures = "Captures"
    case trading = "Trading"
    case problems = "Problems"

    var id: String { rawValue }

    var emptyTitle: String {
        switch self {
        case .all: "Nothing logged yet"
        case .captures: "No captured posts or model calls"
        case .trading: "No trading steps yet"
        case .problems: "No problems recorded"
        }
    }

    func includes(_ entry: DiagnosticsJournalEntry) -> Bool {
        switch self {
        case .all: true
        case .captures: entry.kind == .payload
        case .trading: entry.kind == .trading
        case .problems: entry.tone == .caution
        }
    }
}
