import DesktopCore

enum ActivityFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case needsReview = "Needs Review"
    case trades = "Trades"

    var id: String { rawValue }

    @MainActor
    var title: String {
        switch self {
        case .all: L10n.string("All")
        case .needsReview: L10n.string("Needs Review")
        case .trades: L10n.string("Trades")
        }
    }

    func includes(_ item: SourceActivity) -> Bool {
        switch self {
        case .all: true
        case .needsReview:
            item.decision == "review" || item.deliveryStatus.contains("review") || WaitingCall(item) != nil
        case .trades: item.decision == "trade"
        }
    }
}
