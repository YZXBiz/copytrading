import Foundation

/// The words and the line for the live moment on the card: one headline per step, a calm line
/// under it, which of the four stops the post is at, and how far a fill wait has come.
extension PostProgress {
    /// The last stop on the line: read, sized, sent, then filled.
    static let filledStage = 4

    var stage: Int {
        switch step {
        case .waitingToRead: 0
        case .reading: 1
        case .handingOff, .nextCycle, .heldForResume: 2
        case .awaitingFill: 3
        }
    }

    /// The step waits on the owner, the one thing on the card in amber.
    var waitsOnOwner: Bool {
        if case .heldForResume = step { return true }
        return false
    }

    /// "Reading the post…"
    var headline: String {
        switch step {
        case .waitingToRead: L10n.string("Waiting its turn…")
        case .reading: L10n.string("Reading the post…")
        case .handingOff, .nextCycle: L10n.string("Sizing the order…")
        case .heldForResume: L10n.string("Held for you")
        case .awaitingFill: L10n.string("Sent to Alpaca")
        }
    }

    /// "deepseek-flash is reading it · 2 s". A fill wait shows its time on the line instead.
    func calmLine(at now: Date) -> String {
        let time = Self.live(elapsed(at: now))
        switch step {
        case .waitingToRead:
            return L10n.string("In line to be read · %@", time)
        case .reading(let model?):
            return L10n.string("%@ is reading it · %@", model, time)
        case .reading(nil):
            return L10n.string("Reading it · %@", time)
        case .handingOff:
            return L10n.string("Working out each account's share · %@", time)
        case .nextCycle(let account):
            return L10n.string("%@ picks it up on its next cycle · %@", account, time)
        case .heldForResume(let account, _):
            return L10n.string("%@ holds new buys until you resume entries · %@", account, time)
        case .awaitingFill(_, let symbol, _):
            return L10n.string("%@ is waiting for a fill", symbol)
        }
    }

    /// How far a fill wait has come toward the account's order timeout, 0…1; without a known
    /// timeout it creeps toward the end and never reaches it.
    func fillWait(at now: Date) -> Double? {
        guard case .awaitingFill(_, _, let timeout) = step else { return nil }
        let seconds = elapsed(at: now)
        guard let timeout, timeout > 0 else { return seconds / (seconds + 30) }
        return min(seconds / timeout, 1)
    }

    /// "23 s of 60 s" over the fill wait, or "23 s" when the timeout is not known.
    func fillWaitText(at now: Date) -> String? {
        guard case .awaitingFill(_, _, let timeout) = step else { return nil }
        let time = Self.live(elapsed(at: now))
        return timeout.map { L10n.string("%@ of %@", time, Self.live($0)) } ?? time
    }
}
