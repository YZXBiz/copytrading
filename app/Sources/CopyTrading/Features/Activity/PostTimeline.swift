import DesktopCore
import Foundation

/// A post's trip from Discord to the broker as timed steps: when it was posted, captured and
/// read, when it reached each account, and what each account did with it, with the time each
/// step took. A step that took long for no market reason is marked slow.
struct PostTimeline {
    struct Row: Identifiable, Equatable {
        let id: Int
        let title: String
        let detail: String?
        let at: Date
        /// Time since the step before it; nil for the first.
        let gap: TimeInterval?
        let slow: Bool
        /// Waiting on the owner or ended badly: the row reads in a warning colour.
        let caution: Bool
    }

    /// Steps slower than this before the order goes out are marked.
    static let slowSeconds: TimeInterval = 5

    let rows: [Row]
    /// From the post to the first order sent, and to the first fill.
    let toOrder: TimeInterval?
    let toFill: TimeInterval?

    /// Steps that wait on the market, not on CopyTrading: never marked slow.
    private static let marketSteps: Set<String> = [
        "partially_filled", "filled", "cancel_requested", "cancelled", "expired", "rejected",
    ]

    @MainActor
    init(_ item: SourceActivity) {
        var rows: [Row] = []
        func add(_ title: String, _ detail: String?, _ iso: String?, after previous: Date?, step: String, caution: Bool = false) {
            guard let iso, let at = Humanize.date(iso) else { return }
            let gap = previous.map { at.timeIntervalSince($0) }
            let slow = (gap ?? 0) >= Self.slowSeconds && !Self.marketSteps.contains(step)
            rows.append(Row(id: rows.count, title: title, detail: detail, at: at, gap: gap, slow: slow, caution: caution))
        }
        add(L10n.string("Posted on Discord"), nil, item.sourceAt, after: nil, step: "posted")
        add(L10n.string("Captured by CopyTrading"), nil, item.capturedAt, after: rows.last?.at, step: "captured")
        add(L10n.string("Reading started"), nil, item.readStartedAt, after: rows.last?.at, step: "read_started")
        add(
            L10n.string("Read"), item.interpretedBy.map { L10n.string("by %@", $0) }, item.readAt,
            after: rows.last?.at, step: "read")
        add(L10n.string("Handed to your accounts"), nil, item.deliveredAt, after: rows.last?.at, step: "delivered")
        let handedOff = rows.last?.at
        let several = item.destinations.count > 1
        for destination in item.destinations {
            var previous = handedOff
            let orders = Dictionary(destination.orders.map { ($0.clientID, $0) }, uniquingKeysWith: { first, _ in first })
            for step in destination.timeline {
                let (title, detail, caution) = Self.words(step, order: step.clientID.flatMap { orders[$0] }, account: destination.accountID)
                let prefixed = several ? L10n.string("%@ · %@", destination.accountID, title) : title
                add(prefixed, detail, step.at, after: previous, step: step.step, caution: caution)
                previous = rows.last?.at ?? previous
            }
        }
        self.rows = rows
        let posted = Humanize.date(item.sourceAt)
        let steps = item.destinations.flatMap(\.timeline)
        let sent = steps.filter { $0.step == "sent" }.compactMap { Humanize.date($0.at) }.min()
        let filled = steps.filter { ["filled", "partially_filled"].contains($0.step) }.compactMap { Humanize.date($0.at) }.min()
        toOrder = posted.flatMap { start in sent.map { $0.timeIntervalSince(start) } }
        toFill = posted.flatMap { start in filled.map { $0.timeIntervalSince(start) } }
    }

    /// A step in the owner's words, with what it carried: the size and limit, the fill, the reason.
    @MainActor
    private static func words(_ step: TimelineStep, order: OrderActivity?, account: String) -> (String, String?, Bool) {
        let symbol = order?.symbol ?? ""
        let quantity = Decimal(engine: step.quantity).map { $0.formatted() }
        let price = Decimal(engine: step.price)?.formatted(.currency(code: "USD"))
        switch step.step {
        case "received":
            return (L10n.string("Reached %@", account), nil, false)
        case "held":
            return (L10n.string("Held: waiting for you to resume entries"), nil, true)
        case "resumed":
            return (L10n.string("You resumed entries"), nil, false)
        case "skipped":
            return (L10n.string("Skipped"), step.reason.map { Reason.text($0) }, true)
        case "sized":
            let size = quantity.map { L10n.string("%@ %@", $0, symbol) }
            let limit = price.map { L10n.string("limit %@", $0) }
            return (L10n.string("Sized and checked"), [size, limit].compactMap(\.self).joined(separator: ", ").nilIfEmpty, false)
        case "sent":
            return (L10n.string("Sent to Alpaca"), nil, false)
        case "accepted":
            return (L10n.string("Alpaca accepted it"), nil, false)
        case "partially_filled", "filled":
            let detail = quantity.map { qty in price.map { L10n.string("%@ at %@", qty, $0) } ?? qty }
            return (L10n.string(step.step == "filled" ? "Filled" : "Partly filled"), detail, false)
        case "cancel_requested":
            return (L10n.string("CopyTrading asked Alpaca to cancel"), CancelReasonText.short(step.reason), true)
        case "cancelled":
            return (L10n.string("Cancelled"), order.flatMap { CancelReasonText.sentence($0) }, true)
        case "expired":
            return (L10n.string("Expired when the trading day ended"), nil, true)
        case "rejected":
            return (L10n.string("Rejected by Alpaca"), nil, true)
        default:
            return (L10n.string("Couldn't send it"), step.reason.map { Reason.text($0) }, true)
        }
    }

    /// "0.09 s", "2.9 s", "20.7 s", "1 min 3 s".
    @MainActor
    static func duration(_ seconds: TimeInterval) -> String {
        let value = max(0, seconds)
        if value < 10 { return L10n.string("%@ s", value.formatted(.number.precision(.fractionLength(value < 1 ? 2 : 1)))) }
        if value < 60 { return L10n.string("%@ s", value.formatted(.number.precision(.fractionLength(0)))) }
        let minutes = Int(value) / 60
        let rest = Int(value) % 60
        return rest == 0 ? L10n.string("%lld min", Int64(minutes)) : L10n.string("%lld min %lld s", Int64(minutes), Int64(rest))
    }
}
