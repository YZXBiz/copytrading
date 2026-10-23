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
    try theWaitingTabListsEveryCallTheCountSays()
    try await anAccountTheBrokerHasNoCurveForStopsReading()
    try await holdingsCountOnlyAccountsInTheSetup()
    try aGuruIsTheirChannelsWhateverIDTheSetupSavedThemWith()
}

/// A setup saved before IDs came from the channel still names its guru by their channel, so the
/// posts and holdings the engine names that way show under them (the owner's 赵哥 after beta.6).
@MainActor
private func aGuruIsTheirChannelsWhateverIDTheSetupSavedThemWith() throws {
    let profile = try TradingProfileBuilder().build(TradingProfileDraft(guruID: "guru-0fb5ed9b", displayName: "赵哥"))
    let configuration = TradingConfiguration(
        source: TradingSourceConfiguration(channelIDs: ["1517754775674949742"], authorIDs: []),
        provider: TradingProviderConfiguration(name: .deepseek, model: "deepseek-flash"),
        accounts: [TradingAccountConfiguration(id: "zhap-account-2", environment: .paper)],
        profiles: [profile],
        routes: [
            TradingRouteConfiguration(
                channelID: "1517754775674949742", guruID: profile.guruID, profileRevision: profile.profileRevision,
                connections: [TradingRouteConnection(accountID: "zhap-account-2", fullPositionUSD: "1000")])
        ])
    // The same ID the engine names the channel's posts with (route_keys.guru_for_channel).
    #expect(GuruIdentity.id(channelID: "1517754775674949742") == "guru-3909e2aa")
    let directory = GuruDirectory(configuration)
    #expect(directory.gurus.map(\.id) == ["guru-3909e2aa"])
    #expect(directory.name(for: "guru-3909e2aa") == "赵哥")
    print("CopyTradingContractTests: a guru is their channel's, whatever ID the setup saved them with")
}

/// A guru's holdings count only the accounts the setup copies into: an account removed from the
/// setup keeps its shares at the broker, but they are no longer this guru's in CopyTrading.
@MainActor
private func holdingsCountOnlyAccountsInTheSetup() async throws {
    let accounts = try await GuruDayActions().accounts(beforeAccountID: nil, limit: 50).items
    let held = GuruHoldings(guruID: "alex", accounts: accounts, setUpAccountIDs: ["paper"])
    #expect(held?.stocks == 1)
    #expect(held?.cost == Decimal(string: "50.20"))
    #expect(GuruHoldings(guruID: "alex", accounts: accounts, setUpAccountIDs: ["zhap-account-2"]) == nil)
    #expect(GuruHoldings(guruID: "someone-else", accounts: accounts, setUpAccountIDs: ["paper"]) == nil)
    print("CopyTradingContractTests: a guru's holdings count only the accounts in the setup")
}

/// The engine answers with no curve when it can't ask the broker for one. The account is marked
/// read, so its chart stops saying it is still reading; a new window starts over.
@MainActor
private func anAccountTheBrokerHasNoCurveForStopsReading() async throws {
    let actions = GuruDayActions()
    let feature = AccountFeatureModel()
    feature.authorizePrivateEvidence()
    await feature.refresh(using: actions)
    try #require(feature.historiesRead.isEmpty, "a curve was read before anyone asked")

    await feature.refreshHistories(using: actions)
    try #require(feature.histories["paper"] == nil, "the fake engine returned a curve")
    try #require(feature.historiesRead == ["paper"], "the asked accounts were \(feature.historiesRead)")

    await feature.refreshHistories(window: EquityHistoryWindow(range: .week, day: nil), using: actions)
    try #require(feature.historiesRead == ["paper"], "the week was not asked for")
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

    // The fixture's waiting call was posted at 14:58 UTC on 14 October, 11:00 New York time.
    let now = try date("2026-10-14T16:00:00Z")
    let lee = GuruStats(day: feature.guruDays["lee"], skipped: { _ in false }, isRead: true, now: now)
    try #require(lee.postsToday == 104 && lee.tradedToday == 12 && lee.averageRead == 3.5, "Lee's strip read \(lee)")
    try #require(lee.waiting == 1 && lee.sidebarDetail == "1 need you", "Lee's sidebar read \(lee.sidebarDetail)")

    let skipped = GuruStats(day: feature.guruDays["lee"], skipped: { $0 == "discord:1:1427" }, isRead: true, now: now)
    try #require(skipped.waiting == 0, "a skipped call still waited")
    try #require(skipped.sidebarDetail == "104 posts today", "the sidebar read \(skipped.sidebarDetail)")

    let zhao = GuruStats(day: feature.guruDays["zhao"], skipped: { _ in false }, isRead: true, now: now)
    try #require(zhao.postsToday == 111 && zhao.averageRead == nil, "Zhao's strip read \(zhao)")

    let quiet = GuruStats(day: feature.guruDays["nobody"], skipped: { _ in false }, isRead: true, now: now)
    try #require(
        quiet.postsToday == 0 && quiet.waiting == 0 && quiet.averageRead == nil && quiet.sidebarDetail == "Quiet today",
        "a guru with no posts read \(quiet.sidebarDetail)")

    // Before the engine's day has been read, nothing is counted: no zeros, and no "Quiet today".
    let unread = GuruStats(day: nil, skipped: { _ in false }, isRead: false, now: now)
    try #require(
        unread.postsToday == nil && unread.tradedToday == nil && unread.sidebarDetail == "Not read yet",
        "a guru not read yet read \(unread.sidebarDetail)")
}

