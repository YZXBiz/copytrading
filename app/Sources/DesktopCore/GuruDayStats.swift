import Foundation

/// One guru's numbers for the owner's day, counted by the engine from every post it holds rather
/// than from the page of posts the app has loaded.
public struct GuruDayStats: Codable, Equatable, Sendable {
    public let guruID: String
    public let posts: Int
    /// The day's posts at least one account bought or sold on.
    public let traded: Int
    /// How long the reader took per post that day, on average; nil before any was read.
    public let readSeconds: Double?
    /// Posts of the current trading day with a call still waiting for the owner, whatever their
    /// calendar day, newest first and whole, so they list though the app never loaded them. The
    /// guru's page lists exactly these, less what `stillWaiting` drops, so its count is its tab.
    public let waiting: [SourceActivity]

    public init(guruID: String, posts: Int, traded: Int, readSeconds: Double?, waiting: [SourceActivity]) {
        self.guruID = guruID
        self.posts = posts
        self.traded = traded
        self.readSeconds = readSeconds
        self.waiting = waiting
    }

    /// The posts still waiting for the owner at `now`: what the engine counted, less the ones
    /// the owner has skipped or entered by hand and the ones whose trading day has ended since.
    public func stillWaiting(skipped: (String) -> Bool, now: Date) -> [SourceActivity] {
        waiting.filter { WaitingCall.open($0, skipped: skipped($0.sourceID), now: now) != nil }
    }

    enum CodingKeys: String, CodingKey {
        case guruID = "guru_id"
        case posts
        case traded
        case readSeconds = "read_seconds"
        case waiting
    }
}
