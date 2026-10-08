import DesktopCore
import Foundation

/// How often Activity is read: every second while a post is in flight, so its live step keeps
/// up, and every 15 seconds once everything has settled.
@MainActor
enum ActivityRefreshCadence {
    static let inFlight: TimeInterval = 1
    static let settled: TimeInterval = 15

    static func interval(for activity: [SourceActivity]) -> TimeInterval {
        activity.contains { PostProgress($0) != nil } ? inFlight : settled
    }
}
