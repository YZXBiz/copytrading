import Foundation

/// The words and the ink dot's place for the live moment on the card: one headline per step, a
/// calm line under it with the running time, and how far along the ground the dot has come.
extension PostProgress {
    /// The ink dot's stop on the ground: read, sized, sent, then filled.
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
        case .awaitingFill: L10n.string("Sending to Alpaca…")
        }
    }

    /// "deepseek-flash is reading it · 2 s"
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
        case .awaitingFill(_, let symbol, let timeout?):
            return L10n.string("%@ is waiting for a fill · %@ of %@", symbol, time, Self.live(timeout))
        case .awaitingFill(_, let symbol, nil):
            return L10n.string("%@ is waiting for a fill · %@", symbol, time)
        }
    }
}
