import DesktopCore
import Foundation

/// A post's trip from Discord to the broker in four phases: received, read, sent, and how it
/// ended. Each phase has one time and how long it took; the finer steps fold into one quiet line
/// under it, and a wait (a hold for the owner, a fill that never came) stands out on its own.
struct PostTimeline {
    struct Phase: Identifiable, Equatable {
        let id: Int
        let title: String
        let at: Date
        /// How long this phase took since the one before; nil for the first.
        let duration: TimeInterval?
        /// The finer steps in one line: "deepseek-flash · 2.9 s".
        let detail: String?
        /// Waits that stand out: "Held 18 s waiting for you to resume".
        let waits: [String]
        /// Ended badly or waits on the owner: the phase reads in a warning colour.
        let caution: Bool
    }

    /// Gaps shorter than this are not worth a number.
    static let measurable: TimeInterval = 0.01

    let phases: [Phase]
    /// From the post to the first order sent, and to the first fill.
    let toOrder: TimeInterval?
    let toFill: TimeInterval?

    @MainActor
    init(_ item: SourceActivity) {
        var phases: [Phase] = []
        func add(_ title: String, at: Date, after previous: Date?, detail: String?, waits: [String] = [], caution: Bool = false) {
            let duration = previous.map { at.timeIntervalSince($0) }.flatMap { $0 >= Self.measurable ? $0 : nil }
            phases.append(
                Phase(id: phases.count, title: title, at: at, duration: duration, detail: detail, waits: waits, caution: caution))
        }
        let posted = Humanize.date(item.sourceAt)
        let captured = Humanize.date(item.capturedAt)
        if let received = posted ?? captured {
            let gap = posted.flatMap { start in captured.map { $0.timeIntervalSince(start) } }
            add(
                L10n.string("Received"), at: received, after: nil,
                detail: gap.flatMap { $0 >= Self.measurable ? L10n.string("Captured in %@", Self.duration($0)) : nil })
        }
        let readStarted = Humanize.date(item.readStartedAt)
        let readAt = Humanize.date(item.readAt)
        if let readAt {
            let reading = readStarted.map { readAt.timeIntervalSince($0) }
            let detail = [item.interpretedBy, reading.flatMap { $0 >= Self.measurable ? Self.duration($0) : nil }]
                .compactMap(\.self).joined(separator: " · ")
            var waits: [String] = []
            if let readStarted, let since = captured ?? posted, readStarted.timeIntervalSince(since) >= 1 {
                waits.append(L10n.string("Waited %@ before reading", Self.duration(readStarted.timeIntervalSince(since))))
            }
            add(L10n.string("Read"), at: readAt, after: captured ?? posted, detail: detail.nilIfEmpty, waits: waits)
        }
        let handedOff = Humanize.date(item.deliveredAt) ?? readAt
        let several = item.destinations.count > 1
        for destination in item.destinations {
            Self.addAccount(destination, after: handedOff, several: several, add: add)
        }
        self.phases = phases
        let steps = item.destinations.flatMap(\.timeline)
        let sent = steps.filter { $0.step == "sent" }.compactMap { Humanize.date($0.at) }.min()
        let filled = steps.filter { ["filled", "partially_filled"].contains($0.step) }.compactMap { Humanize.date($0.at) }.min()
        toOrder = posted.flatMap { start in sent.map { $0.timeIntervalSince(start) } }
        toFill = posted.flatMap { start in filled.map { $0.timeIntervalSince(start) } }
    }

