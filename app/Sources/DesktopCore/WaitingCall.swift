import Foundation

/// A post that waits for the owner (ADR-0007): the account won't act on it by itself, so the
/// owner copies it or skips it, through the end of its trading day.
public struct WaitingCall: Equatable, Sendable {
    /// Skips that hold a call back for the owner rather than refuse it; the engine's
    /// `HELD_FOR_OWNER`: an account that approves every order, and a sell naming a buy price none
    /// of its buys has (ADR-0010).
    public static let heldForOwner: Set<String> = ["approval_required", "named_buy_not_held"]

    public let source: SourceActivity
    /// The accounts waiting on it.
    public let accountIDs: [String]
    /// What Copy places: the calls the reader suggests, or the calls an account held back.
    public let calls: [SourceInstruction]
    /// Every account waits only because it asked to approve each order (ADR-0008), so the owner
    /// approves the call rather than copying it.
    public let awaitsApproval: Bool

    /// The waiting call in a post, or nil when no account waits on it.
    public init?(_ source: SourceActivity) {
        var accounts: [String] = []
        var held = Set<Int>()
        var onlyApprovals = true
        for destination in source.destinations {
            let heldParts = destination.instructionOutcomes.indices.filter {
                Self.heldForOwner.contains(destination.instructionOutcomes[$0])
            }
            if destination.status == "review_required" || !heldParts.isEmpty {
                accounts.append(destination.accountID)
                if destination.status == "review_required"
                    || heldParts.contains(where: { destination.instructionOutcomes[$0] != "approval_required" })
                {
                    onlyApprovals = false
                }
            }
            if destination.status == "review_required" {
                held.formUnion(source.instructions.indices)
            }
            held.formUnion(heldParts)
        }
        guard !accounts.isEmpty else { return nil }
        self.source = source
        self.accountIDs = accounts.sorted()
        self.awaitsApproval = onlyApprovals
        self.calls =
            source.suggested.isEmpty
            ? source.instructions.indices.filter(held.contains).map { source.instructions[$0] }
            : source.suggested
    }

    /// Whether the post's trading day has ended, after which it can no longer be copied.
    public func hasExpired(at now: Date) -> Bool {
        guard let posted = EquityCurve.date(source.sourceAt) else { return true }
        return Self.tradingDay(of: posted) != Self.tradingDay(of: now)
    }

    /// When the post's trading day ends and it can no longer be copied: 20:00 New York time.
    public var deadline: Date? {
        EquityCurve.date(source.sourceAt).map(Self.endOfTradingDay(of:))
    }

    /// 20:00 New York time on the trading day `instant` belongs to.
    public static func endOfTradingDay(of instant: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        var day = tradingDay(of: instant)
        day.hour = 20
        day.minute = 0
        return calendar.date(from: day)!
    }

    /// The New York trading day an instant belongs to; from 20:00 it is the next day's, as the
    /// engine's `trade_date` counts it.
    public static func tradingDay(of instant: Date) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let day =
            calendar.component(.hour, from: instant) >= 20
            ? calendar.date(byAdding: .day, value: 1, to: instant)!
            : instant
        return calendar.dateComponents([.year, .month, .day], from: day)
    }
}
