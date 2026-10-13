import DesktopCore
import Foundation
import Testing

/// A holding is told start to finish from the account's activity: the post's buy, a later post's
/// buy that joined it, and the owner's sale of all of it, with what it came to. A holding that is
/// still just the post's one buy has no story.
@MainActor
func runPositionStoryTests() throws {
    func row(
        _ sequence: Int, _ at: String, _ kind: String, source: String, shares: String, price: String,
        message: String, lot: String?
    ) -> [String: Any] {
        [
            "sequence": sequence, "at": at, "kind": kind, "source": source,
            "side": kind == "bought" ? "buy" : "sell", "symbol": "NFLX", "shares": shares, "price": price,
            "amount": NSDecimalNumber(decimal: Decimal(string: shares)! * Decimal(string: price)!).stringValue,
            "guru_id": source == "guru" ? "zhao" : NSNull(), "message_id": message, "order_id": "o\(sequence)",
            "lot_id": lot ?? NSNull(), "changes": [], "reason": NSNull(),
        ]
    }
    func feed(_ rows: [[String: Any]]) throws -> [AccountFeedItem] {
        try JSONDecoder().decode([AccountFeedItem].self, from: JSONSerialization.data(withJSONObject: rows))
    }
    let first = "discord:1:100"
    let second = "discord:1:200"
    let items = try feed([
        row(3, "2026-10-12T17:54:03Z", "sold", source: "you", shares: "8.328828", price: "70.79", message: first, lot: "lot-a"),
        row(2, "2026-10-12T17:52:47Z", "bought", source: "guru", shares: "1.3563", price: "70.80", message: second, lot: "lot-a"),
        row(1, "2026-10-12T17:52:19Z", "bought", source: "guru", shares: "6.972528", price: "70.80", message: first, lot: "lot-a"),
        row(0, "2026-10-12T17:46:23Z", "bought", source: "guru", shares: "9.803921", price: "48.49", message: "discord:1:50", lot: "lot-b"),
    ])

    let story = try #require(PositionStory(post: first, feed: items), "the holding had no story")
    try #require(story.steps.map(\.kind) == [.bought, .added, .soldAll], "steps were \(story.steps.map(\.kind))")
    try #require(story.steps.map(\.isThisPost) == [true, false, false], "the wrong step was marked as this post")
    try #require(story.steps.last?.byOwner == true, "the owner's sale read as copied")
    let expected =
        Decimal(string: "8.328828")! * Decimal(string: "70.79")!
        - Decimal(string: "6.972528")! * Decimal(string: "70.80")! - Decimal(string: "1.3563")! * Decimal(string: "70.80")!
    try #require(story.result == expected, "result was \(String(describing: story.result))")

    // The post whose buy joined the holding tells the same story, its own buy marked instead.
    let joined = try #require(PositionStory(post: second, feed: items), "the joining post had no story")
    try #require(joined.steps.map(\.isThisPost) == [false, true, false], "the joining post's buy was not marked")

    // A holding that is only its one buy, still open, is the order's own result.
    try #require(PositionStory(post: "discord:1:50", feed: items) == nil, "a lone buy got a story")
    // Rows from before the engine named holdings tell nothing.
    let unnamed = try feed([row(1, "2026-10-12T17:52:19Z", "bought", source: "guru", shares: "1", price: "70", message: first, lot: nil)])
    try #require(PositionStory(post: first, feed: unnamed) == nil, "a row with no holding got a story")
    print("CopyTradingContractTests: a holding is told start to finish from every post that bought or sold it")
}