    /// One account's Sent and Ended phases, with its hold and its fill wait folded in.
    @MainActor
    private static func addAccount(
        _ destination: DestinationActivity, after handedOff: Date?, several: Bool,
        add: (String, Date, Date?, String?, [String], Bool) -> Void
    ) {
        func step(_ name: String) -> TimelineStep? { destination.timeline.last { $0.step == name } }
        func date(_ step: TimelineStep?) -> Date? { Humanize.date(step?.at) }
        func named(_ title: String) -> String { several ? L10n.string("%@ · %@", destination.accountID, title) : title }
        let orders = Dictionary(destination.orders.map { ($0.clientID, $0) }, uniquingKeysWith: { first, _ in first })

        var holdWait: String?
        if let held = date(step("held")) {
            let released = date(step("resumed")) ?? date(step("skipped"))
            if let released {
                holdWait = L10n.string("Held %@ waiting for you to resume", duration(released.timeIntervalSince(held)))
            }
        }

        let sentStep = step("sent")
        let sent = date(sentStep)
        if let sent {
            let sized = step("sized")
            let order = (sentStep?.clientID ?? sized?.clientID).flatMap { orders[$0] }
            let quantity = Decimal(engine: sized?.quantity ?? order?.quantity)
            let limit = Decimal(engine: sized?.price ?? order?.limitPrice)?.formatted(.currency(code: "USD"))
            var parts: [String] = []
            // Dollar first, then the shares it came to: "$200 of PM · ≈1 share · limit $201.00".
            if let order, let amount = OrderAmount.planned(order) { parts.append(amount) }
            if let quantity { parts.append(Humanize.shares(quantity)) }
            if let limit { parts.append(L10n.string("limit %@", limit)) }
            if let accepted = date(step("accepted")), accepted.timeIntervalSince(sent) >= measurable {
                parts.append(L10n.string("accepted by Alpaca in %@", duration(accepted.timeIntervalSince(sent))))
            }
            add(named(L10n.string("Sent")), sent, handedOff, parts.joined(separator: " · ").nilIfEmpty, holdWait.map { [$0] } ?? [], false)
        }

        let ends = ["filled", "partially_filled", "cancelled", "expired", "rejected", "skipped", "failed"]
        guard let end = destination.timeline.last(where: { ends.contains($0.step) }), let endedAt = date(end) else { return }
        let start = sent ?? handedOff
        let order = end.clientID.flatMap { orders[$0] } ?? sentStep?.clientID.flatMap { orders[$0] }
        var waits: [String] = sent == nil ? (holdWait.map { [$0] } ?? []) : []
        switch end.step {
        case "filled", "partially_filled":
            let quantity = Decimal(engine: end.quantity)
            let price = Decimal(engine: end.price)
            var parts: [String] = []
            if let quantity, let price {
                parts.append(Humanize.amount(Humanize.usd(quantity * price), of: order?.symbol ?? ""))
            }
            if let quantity {
                parts.append(
                    price.map { L10n.string("%@ at %@", Humanize.shares(quantity), Humanize.usd($0)) }
                        ?? Humanize.shares(quantity))
            }
            let detail = parts.joined(separator: " · ").nilIfEmpty
            add(named(L10n.string(end.step == "filled" ? "Filled" : "Partly filled")), endedAt, start, detail, waits, false)
        case "cancelled", "expired":
            if let sent { waits.append(L10n.string("Waited %@ for a fill", duration(endedAt.timeIntervalSince(sent)))) }
            let why = cancelPhrase(step("cancel_requested")?.reason ?? order?.cancelReason)
            let title =
                end.step == "expired"
                ? L10n.string("Expired at the end of the trading day")
                : why.map { L10n.string("Cancelled · %@", $0) } ?? L10n.string("Cancelled")
            add(named(title), endedAt, start, nil, waits, true)
        case "rejected":
            add(named(L10n.string("Rejected by Alpaca")), endedAt, start, nil, waits, true)
        case "skipped":
            add(named(L10n.string("Skipped")), endedAt, start, end.reason.map { Reason.text($0) }, waits, true)
        default:
            add(named(L10n.string("Couldn't send it")), endedAt, start, end.reason.map { Reason.text($0) }, waits, true)
        }
    }

    /// Why CopyTrading cancelled, in a few words for the Ended phase; the card says it in full.
    @MainActor
    private static func cancelPhrase(_ reason: String?) -> String? {
        switch reason {
        case "timeout": L10n.string("not filled in time")
        case "replaced_by_sell": L10n.string("the guru sold it first")
        case "copying_stopped": L10n.string("copying stopped")
        case "cancelled_at_broker": L10n.string("cancelled at Alpaca")
        default: nil
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