/// The engine counted eight calls waiting from last evening's burst; the newest page the app
/// loaded held none of them. The Waiting tab lists those eight, and the number above it is theirs.
@MainActor
private func theWaitingTabListsEveryCallTheCountSays() throws {
    // 11:30 New York on 15 October: the trading day began at 20:00 the evening before.
    let now = try date("2026-10-15T15:30:00Z")
    func held(_ sequence: Int, at iso: String, orders: [[String: Any]] = []) throws -> SourceActivity {
        try post(sequence, guru: "zhao", at: iso).decision("review").destination(
            "primary", status: "review_required", outcomes: [], orders: orders
        ).build()
    }
    let evening = try (1...8).map { try held($0, at: "2026-10-15T00:0\($0):00Z") }
    let entered = try held(
        9, at: "2026-10-15T00:09:00Z",
        orders: [
            [
                "client_id": "manual-1", "symbol": "PM", "side": "buy", "status": "filled", "quantity": "1",
                "filled_quantity": "1", "limit_price": "201", "average_fill_price": "201", "broker_id": "b9",
                "created_at": "2026-10-15T14:00:00Z", "instruction_index": 0,
            ]
        ])
    let yesterday = try held(10, at: "2026-10-14T15:00:00Z")
    let skipped = try held(11, at: "2026-10-15T14:00:00Z")
    let newest = try (20...23).map { try post($0, guru: "zhao", at: "2026-10-15T15:\($0 - 10):00Z").decision("ignore").build() }
    // The engine counts a post by its own clock; the app drops what its day, the owner, or a
    // later hand-entered trade has settled since.
    let day = GuruDayStats(
        guruID: "zhao", posts: 4, traded: 0, readSeconds: nil,
        waiting: (evening + [entered, yesterday, skipped]).reversed())

    let feed = GuruFeed(
        guruID: "zhao", activity: newest, day: day, skipped: { $0 == skipped.sourceID }, now: now,
        calendar: calendar)
    let tab = feed.days.flatMap(\.entries).filter(GuruPostFilter.waiting.includes)
    let all = feed.days.flatMap(\.entries)
    let stats = GuruStats(day: day, skipped: { $0 == skipped.sourceID }, isRead: true, now: now)

    try #require(
        tab.map(\.item.sequence) == Array((1...8).reversed()), "the Waiting tab listed \(tab.map(\.item.sequence))")
    try #require(stats.waiting == 8 && feed.waitingCount == 8, "the strip said \(stats.waiting), the feed \(feed.waitingCount)")
    try #require(stats.waiting == tab.count, "the count and the tab differ")
    // The calls settled since the engine counted them are not in the feed unless they were loaded.
    try #require(all.count == 4 + 8, "the feed held \(all.map(\.item.sequence)), loaded and waiting")
    let notTraded = all.filter(GuruPostFilter.notTraded.includes).map(\.item.sequence)
    try #require(notTraded == [23, 22, 21, 20], "Not traded held \(notTraded)")
    try #require(
        GuruFeed(guruID: "zhao", activity: newest, skipped: { _ in false }, now: now).waitingCount == 0,
        "posts the engine did not count read as waiting")
}
