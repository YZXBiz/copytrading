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
    /// calendar day; the app leaves out the ones the owner skipped.
    public let waitingSourceIDs: [String]

    public init(guruID: String, posts: Int, traded: Int, readSeconds: Double?, waitingSourceIDs: [String]) {
        self.guruID = guruID
        self.posts = posts
        self.traded = traded
        self.readSeconds = readSeconds
        self.waitingSourceIDs = waitingSourceIDs
    }

    enum CodingKeys: String, CodingKey {
        case guruID = "guru_id"
        case posts
        case traded
        case readSeconds = "read_seconds"
        case waitingSourceIDs = "waiting_source_ids"
    }
}
