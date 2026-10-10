import DesktopCore
import Foundation

/// A buy an account holds after a restart until the owner resumes its entries (manual recovery):
/// which accounts hold this post, and by when a Resume still copies it. Past that moment the
/// post is too old to trade and the engine skips it.
@MainActor
struct ResumeWait: Equatable {
    /// Account id → the last moment a Resume still copies the post.
    let deadlines: [String: Date]

    static var none: ResumeWait { ResumeWait(deadlines: [:]) }

    init(deadlines: [String: Date]) {
        self.deadlines = deadlines
    }

    /// `waiting` are the accounts whose entries wait for the owner's Resume; `signalAge` is each
    /// account's maximum signal age in seconds.
    init(_ source: SourceActivity, waiting: Set<String>, signalAge: (String) -> Int) {
        guard !waiting.isEmpty, let postedAt = Humanize.date(source.sourceAt) else {
            self.init(deadlines: [:])
            return
        }
        var deadlines: [String: Date] = [:]
        for destination in source.destinations
        where waiting.contains(destination.accountID) && Self.isHeld(destination) {
            deadlines[destination.accountID] = postedAt.addingTimeInterval(TimeInterval(signalAge(destination.accountID)))
        }
        self.init(deadlines: deadlines)
    }

    /// The accounts the engine reports as waiting for the owner's Resume after a restart.
    static func waitingAccounts(_ accounts: [AccountOverview]) -> Set<String> {
        Set(accounts.filter { $0.readiness == "manual_resume_required" }.map(\.accountID))
    }

    /// Each account's maximum signal age from the saved setup, or the default.
    static func signalAge(in setup: TradingConfiguration?) -> (String) -> Int {
        { accountID in
            setup?.accounts.first { $0.id == accountID }?.policy.maxSignalAgeSeconds
                ?? TradingAccountPolicy().maxSignalAgeSeconds
        }
    }

    /// No order yet and nothing settled or skipped: the engine still holds the call.
    static func isHeld(_ destination: DestinationActivity) -> Bool {
        destination.orders.isEmpty
            && !["review_required", "stale", "out_of_order", "ignored", "done"].contains(destination.status)
            && destination.instructionOutcomes.allSatisfy { ActivityCardOutcome.carriedOn.contains($0) }
    }
}
