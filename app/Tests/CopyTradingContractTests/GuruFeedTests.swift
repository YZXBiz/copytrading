import CopyTradingTestSupport
import DesktopCore
import Foundation
import Testing

/// A guru's page: only their posts, newest first by day, and what each account did with each one.
@MainActor
func runGuruFeedTests() async throws {
    try aGurusPageShowsOnlyTheirPostsNewestFirstByDay()
    try eachAccountSaysWhatItDidInAFewWords()
    try await theStripAndSidebarCountTheEnginesWholeDay()
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

/// On a busy day the app has loaded only the newest page of posts across every guru; the strip
/// and the sidebar say what the engine counted over the owner's whole day instead.
@MainActor
private func theStripAndSidebarCountTheEnginesWholeDay() async throws {
    let actions = GuruDayActions()
    let feature = AccountFeatureModel()
    feature.authorizePrivateEvidence()

    await feature.refresh(using: actions)

    let window = await actions.window
    let start = AppTime.calendar.startOfDay(for: .now)
    try #require(window?.start == start, "the day began at \(String(describing: window?.start))")
    try #require(
        window?.end == AppTime.calendar.date(byAdding: .day, value: 1, to: start),
        "the day ended at \(String(describing: window?.end))")
    try #require(feature.activity.count == 1, "the loaded page held \(feature.activity.count) posts")

    let lee = GuruStats(day: feature.guruDays["lee"], skipped: { _ in false })
    try #require(lee.postsToday == 104 && lee.tradedToday == 12 && lee.averageRead == 3.5, "Lee's strip read \(lee)")
    try #require(lee.waiting == 1 && lee.sidebarDetail == "1 need you", "Lee's sidebar read \(lee.sidebarDetail)")

    let skipped = GuruStats(day: feature.guruDays["lee"], skipped: { $0 == "discord:1:1427" })
    try #require(skipped.waiting == 0, "a skipped call still waited")
    try #require(skipped.sidebarDetail == "104 posts today", "the sidebar read \(skipped.sidebarDetail)")

    let zhao = GuruStats(day: feature.guruDays["zhao"], skipped: { _ in false })
    try #require(zhao.postsToday == 111 && zhao.averageRead == nil, "Zhao's strip read \(zhao)")

    let quiet = GuruStats(day: feature.guruDays["nobody"], skipped: { _ in false })
    try #require(
        quiet.postsToday == 0 && quiet.waiting == 0 && quiet.averageRead == nil && quiet.sidebarDetail == "Quiet today",
        "a guru with no posts read \(quiet.sidebarDetail)")
}
