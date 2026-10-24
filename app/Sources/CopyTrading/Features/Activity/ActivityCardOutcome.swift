import DesktopCore
import Foundation

/// How a post ended (ADR-0007), for the Activity card: one badge (Traded, Traded smaller, Waiting
/// for you, Skipped, Ignored), and for each account the takeaway first: one line saying what
/// happened, a few facts behind it, and at most one thing to do about it.
@MainActor
struct ActivityCardOutcome {
    /// A number behind the takeaway, its label above its value: "Your limit" "$201.00".
    struct Fact: Equatable {
        let label: String
        let value: String
    }

    /// The one change the card offers, never made without the owner.
    enum Suggestion: Equatable {
        /// Let buys pay a little above the guru's price: the account's limit sat at 0%.
        case allowAboveGuru
    }

    /// One thing the account did with the post: usually one order, or why there was none.
    struct Result: Equatable {
        let headline: String
        var facts: [Fact] = []
        /// One short sentence under the facts, only when the headline and facts leave a question.
        var note: String?
        var suggestion: Suggestion?
        /// The limit beside the price the order met, drawn as a ruler instead of two numbers.
        var prices: PricePoints?
    }

    struct Account: Equatable, Identifiable {
        let id: String
        let environment: String
        let results: [Result]
        /// The account waits for the owner to copy or skip the post.
        let waits: Bool
        /// The account holds the post's buy until the owner resumes its entries after a restart.
        var awaitsResume = false
    }

    let title: String
    let tone: StatusTone
    let accounts: [Account]

    /// Outcomes that are not a skip: an order went out, the part is still working (a sell may be
    /// waiting for a price to sell at), or the owner approved a held call by hand.
    static let carriedOn: Set<String> = ["order_linked", "pending", "waiting_for_quote", "approved_by_owner"]

