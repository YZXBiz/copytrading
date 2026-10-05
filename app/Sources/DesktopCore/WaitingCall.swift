import Foundation

/// A post that waits for the owner (ADR-0007): the account won't act on it by itself, so the
/// owner copies it or skips it, through the end of its trading day.
public struct WaitingCall: Equatable, Sendable {
    /// Skips that hold a call back for the owner rather than refuse it; the engine's
    /// `HELD_FOR_OWNER`.
    public static let heldForOwner: Set<String> = ["price_moved"]

    public let source: SourceActivity
    /// The accounts waiting on it.
    public let accountIDs: [String]
    /// What Copy places: the calls the reader suggests, or the calls an account held back.
    public let calls: [SourceInstruction]

    /// The waiting call in a post, or nil when no account waits on it.
    public init?(_ source: SourceActivity) {
        var accounts: [String] = []
        var held = Set<Int>()
        for destination in source.destinations {
            let heldParts = destination.instructionOutcomes.indices.filter {
                Self.heldForOwner.contains(destination.instructionOutcomes[$0])
            }
            if destination.status == "review_required" || !heldParts.isEmpty {
                accounts.append(destination.accountID)
            }
            if destination.status == "review_required" {
                held.formUnion(source.instructions.indices)
            }
            held.formUnion(heldParts)
        }
        guard !accounts.isEmpty else { return nil }
        self.source = source
        self.accountIDs = accounts.sorted()
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
