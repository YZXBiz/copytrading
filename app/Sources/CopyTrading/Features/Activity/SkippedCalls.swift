import Foundation
import Observation

/// The waiting calls the owner chose to skip (ADR-0007). Skipping places nothing and changes
/// nothing in the engine; it only takes a call off the owner's list, so it is kept with the
/// app's preferences and forgotten after a week, long after the call itself has expired.
@MainActor
@Observable
final class SkippedCalls {
    static let storageKey = "skippedWaitingCalls"
    private static let kept: TimeInterval = 7 * 24 * 3600

    private let defaults: UserDefaults
    private(set) var skipped: [String: Date]
    /// The call skipped last and when, so it can be brought back for a few seconds.
    private(set) var recent: (sourceID: String, text: String, at: Date)?
    /// How long a skip can be undone in place.
    static let undoWindow: TimeInterval = 10

    init(defaults: UserDefaults = .standard, now: Date = .now) {
        self.defaults = defaults
        let stored = defaults.dictionary(forKey: Self.storageKey) as? [String: Date] ?? [:]
        skipped = stored.filter { now.timeIntervalSince($0.value) < Self.kept }
        defaults.set(skipped, forKey: Self.storageKey)
    }

    func contains(_ sourceID: String) -> Bool { skipped[sourceID] != nil }

    func skip(_ sourceID: String, text: String = "", at now: Date = .now) {
        skipped[sourceID] = now
        recent = (sourceID, text, now)
        defaults.set(skipped, forKey: Self.storageKey)
    }

    /// Puts the last skipped call back on the owner's list.
    func undo() {
        guard let recent else { return }
        skipped.removeValue(forKey: recent.sourceID)
        self.recent = nil
        defaults.set(skipped, forKey: Self.storageKey)
    }

    /// The skip that can still be undone at `now`, if any.
    func undoable(at now: Date = .now) -> (sourceID: String, text: String, at: Date)? {
        guard let recent, now.timeIntervalSince(recent.at) < Self.undoWindow else { return nil }
        return recent
    }
}