    init(
        _ source: SourceActivity, skipped: Bool, resume: ResumeWait = .none, now: Date = .now,
        zone: TimeZone? = nil, locale: Locale? = nil
    ) {
        let waiting = WaitingCall(source)
        // A post the owner traded by hand is settled: it no longer waits for them.
        let open = WaitingCall.open(source, skipped: skipped, now: now) != nil
        let deadline = waiting?.deadline.map { TradingDeadlineText.text($0, now: now, zone: zone, locale: locale) } ?? ""
        accounts = source.destinations.map { destination in
            let waits =
                waiting?.accountIDs.contains(destination.accountID) == true
                && !destination.orders.contains(where: \.isOwnerEntry)
            let resumeBy = resume.deadlines[destination.accountID]
            var account = Account(
                id: destination.accountID, environment: destination.environment,
                results: Self.results(
                    for: destination, in: source, waits: waits, open: open, skipped: skipped, resumeBy: resumeBy,
                    now: now, deadline: deadline),
                waits: waits && open)
            account.awaitsResume = resumeBy != nil
            return account
        }
        let awaitsResume = accounts.contains(where: \.awaitsResume)
        // The owner's own sales are theirs, not the post's: they never decide how the post did.
        let copied = source.destinations.flatMap(\.orders).filter { !$0.isOwnerSale }
        let orders = copied.map { DestinationOutcome.order($0, count: 1) }
        let trimmed = source.destinations.flatMap(\.orders).contains(where: Self.wasTrimmed)
        let anySkip = source.destinations.contains { destination in
            destination.instructionOutcomes.contains { !Self.carriedOn.contains($0) }
                || ["stale", "out_of_order"].contains(destination.status)
        }
        if source.decision == "ignore" {
            (title, tone) = (L10n.string("Ignored"), .inactive)
        } else if open || awaitsResume {
            (title, tone) = (L10n.string("Waiting for you"), .caution)
        } else if orders.contains(where: { $0.tone == .positive }), orders.contains(where: { $0.tone != .positive }) {
            // One account filled and another didn't: the post traded, but not everywhere.
            (title, tone) = (L10n.string("Partly traded"), .neutral)
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

    private static func results(
        for destination: DestinationActivity, in source: SourceActivity, waits: Bool, open: Bool, skipped: Bool,
        resumeBy: Date?, now: Date, deadline: String
    ) -> [Result] {
        let postedAt = Humanize.date(source.sourceAt)
        var results = destination.orders.map { orderResult($0, postedAt: postedAt) }
        for (part, outcome) in destination.instructionOutcomes.enumerated()
        // A call waiting for the owner says why once, in its own result below; not as "Not bought" too.
        where !Self.carriedOn.contains(outcome) && !WaitingCall.heldForOwner.contains(outcome)
            && !(waits && outcome == "review_required")
        {
            let selling = source.instructions.indices.contains(part) && source.instructions[part].action != "buy"
            if let limit = destination.limitsHit.first(where: { $0.part == part }) {
                results.append(limitResult(limit, selling: selling, in: source, part: part))
            } else if let later = destination.laterBuys.first(where: { $0.part == part }),
                let headline = laterBuyHeadline(later, account: destination.accountID, in: source, part: part)
            {
                results.append(Result(headline: headline))
            } else {
                results.append(Result(headline: L10n.string(selling ? "Not sold" : "Not bought"), note: Reason.text(outcome)))
            }
        }
        // A sell with no fresh bid yet keeps waiting, and asks Alpaca again every 30 seconds.
        if destination.instructionOutcomes.contains("waiting_for_quote") {
            results.append(Result(headline: Reason.text("waiting_for_quote")))
        }
        if waits {
            results.append(waitingResult(destination, in: source, open: open, skipped: skipped, deadline: deadline))
        } else if ["stale", "out_of_order"].contains(destination.status), results.isEmpty {
            results.append(
                Result(
                    headline: L10n.string("Not copied"),
                    note: destination.status == "stale" ? staleNote(source) : Reason.text(destination.status)))
        }
        if results.isEmpty, let resumeBy {
            // After a restart an account waits for its Start Copying; the buy waits with it while it is fresh.
            // A two-minute window: to the second, with the zone.
            let time = "\(resumeBy.formatted(AppTime.style(.dateTime.hour().minute().second()))) \(AppTime.shortName())"
            results.append(
                resumeBy > now
                    ? Result(
                        headline: L10n.string("Waiting for Start Copying"),
                        facts: [Fact(label: L10n.string("Start by"), value: time)])
                    : Result(
                        headline: L10n.string("Waiting for Start Copying"),
                        note: L10n.string("Start Copying now: after %@ it is too old to copy.", time)))
        }
        if results.isEmpty {
            results.append(Result(headline: DestinationOutcome(destination).detail))
        }
        return results
    }

    /// Why a post of buys wasn't copied: how late it was read, against the account's signal age.
    private static func staleNote(_ source: SourceActivity) -> String {
        guard let posted = Humanize.date(source.sourceAt), let read = Humanize.date(source.capturedAt) else {
            return Reason.text("stale")
        }
        return L10n.string(
            "Read %@ after it was posted: older than this account copies buys. A sell is always copied.",
            PostTimeline.duration(read.timeIntervalSince(posted)))
    }

    /// One order, takeaway first: what it bought, or why it bought nothing, with the numbers that
    /// decided it. A sell read long after the post says so: it sold from the market then.
    static func orderResult(_ order: OrderActivity, postedAt: Date? = nil) -> Result {
        let buying = order.side != "sell"
        var note: String?
        if !buying, let postedAt, let placed = Humanize.date(order.createdAt),
            placed.timeIntervalSince(postedAt) >= lateSellSeconds
        {
            note = L10n.string(
                "Read %@ after the guru posted it. A sell is always copied, at no less than your lowest price.",
                PostTimeline.duration(placed.timeIntervalSince(postedAt)))
        }
        let limit = money(order.limitPrice)
        let planned = OrderAmount.planned(order) ?? order.symbol
        var facts: [Fact] = []
        let headline: String
        var suggestion: Suggestion?
        var prices: PricePoints?
        // A working order's ruler; its own facts already say where its limit came from.
        var working: PricePoints?
        let limitPrice = Decimal(engine: order.limitPrice)
        switch DestinationOutcome.order(order, count: 1) {
        case .filled:
            headline = L10n.string(
                order.isOwnerSale || (order.isOwnerEntry && !buying)
                    ? "You sold %@" : order.isOwnerEntry ? "You bought %@" : buying ? "Bought %@" : "Sold %@",
                OrderAmount.filled(order) ?? planned)
            if let limitPrice, let fill = Decimal(engine: order.averageFillPrice) {
                prices = PricePoints(
                    limit: limitPrice, market: fill, marketLabel: L10n.string("Filled at"), buying: buying,
                    guru: guruMark(order))
            } else {
                facts.append(Fact(label: L10n.string("Price"), value: money(order.averageFillPrice) ?? "—"))
            }
            facts.append(
                Fact(label: L10n.string("Shares"), value: Humanize.shares(Decimal(engine: order.filledQuantity) ?? 0, of: order.symbol)))
        case .partlyFilled:
            headline = L10n.string(
                order.status == "partially_filled" ? "Partly filled: %@ so far" : "Partly filled: %@, the rest cancelled",
                OrderAmount.filled(order) ?? planned)
            facts.append(
                Fact(
                    label: L10n.string("Filled"),
                    value: Humanize.shares(
                        Decimal(engine: order.filledQuantity) ?? 0, of: Decimal(engine: order.quantity) ?? 0, symbol: order.symbol)))
            facts.append(Fact(label: L10n.string("Price"), value: money(order.averageFillPrice) ?? "—"))
        case .working:
            headline = L10n.string(buying ? "Buying %@" : "Selling %@", planned)
            // Where it waits: the guru's price, your limit, and the market it met, on one ruler.
            if let limitPrice, let met = Decimal(engine: buying ? order.quoteAsk : order.quoteBid) {
                working = PricePoints(
                    limit: limitPrice, market: met, marketLabel: L10n.string("Market"), buying: buying,
                    guru: guruMark(order))
            }
            if buying {
                if let limit { facts.append(Fact(label: L10n.string("Your limit"), value: limit)) }
            } else {
                // A sell keeps working at its floor until the market reaches it (ADR-0010).
                if let floor = sellFloor(order) { facts.append(Fact(label: L10n.string("Lowest sell price"), value: floor)) }
                if working == nil, let market = sellMarket(order) {
                    facts.append(Fact(label: L10n.string("Market"), value: market))
                }
            }
        case .failed:
            headline = L10n.string(buying ? "Not bought: Alpaca rejected it" : "Not sold: Alpaca rejected it")
        case .needsReview:
            headline = L10n.string("Waiting for Alpaca to confirm")
        default:
            let market = money(buying ? order.quoteAsk : order.quoteBid)
            if !buying, order.status == "expired" || order.cancelReason == "expired", let limit {
                headline = L10n.string("Not sold by the close: the market stayed under your lowest price %@", limit)
            } else {
                headline = L10n.string(buying ? "Not bought: %@" : "Not sold: %@", cancelReason(order))
            }
            if let limitPrice, let met = Decimal(engine: buying ? order.quoteAsk : order.quoteBid) {
                prices = PricePoints(
                    limit: limitPrice, market: met, marketLabel: L10n.string("Market"), buying: buying,
                    guru: guruMark(order))
            } else {
                if let limit {
                    facts.append(Fact(label: L10n.string(buying ? "Your limit" : "Lowest sell price"), value: limit))
                }
                if let market { facts.append(Fact(label: L10n.string("Market"), value: market)) }
            }
            if let waited = CancelReasonText.waitedSeconds(order), order.cancelReason == "timeout" {
                facts.append(Fact(label: L10n.string("Waited"), value: PostTimeline.duration(waited)))
            }
            if buying, order.cancelReason == "timeout", Decimal(engine: order.entryTolerancePct) == 0 {
                suggestion = .allowAboveGuru
            }
        }
        if prices != nil, let basis = guruPrice(order) {
            // The ruler shows the limit; this says where it came from, so a changed allowance shows.
            facts.insert(Fact(label: L10n.string("Guru's price"), value: basis), at: 0)
        }
        if let working { prices = working }
        if let budget = Decimal(engine: order.budgetUSD) {
            if wasTrimmed(order) {
                // Cut by one of the account's limits: say which, and what the call asked for.
                facts.append(Fact(label: L10n.string("Order"), value: cut(order)))
                facts.append(Fact(label: L10n.string("The call asked for"), value: Humanize.dollars(order.requestedUSD)))
            } else {
                facts.append(Fact(label: L10n.string("Order"), value: OrderAmount.dollars(budget)))
            }
        }
        return Result(
            headline: headline, facts: Array(facts.prefix(4)), note: note, suggestion: suggestion, prices: prices)
    }

    /// "Not sold: zhap-account-2's SOXL was bought after this sell was posted (Wed 9:41 vs Mon 10:02)."
    private static func laterBuyHeadline(_ later: LaterBuy, account: String, in source: SourceActivity, part: Int)
        -> String?
    {
        guard let bought = Humanize.date(later.boughtAt), let sold = Humanize.date(source.sourceAt) else { return nil }
        let symbol = source.instructions.indices.contains(part) ? source.instructions[part].symbol : ""
        let style = AppTime.style(.dateTime.weekday(.abbreviated).hour().minute())
        return L10n.string(
            "Not sold: %@'s %@ was bought after this sell was posted (%@ vs %@).", account, symbol,
            bought.formatted(style), sold.formatted(style))
    }

    /// A sell placed this long after its post was read late, so the card says so.
    static let lateSellSeconds: TimeInterval = 600

    /// What a cut buy spent, and the limit that cut it: "$200 · your largest single buy".
    static func cut(_ order: OrderActivity) -> String {
        let amount = Humanize.dollars(order.budgetUSD)
        switch order.limitedBy {
        case "symbol_exposure_cap": return L10n.string("%@ · the room left under your %@ limit", amount, order.symbol)
        case "total_exposure_cap": return L10n.string("%@ · the room left under your total limit", amount)
        default: return L10n.string("%@ · your largest single buy", amount)
        }
    }

    /// A sell's floor and where it came from: "$53.66 (1% under the guru's $54.20)" (ADR-0010).
    static func sellFloor(_ order: OrderActivity) -> String? {
        guard let limit = money(order.limitPrice) else { return nil }
        guard let guru = money(order.sourcePrice), let allowance = Decimal(engine: order.entryTolerancePct),
            allowance > 0
        else { return limit }
        let percent = (allowance / 100).formatted(.percent.precision(.fractionLength(0...2)))
        return L10n.string("%@ (%@ under the guru's %@)", limit, percent, guru)
    }

    /// The bid when a sell went out, against its floor: "$53.85, above it".
    static func sellMarket(_ order: OrderActivity) -> String? {
        guard let bid = Decimal(engine: order.quoteBid), let market = money(order.quoteBid) else { return nil }
        guard let floor = Decimal(engine: order.limitPrice) else { return market }
        return L10n.string(bid >= floor ? "%@, above it" : "%@, under it", market)
    }

    /// The guru's price as its own mark on the ruler; nil when the limit is that price.
    private static func guruMark(_ order: OrderActivity) -> Decimal? {
        guard let guru = Decimal(engine: order.sourcePrice), guru != Decimal(engine: order.limitPrice) else { return nil }
        return guru
    }

    /// The price the limit came from and the allowance added to it: "$69.80 + 1% allowed" for a buy,
    /// "$54.20 − 1% allowed" for a sell, both from the guru's price. Nil with no allowance, where
    /// the limit is that price.
    private static func guruPrice(_ order: OrderActivity) -> String? {
        guard let source = money(order.sourcePrice),
            let allowance = Decimal(engine: order.entryTolerancePct), allowance > 0
        else { return nil }
        let percent = (allowance / 100).formatted(.percent.precision(.fractionLength(0...2)))
        return L10n.string(order.side == "sell" ? "%@ − %@ allowed" : "%@ + %@ allowed", source, percent)
    }

    /// Why an order ended unfilled, in a few words after "Not bought:".
    private static func cancelReason(_ order: OrderActivity) -> String {
        switch order.cancelReason {
        case "timeout":
            let buying = order.side != "sell"
            guard let limit = Decimal(engine: order.limitPrice),
                let market = Decimal(engine: buying ? order.quoteAsk : order.quoteBid)
            else { return L10n.string("not filled in time") }
            if buying, market > limit { return L10n.string("the price ran above your limit") }
            if !buying, market < limit { return L10n.string("the price fell below your limit") }
            return L10n.string("not filled in time")
        case "replaced_by_sell": return L10n.string("the guru sold it first")
        case "copying_stopped": return L10n.string("copying stopped")
        case "cancelled_at_broker": return L10n.string("cancelled at Alpaca")
        case "rejected": return L10n.string("Alpaca rejected it")
        default:
            return L10n.string(order.status == "expired" ? "the trading day ended" : "cancelled before it filled")
        }
    }

    private static func waitingResult(
        _ destination: DestinationActivity, in source: SourceActivity, open: Bool, skipped: Bool, deadline: String
    ) -> Result {
        let code =
            source.decision == "review"
            ? source.parserReason
            : destination.instructionOutcomes.first { WaitingCall.heldForOwner.contains($0) }
        // An account that asked to approve every order is asked to approve, not to copy.
        let approving = destination.instructionOutcomes.contains("approval_required") && source.decision != "review"
        if skipped {
            return Result(headline: L10n.string("Not copied"), note: L10n.string("You skipped this call."))
        }
        guard open else {
            return Result(
                headline: L10n.string(approving ? "Not sent" : "Not copied"),
                note: L10n.string(
                    approving ? "Too late to approve: its trading day is over." : "Too late to copy: its trading day is over."))
        }
        let short = approving ? nil : code.flatMap { waitingReasons[$0] }.map { L10n.string($0) }
        return Result(
            headline: approving
                ? L10n.string("Waiting for your approval")
                : short.map { L10n.string("Waiting for you: %@", $0) } ?? L10n.string("Waiting for you"),
            facts: [Fact(label: L10n.string(approving ? "Approve by" : "Copy by"), value: deadline)],
            // With no reason given, the headline and deadline say it all; a note would be a lone dash.
            note: short == nil ? code.map { L10n.sentence(Reason.text($0)) } : nil)
    }

    /// Why a call waits, in a few words after "Waiting for you:".
    private static let waitingReasons: [String: String] = [
        "repeats_an_earlier_call": "repeats an earlier call",
        "conditional": "the trade has a condition",
        "suggestion": "a suggestion, not a trade",
        "unclear": "the post is unclear",
        "price_range": "the guru gave a price range",
        "price_at_market": "a buy at the market price",
        "price_not_given": "no price given",
        "named_buy_not_held": "no buy at the guru's price",
        "sell_share_not_given": "the sell gives no size",
        "batch_size_not_given": "no batch size given",
    ]

    /// A buy with less than Alpaca's $1 minimum of room left under a limit: a cap only cuts a buy
    /// to the room left, so this is the one way it skips one (ADR-0010).
    private static func limitResult(_ limit: LimitHit, selling: Bool, in source: SourceActivity, part: Int) -> Result {
        let symbol = source.instructions.indices.contains(part) ? source.instructions[part].symbol : ""
        let full =
            limit.scope == "symbol"
            ? L10n.string("%@ is at your limit for one stock", symbol) : L10n.string("you're at your total limit")
        let room = (Decimal(engine: limit.limit) ?? 0) - (Decimal(engine: limit.current) ?? 0)
        return Result(
            headline: L10n.string(selling ? "Not sold: %@" : "Not bought: %@", full),
            facts: [
                Fact(
                    label: L10n.string(limit.scope == "symbol" ? "Holding %@" : "Holding in total", symbol),
                    value: Humanize.dollars(limit.current)),
                Fact(label: L10n.string("Limit"), value: Humanize.dollars(limit.limit)),
                Fact(label: L10n.string("Room left"), value: Humanize.dollars("\(max(room, 0))")),
            ],
            note: L10n.string("Less than $1 is left, Alpaca's smallest order."))
    }

    private static func money(_ value: String?) -> String? {
        Decimal(engine: value)?.formatted(.currency(code: "USD"))
    }
}
