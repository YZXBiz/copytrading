import DesktopCore
import Foundation

/// Why an order ended without filling, in the owner's words and with its numbers: how long it
/// waited, the limit it carried, what the market offered when it went out, and the setting
/// behind the limit.
enum CancelReasonText {
    /// One full sentence for the card and the timeline; nil when the order did not end unfilled.
    @MainActor
    static func sentence(_ order: OrderActivity) -> String? {
        guard let reason = order.cancelReason else { return nil }
        switch reason {
        case "timeout":
            return timedOut(order)
        case "replaced_by_sell":
            return L10n.string("Cancelled because the guru sold %@ before it filled.", order.symbol)
        case "copying_stopped":
            return L10n.string("Cancelled when copying stopped, before it filled.")
        case "cancelled_at_broker":
            return L10n.string("Cancelled at Alpaca, not by CopyTrading.")
        case "expired":
            return L10n.string("Expired when the trading day ended, unfilled.")
        case "rejected":
            return L10n.string("Alpaca rejected the order.")
        default:
            return L10n.string("CopyTrading cancelled it before it filled.")
        }
    }

    /// The reason in a few words, for the timeline's cancel request.
    @MainActor
    static func short(_ reason: String?) -> String? {
        switch reason {
        case "timeout": L10n.string("Not filled in time")
        case "replaced_by_sell": L10n.string("The guru sold it first")
        case "copying_stopped": L10n.string("Copying stopped")
        default: nil
        }
    }

    @MainActor
    private static func timedOut(_ order: OrderActivity) -> String {
        let waited = waitedSeconds(order).map { PostTimeline.duration($0) }
        let limit = money(order.limitPrice)
        let buying = order.side != "sell"
        var parts: [String] = []
        switch (waited, limit) {
        case let (waited?, limit?):
            parts.append(L10n.string("Not filled within %@ at your limit of %@.", waited, limit))
        case let (waited?, nil):
            parts.append(L10n.string("Not filled within %@.", waited))
        case let (nil, limit?):
            parts.append(L10n.string("Not filled in time at your limit of %@.", limit))
        case (nil, nil):
            parts.append(L10n.string("Not filled in time."))
        }
        if buying, let ask = money(order.quoteAsk) {
            parts.append(L10n.string("%@ was offered at %@ when it went out.", order.symbol, ask))
        } else if !buying, let bid = money(order.quoteBid) {
            parts.append(L10n.string("The best bid for %@ was %@ when it went out.", order.symbol, bid))
        }
        if buying, let tolerance = Decimal(engine: order.entryTolerancePct) {
            parts.append(
                tolerance == 0
                    ? L10n.string("Your buys pay at most the guru's price, so it waited for the price to come down.")
                    : L10n.string("Your buys pay at most %@%% above the guru's price.", tolerance.formatted()))
        }
        return parts.joined(separator: " ")
    }

    @MainActor
    private static func waitedSeconds(_ order: OrderActivity) -> TimeInterval? {
        guard let start = Humanize.date(order.submittedAt ?? order.createdAt), let end = Humanize.date(order.endedAt) else {
            return nil
        }
        return end.timeIntervalSince(start)
    }

    private static func money(_ value: String?) -> String? {
        Decimal(engine: value)?.formatted(.currency(code: "USD"))
    }
}
