import DesktopCore
import Foundation

/// Where a post in flight is right now, and since when: waiting to be read, being read, on its
/// way to the accounts, held for the owner's Resume, waiting for an account's next cycle, or
/// waiting at Alpaca for a fill. A settled post has none, so nothing ticks once it is done.
@MainActor
struct PostProgress: Equatable {
    enum Step: Equatable {
        case waitingToRead
        case reading(model: String?)
        case handingOff
        case heldForResume(account: String, copiesUntil: Date?)
        case nextCycle(account: String)
        case awaitingFill(account: String, symbol: String, timeout: TimeInterval?)
    }

    let step: Step
    let since: Date

    /// Order states still open at the broker.
    static let workingOrders: Set<String> = [
        "prepared", "accepted", "pending_new", "accepted_for_bidding", "new", "partially_filled",
        "pending_cancel", "pending_replace", "held", "suspended", "stopped",
    ]

    /// What the progress line needs from the saved setup: the reader's model and each
    /// account's order timeout.
    struct Context: Equatable {
        var readerModel: String?
        var orderTimeouts: [String: TimeInterval] = [:]
    }

    init(step: Step, since: Date) {
        self.step = step
        self.since = since
    }

    init?(_ item: SourceActivity, context: Context = Context(), resume: ResumeWait = .none) {
        guard !item.isHistorical else { return nil }
        guard let decision = item.decision else {
            guard item.parseStatus == "pending" else { return nil }
            if let started = Humanize.date(item.readStartedAt) {
                self.init(step: .reading(model: context.readerModel), since: started)
            } else if let captured = Humanize.date(item.capturedAt) {
                self.init(step: .waitingToRead, since: captured)
            } else {
                return nil
            }
            return
        }
        guard decision == "trade" else { return nil }
        guard item.deliveryStatus == "delivered" else {
            guard let read = Humanize.date(item.readAt) ?? Humanize.date(item.capturedAt) else { return nil }
            self.init(step: .handingOff, since: read)
            return
        }
        // The most telling account wins: an order at the broker, then a hold, then a wait.
        var held: PostProgress?
        var waiting: PostProgress?
        for destination in item.destinations {
            if let order = destination.orders.first(where: { Self.workingOrders.contains($0.status) }),
                let sent = Humanize.date(order.submittedAt) ?? Humanize.date(order.createdAt)
            {
                self.init(
                    step: .awaitingFill(
                        account: destination.accountID, symbol: order.symbol,
                        timeout: context.orderTimeouts[destination.accountID]),
                    since: sent)
                return
            }
            let last = destination.timeline.last
            if last?.step == "held", let at = Humanize.date(last?.at) {
                held =
                    held
                    ?? PostProgress(
                        step: .heldForResume(account: destination.accountID, copiesUntil: resume.deadlines[destination.accountID]),
                        since: at)
            } else if destination.status == "queued",
                let at = Humanize.date(last?.at) ?? Humanize.date(item.deliveredAt)
            {
                waiting = waiting ?? PostProgress(step: .nextCycle(account: destination.accountID), since: at)
            }
        }
        guard let found = held ?? waiting else { return nil }
        self = found
    }

    func elapsed(at now: Date) -> TimeInterval { max(0, now.timeIntervalSince(since)) }

    /// Past what a healthy run takes: reading over 5 s, a fill over 30 s, a cycle over 10 s.
    /// A hold waits on the owner, so it always reads as a caution.
    func isSlow(at now: Date) -> Bool {
        let seconds = elapsed(at: now)
        switch step {
        case .waitingToRead, .reading, .handingOff: return seconds > 5
        case .nextCycle: return seconds > 10
        case .awaitingFill: return seconds > 30
        case .heldForResume: return true
        }
    }

    /// The card's line: "Reading with deepseek-flash… 2.1 s".
    func line(at now: Date) -> String {
        let time = Self.live(elapsed(at: now))
        switch step {
        case .waitingToRead:
            return L10n.string("Waiting to be read… %@", time)
        case .reading(let model?):
            return L10n.string("Reading with %@… %@", model, time)
        case .reading(nil):
            return L10n.string("Reading… %@", time)
        case .handingOff:
            return L10n.string("Handing to your accounts… %@", time)
        case .heldForResume(_, let until?):
            return L10n.string(
                "Held · waiting for you to resume entries · %@, copies until %@", time,
                until.formatted(AppTime.style(.dateTime.hour().minute().second())))
        case .heldForResume(_, nil):
            return L10n.string("Held · waiting for you to resume entries · %@", time)
        case .nextCycle:
            return L10n.string("Waiting for the next account cycle… %@", time)
        case .awaitingFill(_, _, let timeout?):
            return L10n.string("Sent to Alpaca · waiting for a fill · %@ of %@", time, Self.live(timeout))
        case .awaitingFill(_, _, nil):
            return L10n.string("Sent to Alpaca · waiting for a fill · %@", time)
        }
    }

    /// A ticking count in whole seconds: "8 s", "60 s", "2 min 5 s".
    static func live(_ seconds: TimeInterval) -> String {
        let whole = Int(max(0, seconds))
        if whole < 120 { return L10n.string("%lld s", Int64(whole)) }
        let rest = whole % 60
        return rest == 0
            ? L10n.string("%lld min", Int64(whole / 60))
            : L10n.string("%lld min %lld s", Int64(whole / 60), Int64(rest))
    }

    /// The list row's words: "Waiting for fill · 12 s".
    func short(at now: Date) -> String {
        let time = Self.live(elapsed(at: now))
        switch step {
        case .waitingToRead: return L10n.string("Waiting to read · %@", time)
        case .reading: return L10n.string("Reading · %@", time)
        case .handingOff: return L10n.string("Handing off · %@", time)
        case .heldForResume: return L10n.string("Held for you · %@", time)
        case .nextCycle: return L10n.string("Next cycle · %@", time)
        case .awaitingFill: return L10n.string("Waiting for fill · %@", time)
        }
    }
}
