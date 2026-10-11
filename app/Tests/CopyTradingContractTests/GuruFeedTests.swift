import CopyTradingTestSupport
import DesktopCore
import Foundation
import Testing

/// A guru's page: only their posts, newest first by day, and what each account did with each one.
@MainActor
func runGuruFeedTests() throws {
    try aGurusPageShowsOnlyTheirPostsNewestFirstByDay()
    try eachAccountSaysWhatItDidInAFewWords()
    try theStatsCountTodayAndWhatWaits()
}

private let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
private let morning = "2026-10-05T15:00:00Z"

private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = losAngeles
    return calendar
}

private func date(_ iso: String) throws -> Date {
    try Date(iso, strategy: .iso8601)
}

private func post(_ sequence: Int, guru: String, at iso: String) -> SourceActivityBuilder {
    SourceActivityBuilder().sequence(sequence, sourceID: "discord:1:\(sequence)").guru(guru).posted(at: iso)
}

@MainActor
private func aGurusPageShowsOnlyTheirPostsNewestFirstByDay() throws {
    let activity = [
        try post(1, guru: "zhao", at: "2026-10-02T16:00:00Z").build(),
        try post(2, guru: "lee", at: "2026-10-05T14:00:00Z").build(),
        try post(3, guru: "zhao", at: "2026-10-05T14:10:00Z").build(),
        try post(4, guru: "zhao", at: "2026-10-05T14:20:00Z").build(),
    ]
    let posts = GuruFeed.posts(of: "zhao", in: activity).map(\.sequence)
    try #require(posts == [4, 3, 1], "zhao's posts were \(posts)")

    let feed = GuruFeed(guruID: "zhao", activity: activity, skipped: { _ in false }, now: try date(morning), calendar: calendar)
    let days = feed.days.map { $0.entries.map(\.item.sequence) }
    try #require(days == [[4, 3], [1]], "the days held \(days)")
    try #require(GuruFeed(guruID: "nobody", activity: activity, skipped: { _ in false }).days.isEmpty, "a stranger had posts")
}

@MainActor
private func eachAccountSaysWhatItDidInAFewWords() throws {
    let source = try post(1, guru: "zhao", at: "2026-10-05T14:30:00Z")
        .calls([SourceActivityBuilder.buy("SOUN", "5.85", fraction: "0.1667")])
        .destination(
            "primary", status: "done", outcomes: ["symbol_exposure_cap"],
            limits: [["part": 0, "scope": "symbol", "current": "1900", "proposed": "333.33", "limit": "2000"]]
        )
        .destination(
            "ira", status: "done", outcomes: ["order_linked"],
            orders: [
                [
                    "client_id": "c1", "symbol": "SOUN", "side": "buy", "status": "filled", "quantity": "42",
                    "filled_quantity": "42", "limit_price": "5.85", "average_fill_price": "5.85", "broker_id": "b1",
                    "created_at": "2026-10-05T14:30:01Z", "instruction_index": 0,
                ]
            ]
        )
        .destination("roth", status: "done", outcomes: ["approval_required"])
        .build()

    let outcomes = GuruAccountOutcome.outcomes(of: source, skipped: false, now: try date(morning))

    try #require(
        outcomes == [
            .init(accountID: "primary", summary: "Not bought: over your SOUN limit", kind: .notTraded),
            .init(accountID: "ira", summary: "Bought $245.70 of SOUN", kind: .traded),
            .init(accountID: "roth", summary: "Waiting for your approval", kind: .waiting),
        ], "outcomes were \(outcomes)")

    let chatter = try post(2, guru: "zhao", at: "2026-10-05T14:31:00Z").decision("ignore").build()
    try #require(GuruAccountOutcome.outcomes(of: chatter, skipped: false).isEmpty, "talk reached an account")
    let entry = GuruFeed(guruID: "zhao", activity: [chatter], skipped: { _ in false }).days.first?.entries.first
    try #require(entry?.readAs == "Not a trade", "talk read as \(entry?.readAs ?? "nil")")
}

@MainActor
private func theStatsCountTodayAndWhatWaits() throws {
    let filled: [String: Any] = [
        "client_id": "c1", "symbol": "SOUN", "side": "buy", "status": "filled", "quantity": "1",
        "filled_quantity": "1", "limit_price": "5.85", "average_fill_price": "5.85", "broker_id": "b1",
        "created_at": "2026-10-05T14:30:01Z", "instruction_index": 0,
    ]
    let activity = [
        try post(1, guru: "zhao", at: "2026-10-05T14:30:00Z")
            .read(started: "2026-10-05T14:30:01Z", finished: "2026-10-05T14:30:03Z", delivered: "2026-10-05T14:30:03Z")
            .destination("primary", status: "done", outcomes: ["order_linked"], orders: [filled]).build(),
        try post(2, guru: "zhao", at: "2026-10-05T14:40:00Z")
            .read(started: "2026-10-05T14:40:01Z", finished: "2026-10-05T14:40:05Z", delivered: "2026-10-05T14:40:05Z")
            .destination("primary", status: "done", outcomes: ["approval_required"]).build(),
        try post(3, guru: "zhao", at: "2026-10-02T16:00:00Z")
            .destination("primary", status: "done", outcomes: ["order_linked"], orders: [filled]).build(),
    ]

    let stats = GuruFeed(guruID: "zhao", activity: activity, skipped: { _ in false }, now: try date(morning), calendar: calendar)
        .stats

    try #require(stats.postsToday == 2 && stats.tradedToday == 1, "today counted \(stats)")
    try #require(stats.waiting == 1, "waiting counted \(stats.waiting)")
    try #require(stats.averageRead == 3, "reads averaged \(stats.averageRead ?? -1)")

    let skipped = GuruFeed(
        guruID: "zhao", activity: activity, skipped: { $0 == "discord:1:2" }, now: try date(morning), calendar: calendar)
    try #require(skipped.stats.waiting == 0, "a skipped call still waited")
}
