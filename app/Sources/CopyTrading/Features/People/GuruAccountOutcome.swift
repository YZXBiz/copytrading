import DesktopCore
import Foundation

/// What one account did with one of a guru's posts, short enough for a feed row:
/// "primary · Not bought: the price ran above your limit", "ira · Bought $599.45".
struct GuruAccountOutcome: Equatable, Identifiable {
    enum Kind: Equatable {
        case traded
        case notTraded
        case waiting
        case working
        case settled
    }

    let accountID: String
    let summary: String
    let kind: Kind

    var id: String { accountID }

    /// One line per account the post reached, in the post's own order, worded as the Activity card words it.
    @MainActor
    static func outcomes(of item: SourceActivity, skipped: Bool, now: Date = .now) -> [Self] {
        let card = ActivityCardOutcome(item, skipped: skipped, now: now)
        return zip(item.destinations, card.accounts).map { destination, account in
            let first = account.results.first?.headline ?? DestinationOutcome(destination).detail
            let summary =
                account.results.count > 1 ? L10n.string("%@ and %lld more", first, Int64(account.results.count - 1)) : first
            return Self(accountID: destination.accountID, summary: summary, kind: kind(destination, waits: account))
        }
    }

    @MainActor
    private static func kind(_ destination: DestinationActivity, waits account: ActivityCardOutcome.Account) -> Kind {
        if account.waits || account.awaitsResume { return .waiting }
        let orders = destination.orders.map { DestinationOutcome.order($0, count: 1) }
        if orders.contains(where: \.isFill) { return .traded }
        if orders.contains(where: \.isOpen) { return .working }
        let skipped =
            !orders.isEmpty
            || destination.instructionOutcomes.contains { !ActivityCardOutcome.carriedOn.contains($0) }
            || ["stale", "out_of_order", "ignored"].contains(destination.status)
        return skipped ? .notTraded : .settled
    }
}

extension DestinationOutcome {
    fileprivate var isFill: Bool {
        switch self {
        case .filled, .partlyFilled: true
        default: false
        }
    }

    fileprivate var isOpen: Bool {
        switch self {
        case .working, .needsReview: true
        default: false
        }
    }
}
