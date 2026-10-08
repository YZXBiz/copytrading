import DesktopCore
import Foundation

/// How a post ended (ADR-0007), for the Activity card: one badge (Traded, Traded smaller, Waiting
/// for you, Skipped, Ignored), and for each account what it did and why, in plain words.
@MainActor
struct ActivityCardOutcome {
    struct Line: Equatable {
        let what: String
        let why: String?
    }

    struct Account: Equatable, Identifiable {
        let id: String
        let environment: String
        let lines: [Line]
        /// The account waits for the owner to copy or skip the post.
        let waits: Bool
    }

    let title: String
    let tone: StatusTone
    let accounts: [Account]

    /// Outcomes that are not a skip: an order went out, the part is still working, or the owner
    /// approved a held call by hand.
    static let carriedOn: Set<String> = ["order_linked", "pending", "approved_by_owner"]

    init(_ source: SourceActivity, skipped: Bool, now: Date = .now, zone: TimeZone = .current, locale: Locale = .current) {
        let waiting = WaitingCall(source)
        let open = waiting.map { !skipped && !$0.hasExpired(at: now) } ?? false
        let deadline = waiting?.deadline.map { TradingDeadlineText.text($0, now: now, zone: zone, locale: locale) } ?? ""
        accounts = source.destinations.map { destination in
            let waits = waiting?.accountIDs.contains(destination.accountID) == true
            return Account(
                id: destination.accountID, environment: destination.environment,
                lines: Self.lines(
                    for: destination, in: source, waits: waits, open: open, skipped: skipped, deadline: deadline),
                waits: waits && open)
        }
        let orders = source.destinations.flatMap(\.orders).map { DestinationOutcome.order($0, count: 1) }
        let trimmed = source.destinations.flatMap(\.orders).contains(where: Self.wasTrimmed)
        let anySkip = source.destinations.contains { destination in
            destination.instructionOutcomes.contains { !Self.carriedOn.contains($0) }
                || ["stale", "out_of_order"].contains(destination.status)
        }
        if source.decision == "ignore" {
            (title, tone) = (L10n.string("Ignored"), .inactive)
        } else if open {
            (title, tone) = (L10n.string("Waiting for you"), .caution)
        } else if let unsettled = orders.first(where: { $0.tone != .positive }) {
            // An order still working, cancelled, or failed says so before the post counts as traded.
            (title, tone) = (unsettled.title, unsettled.tone)
        } else if !orders.isEmpty {
            (title, tone) = trimmed ? (L10n.string("Traded smaller"), .neutral) : (L10n.string("Traded"), .positive)
        } else if waiting != nil, !skipped {
            (title, tone) = (L10n.string("Expired"), .inactive)
        } else if anySkip || skipped {
            (title, tone) = (L10n.string("Skipped"), .inactive)
        } else {
            (title, tone) = (source.decisionTitle, source.decisionTone)
        }
    }

    /// A buy the maximum per order cut below what its call asked for.
    static func wasTrimmed(_ order: OrderActivity) -> Bool {
        guard let asked = Decimal(engine: order.requestedUSD), let allowed = Decimal(engine: order.budgetUSD) else {
            return false
        }
        return allowed < asked
    }

    private static func lines(
        for destination: DestinationActivity, in source: SourceActivity, waits: Bool, open: Bool, skipped: Bool,
        deadline: String
    ) -> [Line] {
        var lines = destination.orders.map { order in
            Line(
                what: DestinationOutcome.order(order, count: 1).detail,
                why: wasTrimmed(order)
                    ? L10n.string(
                        "The call was for %@. Your max per order cut it to %@.",
                        Humanize.dollars(order.requestedUSD), Humanize.dollars(order.budgetUSD))
                    : nil)
        }
        for (part, outcome) in destination.instructionOutcomes.enumerated()
        where !Self.carriedOn.contains(outcome) && !WaitingCall.heldForOwner.contains(outcome) {
            let selling = source.instructions.indices.contains(part) && source.instructions[part].action != "buy"
            let limit = destination.limitsHit.first { $0.part == part }
            lines.append(
                Line(
                    what: L10n.string(selling ? "Not sold" : "Not bought"),
                    why: limit.map { limitSentence($0, account: destination.accountID, in: source, part: part) }
                        ?? Reason.text(outcome)))
        }
        if waits {
            let reason =
                source.decision == "review"
                ? Reason.text(source.parserReason)
                : Reason.text(destination.instructionOutcomes.first { WaitingCall.heldForOwner.contains($0) })
            // An account that asked to approve every order is asked to approve, not to copy.
            let approving = destination.instructionOutcomes.contains("approval_required") && source.decision != "review"
            let when =
                skipped
                ? L10n.string("You skipped this call.")
                : open
                    ? L10n.string(
                        approving ? "Approve it by %@, when trading ends." : "Copy it from here by %@, when trading ends.",
                        deadline)
                    : L10n.string(
                        approving ? "Too late to approve: its trading day is over." : "Too late to copy: its trading day is over.")
            let what =
                approving
                ? L10n.string(open ? "Waiting for your approval" : "Not sent")
                : L10n.string(open ? "Not copied yet" : "Not copied")
            lines.append(Line(what: what, why: L10n.sentences([L10n.sentence(reason), when])))
        } else if ["stale", "out_of_order"].contains(destination.status), lines.isEmpty {
            lines.append(Line(what: L10n.string("Not copied"), why: Reason.text(destination.status)))
        }
        if lines.isEmpty {
            lines.append(Line(what: DestinationOutcome(destination).detail, why: nil))
        }
        return lines
    }

    private static func limitSentence(_ limit: LimitHit, account: String, in source: SourceActivity, part: Int) -> String {
        if limit.scope == "symbol" {
            let symbol = source.instructions.indices.contains(part) ? source.instructions[part].symbol : ""
            return L10n.string(
                "%@ already has %@ of %@. Buying %@ more would go over its %@ limit for one stock.", account,
                Humanize.dollars(limit.current), symbol, Humanize.dollars(limit.proposed), Humanize.dollars(limit.limit))
        }
        return L10n.string(
            "%@ already holds %@ in total. Buying %@ more would go over its %@ total limit.", account,
            Humanize.dollars(limit.current), Humanize.dollars(limit.proposed), Humanize.dollars(limit.limit))
    }
}
