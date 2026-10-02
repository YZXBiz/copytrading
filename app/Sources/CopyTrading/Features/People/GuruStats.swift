import DesktopCore
import Foundation

/// How a guru's calls went, counted from the posts CopyTrading has loaded.
struct GuruStats {
    let posts: Int
    let trades: Int
    /// Orders, across every account, that filled or were skipped.
    let filled: Int
    let skipped: Int
    /// Calls at least one account filled, and calls no account filled but one skipped.
    let copiedCalls: Int
    let skippedCalls: Int
    let needsReview: Int
    let lastPost: Date?
    /// How each recent post went, oldest first: up to the last twelve.
    let trail: [StatusTone]

    @MainActor
    init(guruID: String, activity: [SourceActivity]) {
        let mine = activity.filter { $0.guruID == guruID }
        let outcomes = mine.flatMap { $0.outcomes }.map(\.outcome)
        posts = mine.count
        trades = mine.filter { !$0.instructions.isEmpty }.count
        filled = outcomes.filter(Self.isFill).count
        skipped = outcomes.filter(Self.isSkip).count
        let calls = mine.filter { !$0.instructions.isEmpty }.map { activity in
            activity.outcomes.map(\.outcome)
        }
        copiedCalls = calls.filter { $0.contains(where: Self.isFill) }.count
        skippedCalls = calls.filter { !$0.contains(where: Self.isFill) && $0.contains(where: Self.isSkip) }.count
        needsReview = mine.filter(\.needsManualReview).count
        lastPost = mine.compactMap(\.sourceDate).max()
        trail = mine.sorted { ($0.sourceDate ?? .distantPast) < ($1.sourceDate ?? .distantPast) }.suffix(12).map(\.decisionTone)
    }

    private static func isFill(_ outcome: DestinationOutcome) -> Bool {
        if case .filled = outcome { true } else if case .partlyFilled = outcome { true } else { false }
    }

    private static func isSkip(_ outcome: DestinationOutcome) -> Bool {
        if case .skipped = outcome { true } else { false }
    }
}
