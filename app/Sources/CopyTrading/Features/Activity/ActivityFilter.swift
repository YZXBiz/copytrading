import DesktopCore
import Foundation

enum ActivityFilter: String, CaseIterable, Identifiable {
    case all = "All posts"
    case waiting = "Needs you"
    case trades = "Traded"

    var id: String { rawValue }

    @MainActor
    var title: String {
        switch self {
        case .all: L10n.string("All posts")
        case .waiting: L10n.string("Needs you")
        case .trades: L10n.string("Traded")
        }
    }

    /// Waiting for You lists the posts the owner can still copy or skip (ADR-0007).
    @MainActor
    func includes(_ item: SourceActivity, skipped: SkippedCalls?, now: Date = .now) -> Bool {
        switch self {
        case .all: true
        case .waiting:
            WaitingCall.open(item, skipped: skipped?.contains(item.sourceID) == true, now: now) != nil
        case .trades: item.decision == "trade"
        }
    }
}
