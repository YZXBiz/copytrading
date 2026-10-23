import CopyTradingTestSupport
import DesktopCore
import Foundation
import Testing

/// The Activity card's words (ADR-0007): how it reads a post, which words it marks, and how a
/// post ended for each account.
@MainActor
func runActivityCardTests() throws {
    try readAsSaysEachCallInPlainWords()
    try aRepeatedNumberIsMarkedBesideTheOtherCitedWords()
    try aTrimmedBuyIsTradedSmallerAndSaysByHowMuch()
    try aBuyCutToTheRoomLeftNamesTheLimitThatCutIt()
    try aSellReadLateWaitsAtItsFloorUnderTheGurusPrice()
    try aSellCancelledWithTheMarketAboveItsFloorNeverReadsAsOverALimit()
    try aSellNotFilledByTheCloseSaysTheMarketStayedUnderItsFloor()
    try aPostOfBuysReadTooLateSaysHowLate()
    try aSellOlderThanEveryBuyHeldSaysWhenEachWasPosted()
    try aSellWithNoBidYetSaysItWaitsForAPrice()
    try aLotSoldByHandStaysTheOwners()
    try aPostTheOwnerTradedByHandReadsAsTheirs()
    try aBuyNamesTheGurusPriceAndTheAllowanceItsLimitUsed()
    try aSkipNamesTheLimitWithItsNumbers()
    try aCallHeldForApprovalAsksToBeApproved()
    try aCallWaitingWithNoReasonHasNoNote()
    try aBuyHeldForAResumeAsksToResumeByItsDeadline()
    try aDeadlineReadsOnTheOwnersClock()
    try theTimeZoneSettingMovesADeadline()
    try activityShowsOnlyTheChosenAccount()
    try aSellWithNoPriceReadsAsAtTheMarket()
    try yesterdaysPostsStopCountingAsTodayAtMidnight()
    try theGuruPageReadsInChinese()
    try aSavedGuruIsChosenByNameNotByNumbers()
    try anEvaluationNoteNeverRepeatsThePost()
}

/// The model's summary of an evaluated post shows only when it says something the post doesn't: a
/// live DeepSeek reading of "sofi another 1/6 at 27.10" summarized it as the same words.
@MainActor
private func anEvaluationNoteNeverRepeatsThePost() throws {
    func evaluation(_ decision: String, reason: String) -> ProfileEvaluation {
        ProfileEvaluation(
            messageIdentity: "m", guruID: "zhao", profileRevision: "r", provider: "deepseek", model: "deepseek-flash",
            decision: decision, reason: reason, simulated: true, noOrder: true, costNotice: "",
            instructions: [], destinations: [], reviewReasons: [])
    }
    let post = "sofi another 1/6 at 27.10"
    let echoed = EvaluationNote.text(evaluation("trade", reason: "SOFI another 1/6  at 27.10"), post: post)
    try #require(echoed == nil, "an echoed summary showed \(echoed ?? "")")
    let summary = EvaluationNote.text(evaluation("trade", reason: "Bought another sixth of SOFI"), post: post)
    try #require(summary == "Bought another sixth of SOFI", "a real summary read \(summary ?? "nil")")
    let code = EvaluationNote.text(evaluation("trade", reason: "trade_made"), post: post)
    try #require(code == nil, "a parser code showed \(code ?? "")")
}

/// Evaluating an earlier post offers each saved guru by name and the accounts they copy into; the
/// channel and author numbers that route their posts never show.
@MainActor
private func aSavedGuruIsChosenByNameNotByNumbers() throws {
    let zhao = try TradingProfileBuilder().build(TradingProfileDraft(guruID: "zhao", displayName: "Zhao"))
    let route = TradingRouteConfiguration(
        channelID: "1287345091273645568", authorID: "804512398817402881", guruID: "zhao",
        profileRevision: zhao.profileRevision,
        connections: [
            TradingRouteConnection(accountID: "primary", fullPositionUSD: "1200"),
            TradingRouteConnection(accountID: "swing", fullPositionUSD: "900"),
        ])
    let configuration = TradingConfiguration(
        source: TradingSourceConfiguration(channelIDs: ["1287345091273645568"]),
        provider: TradingProviderConfiguration(name: .deepseek, model: "deepseek-flash"),
        accounts: [
            TradingAccountConfiguration(id: "primary", environment: .paper),
            TradingAccountConfiguration(id: "swing", environment: .paper),
        ],
        profiles: [zhao], routes: [route])

    let label = SavedGuruLabel.text(route, in: configuration)
    try #require(label == "Zhao · primary, swing", "the saved guru read \(label)")
}

/// In 简体中文 the guru page keeps no English: an ignored post, the holdings line, and a waiting
/// call's deadline in Chinese word order.
@MainActor
private func theGuruPageReadsInChinese() throws {
    let language = AppLanguagePreference.shared
    let original = language.language
    defer { language.select(original) }
    language.select(.simplifiedChinese)

    let ignored = try SourceActivityBuilder().decision("ignore").destination("primary", status: "ignored").build()
    let outcome = GuruAccountOutcome.outcomes(of: ignored, skipped: false).map(\.summary)
    try #require(outcome == ["已忽略"], "an ignored post read \(outcome)")

    let holding = L10n.string("Holding %@ in %lld stocks from these calls", "$650", Int64(3))
    try #require(holding == "这些喊单目前持有 $650，共 3 只股票", "the holdings line read \(holding)")

    let deadline = WaitingCall.endOfTradingDay(of: try Date("2026-10-05T15:00:00Z", strategy: .iso8601))
    let morning = try Date("2026-10-05T15:00:00Z", strategy: .iso8601)
    let zone = TimeZone(identifier: "America/New_York")!
    let chinese = Locale(identifier: "zh-Hans")
    let copyBy = L10n.string("Copy by %@", TradingDeadlineText.text(deadline, now: morning, zone: zone, locale: chinese))
    try #require(copyBy == "请在今天 20:00（纽约时间）前复制", "the deadline read \(copyBy)")
}

/// A count of today's posts asks about the moment it is drawn, so an app left open overnight stops
/// counting yesterday's posts at midnight in the owner's zone.
@MainActor
private func yesterdaysPostsStopCountingAsTodayAtMidnight() throws {
    let preference = AppTimeZonePreference.shared
    let before = preference.chosen
    defer { preference.select(before) }
    preference.select("America/Los_Angeles")
    let post = try SourceActivityBuilder().posted(at: "2026-10-12T22:50:00Z").build()

    try #require(post.isPosted(onDayOf: try Date("2026-10-13T06:00:00Z", strategy: .iso8601)), "11 PM was not the same day")
    try #require(!post.isPosted(onDayOf: try Date("2026-10-13T14:40:00Z", strategy: .iso8601)), "the next morning still counted it")
}

/// "sell wmt half" names no price: the engine sends the call with none, and sells at the market
/// (ADR-0007). The card says so instead of failing to read the post.
@MainActor
private func aSellWithNoPriceReadsAsAtTheMarket() throws {
    let sell: [String: Any] = [
        "action": "reduce", "symbol": "WMT", "price": NSNull(), "entry_price": NSNull(),
        "fraction": "0.5", "exit_basis": "remaining_position",
    ]
    let source = try SourceActivityBuilder().text("sell wmt half").decision("trade", reason: "Sell half")
        .calls([sell]).build()
    try #require(source.instructions.first?.price == nil, "a market sell carried a price")
    try #require(
        source.headline == "Sell half of WMT at the market price", "headline was \(source.headline)")
}

/// Choosing an account keeps the posts that reached it; every account shows all posts.
@MainActor
private func activityShowsOnlyTheChosenAccount() throws {
    let both = try soun().destination("primary", status: "done", outcomes: ["order_linked"])
        .destination("ira", status: "done", outcomes: ["order_linked"]).build()
    let iraOnly = try soun().destination("ira", status: "done", outcomes: ["order_linked"]).build()
    let chatter = try soun().build()
    let state = ActivityScreenState()
    try #require([both, iraOnly, chatter].allSatisfy(state.includes), "every account hid a post")
    state.accountID = "primary"
    try #require(state.includes(both), "primary's post was hidden")
    try #require(!state.includes(iraOnly), "ira's post showed under primary")
    try #require(!state.includes(chatter), "a post no account acted on showed under primary")
}

private let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
private let english = Locale(identifier: "en_US")

/// Times format with a narrow no-break space before AM/PM; compare them as people read them.
private func plain(_ text: String?) -> String? {
    text?.replacingOccurrences(of: "\u{202F}", with: " ")
}

/// A waiting call's deadline, 20:00 New York, in the owner's zone, said as today, tomorrow, or a day.
@MainActor
private func aDeadlineReadsOnTheOwnersClock() throws {
    let deadline = WaitingCall.endOfTradingDay(of: try Date("2026-10-05T15:00:00Z", strategy: .iso8601))
    let morning = try Date("2026-10-05T15:00:00Z", strategy: .iso8601)
    let dayBefore = try Date("2026-10-04T20:00:00Z", strategy: .iso8601)
    let daysBefore = try Date("2026-10-02T15:00:00Z", strategy: .iso8601)
    let today = plain(TradingDeadlineText.text(deadline, now: morning, zone: losAngeles, locale: english))
    try #require(today == "5:00 PM PT today", "the deadline read \(today ?? "nil")")
    let tomorrow = plain(TradingDeadlineText.text(deadline, now: dayBefore, zone: losAngeles, locale: english))
    try #require(tomorrow == "5:00 PM PT tomorrow", "the deadline read \(tomorrow ?? "nil")")
    let later = plain(TradingDeadlineText.text(deadline, now: daysBefore, zone: losAngeles, locale: english))
    try #require(later == "Mon 5:00 PM PT", "the deadline read \(later ?? "nil")")
}

private func readings() throws -> [PostReading] {
    let contracts = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appending(path: "Resources/Contracts")
    return try JSONDecoder().decode(
        [PostReading].self, from: Data(contentsOf: contracts.appending(path: "post-readings.json")))
}

@MainActor
private func readAsSaysEachCallInPlainWords() throws {
    let lines = try readings().map { ReadAsText.lines($0).joined(separator: " | ") }

    try #require(
        lines == [
            "Sell half of the IREN bought at $39.50, at $41.27.",
            "Buy SOUN at $5.85, a sixth of a full position.",
            "Sell all of RCL, at $260.",
            "Buy CBRS between $160 and $179.",
            "Buy SCO at $20, batch 1.",
            "Buy SCO at the market price.",
            "Buy SOUN at $5.85, a sixth of a full position. A re-post of an earlier call.",
            "TSLA 373 is still resistance today",
            "Just chat, nothing to trade",
            "The reader couldn't tell what this post means.",
            "Buy $200 of NFLX at $71.",
            "Sell some of KO, at the market price.",
        ], "Read as lines changed: \(lines)")
    try #require(
        try ReadAsText.note(readings()[10].calls[0]) == nil, "a dollar size has no full-position note")
    try #require(
        try ReadAsText.note(readings()[3].calls[0]) == "no size given, so a full position",
        "Read as note changed")
}

@MainActor
private func aRepeatedNumberIsMarkedBesideTheOtherCitedWords() throws {
    let post = "Cbrs 上次叫大家217 盈利跑路，现在179 又是机会。建仓区域160-179， 跑路区域210 以上"

    let ranges = CitedWordMarks.ranges(of: ["建仓", "Cbrs", "160", "179"], in: post)
    let marks = ranges.map { String(post[$0]) }
    let range179 = try #require(ranges.last)

    try #require(marks == ["建仓", "Cbrs", "160", "179"], "marked \(marks)")
    try #require(post[range179.lowerBound...].hasPrefix("179，"), "the range's 179 was not the one marked")
}

/// A SOUN buy of a sixth, as zhao-paper saw it.
private func soun() -> SourceActivityBuilder {
    SourceActivityBuilder().decision("trade", reason: "Bought").calls([SourceActivityBuilder.buy("SOUN", "5.85", fraction: "0.1667")])
}

@MainActor
private func aTrimmedBuyIsTradedSmallerAndSaysByHowMuch() throws {
    let source = try soun()
        .destination(
            "zhao-paper", status: "done", outcomes: ["order_linked"],
            orders: [
                [
                    "client_id": "c1", "symbol": "SOUN", "side": "buy", "status": "filled", "quantity": "42",
                    "filled_quantity": "42", "limit_price": "5.85", "average_fill_price": "5.85", "broker_id": "b1",
                    "created_at": "2026-10-05T14:30:01Z", "instruction_index": 0, "requested_usd": "333.33",
                    "budget_usd": "250",
                ]
            ]
        )
        .build()

    let outcome = ActivityCardOutcome(source, skipped: false)

    try #require(outcome.title == "Traded smaller", "badge was \(outcome.title)")
    let result = try #require(outcome.accounts.first?.results.first)
    try #require(result.headline == "Bought $245.70 of SOUN", "headline was \(result.headline)")
    try #require(
        result.facts
            == [
                .init(label: "Shares", value: "42 shares"),
                .init(label: "Order", value: "$250 · your largest single buy"),
                .init(label: "The call asked for", value: "$333.33"),
            ],
        "facts were \(result.facts)")
    // The fill price is drawn beside the limit on the ruler rather than listed as a number.
    try #require(
        result.prices == PricePoints(limit: 5.85, market: 5.85, marketLabel: "Filled at", buying: true),
        "prices were \(String(describing: result.prices))")
}

/// A buy whose lot the owner later sold from the account page: the post bought it, the owner sold it.
@MainActor
private func aLotSoldByHandStaysTheOwners() throws {
    let order: (String, String, String) -> [String: Any] = { id, side, price in
        [
            "client_id": id, "symbol": "SOUN", "side": side, "status": "filled", "quantity": "42",
            "filled_quantity": "42", "limit_price": price, "average_fill_price": price, "broker_id": id,
            "created_at": "2026-10-05T14:30:01Z", "instruction_index": 0,
        ]
    }
    let source = try soun()
        .destination(
            "zhao-paper", status: "done", outcomes: ["order_linked"],
            orders: [order("copy-1", "buy", "5.85"), order("lotsale-1", "sell", "6.10")]
        )
        .build()
    let destination = try #require(source.destinations.first)
    try #require(
        DestinationOutcome(destination) == .filled("Bought $245.70 of SOUN"),
        "summary was \(DestinationOutcome(destination))")
    let headlines = ActivityCardOutcome(source, skipped: false).accounts.first?.results.map(\.headline) ?? []
    try #require(headlines == ["Bought $245.70 of SOUN", "You sold $256.20 of SOUN"], "headlines were \(headlines)")

    // The owner's sale resting or expiring unfilled is theirs; the post still traded.
    var resting = order("lotsale-2", "sell", "6.40")
    resting["status"] = "expired"
    resting["filled_quantity"] = "0"
    let expired = try soun()
        .destination("zhao-paper", status: "done", outcomes: ["order_linked"], orders: [order("copy-1", "buy", "5.85"), resting])
        .build()
    let title = ActivityCardOutcome(expired, skipped: false).title
    try #require(title == L10n.string("Traded"), "the post read \(title) while the owner's sale expired")
}

/// A buy that ran past a 1% allowance says the guru's price and the 1%, so a changed limit shows.
@MainActor
private func aBuyNamesTheGurusPriceAndTheAllowanceItsLimitUsed() throws {
    let source = try soun()
        .destination(
            "zhao-paper", status: "done", outcomes: ["order_linked"],
            orders: [
                [
                    "client_id": "copy-1", "symbol": "SOUN", "side": "buy", "status": "canceled", "quantity": "42",
                    "filled_quantity": "0", "limit_price": "5.91", "broker_id": "b1",
                    "created_at": "2026-10-05T14:30:01Z", "instruction_index": 0, "source_price": "5.85",
                    "entry_tolerance_pct": "1", "quote_ask": "5.97", "cancel_reason": "timeout",
                ]
            ]
        )
        .build()
    let result = try #require(ActivityCardOutcome(source, skipped: false).accounts.first?.results.first)
    try #require(result.headline == "Not bought: the price ran above your limit", "headline was \(result.headline)")
    try #require(
        result.facts.first == .init(label: "Guru's price", value: "$5.85 + 1% allowed"), "facts were \(result.facts)")
}

/// "hm" read as unclear waits for the owner; they enter an NVDA buy by hand and it fills. The
/// post is then the owner's trade: no "Needs your review", no skip, and one result, not "and 1 more".
@MainActor
private func aPostTheOwnerTradedByHandReadsAsTheirs() throws {
    let order: [String: Any] = [
        "client_id": "manual-d00bb87d4b756f6cc43d7b33036bd0f8dc7f1bf3", "symbol": "NVDA", "side": "buy",
        "status": "filled", "quantity": "0.655537", "filled_quantity": "0.655537", "limit_price": "228.82",
        "average_fill_price": "226.558", "broker_id": "b1", "created_at": "2026-10-05T14:31:50Z",
        "instruction_index": 0, "requested_usd": "150", "budget_usd": "150",
    ]
    let source = try SourceActivityBuilder().text("hm").decision("review", reason: "unclear")
        .destination("primary", status: "review_required", orders: [order])
        .build()

    try #require(source.headline == "You entered the trade", "headline was \(source.headline)")
    // The owner closed the call from Needs You, so the app counts it as skipped too.
    for skipped in [false, true] {
        let outcome = ActivityCardOutcome(source, skipped: skipped, now: try Date("2026-10-05T14:33:00Z", strategy: .iso8601))
        try #require(outcome.title == "Traded", "badge was \(outcome.title)")
        let account = try #require(outcome.accounts.first)
        try #require(!account.waits, "the account still waited for the owner")
        try #require(
            account.results.map(\.headline) == ["You bought $148.52 of NVDA"],
            "results were \(account.results.map(\.headline))")
        let row = GuruAccountOutcome.outcomes(of: source, skipped: skipped).map(\.summary)
        try #require(row == ["You bought $148.52 of NVDA"], "the row read \(row)")
    }
    let destination = try #require(source.destinations.first)
    try #require(
        DestinationOutcome(destination) == .filled("You bought $148.52 of NVDA"),
        "summary was \(DestinationOutcome(destination))")
}

@MainActor
private func aSkipNamesTheLimitWithItsNumbers() throws {
    let source = try soun()
        .destination(
            "zhao-paper", status: "done", outcomes: ["symbol_exposure_cap"],
            limits: [["part": 0, "scope": "symbol", "current": "1999.50", "proposed": "333.33", "limit": "2000"]]
        )
        .build()

    let outcome = ActivityCardOutcome(source, skipped: false)

    try #require(outcome.title == "Skipped", "badge was \(outcome.title)")
    // A cap cuts a buy to the room left; it skips one only when less than Alpaca's $1 minimum is left.
    try #require(
        outcome.accounts.first?.results
            == [
                .init(
                    headline: "Not bought: SOUN is at your limit for one stock",
                    facts: [
                        .init(label: "Holding SOUN", value: "$1,999.50"), .init(label: "Limit", value: "$2,000"),
                        .init(label: "Room left", value: "$0.50"),
                    ],
                    note: "Less than $1 is left, Alpaca's smallest order.")
            ], "results were \(outcome.accounts.first?.results ?? [])")
}

/// A sixth of SOUN with $1,900 of a $2,000 per-stock limit held: it buys the $100 left, not nothing,
/// and says which limit cut it (ADR-0010).
@MainActor
private func aBuyCutToTheRoomLeftNamesTheLimitThatCutIt() throws {
    let source = try soun()
        .destination(
            "zhao-paper", status: "done", outcomes: ["order_linked"],
            orders: [
                [
                    "client_id": "c1", "symbol": "SOUN", "side": "buy", "status": "filled", "quantity": "17",
                    "filled_quantity": "17", "limit_price": "5.85", "average_fill_price": "5.85", "broker_id": "b1",
                    "created_at": "2026-10-05T14:30:01Z", "instruction_index": 0, "requested_usd": "333.33",
                    "budget_usd": "100", "limited_by": "symbol_exposure_cap",
                ]
            ]
        )
        .build()

    let result = try #require(ActivityCardOutcome(source, skipped: false).accounts.first?.results.first)

    try #require(
        result.facts.contains(.init(label: "Order", value: "$100 · the room left under your SOUN limit")),
        "facts were \(result.facts)")
    try #require(result.facts.contains(.init(label: "The call asked for", value: "$333.33")), "facts were \(result.facts)")
}

/// Zhao's "soxl 日内撤" read two hours late, after the stock fell: it still goes out, at its floor
/// under the guru's price, and waits there for the market (ADR-0010).
@MainActor
private func aSellReadLateWaitsAtItsFloorUnderTheGurusPrice() throws {
    let source = try SourceActivityBuilder()
        .decision("trade", reason: "Sold")
        .posted(at: "2026-10-05T14:30:00Z")
        .calls([
            [
                "action": "close", "symbol": "SOXL", "price": "92.30", "entry_price": NSNull(), "fraction": "1",
                "exit_basis": NSNull(),
            ]
        ])
        .destination(
            "zhap-account-2", status: "done", outcomes: ["order_linked"],
            orders: [
                [
                    "client_id": "s1", "symbol": "SOXL", "side": "sell", "status": "new", "quantity": "2.779841",
                    "filled_quantity": "0", "limit_price": "91.38", "average_fill_price": NSNull(),
                    "broker_id": "b1", "created_at": "2026-10-05T16:30:00Z", "instruction_index": 0,
                    "source_price": "92.30", "entry_tolerance_pct": "1", "quote_bid": "86.10", "quote_ask": "86.12",
                ]
            ]
        )
        .build()

    let result = try #require(ActivityCardOutcome(source, skipped: false).accounts.first?.results.first)

    try #require(
        result.note
            == "Read 120 min after the guru posted it. A sell is always copied, at no less than your lowest price.",
        "note was \(String(describing: result.note))")
    try #require(
        result.facts.contains(.init(label: "Lowest sell price", value: "$91.38 (1% under the guru's $92.30)")),
        "facts were \(result.facts)")
    try #require(result.facts.contains(.init(label: "Market", value: "$86.10, under it")), "facts were \(result.facts)")
}

/// The SOXS sell of Oct 23: a floor of $53.66 under the guru's $54.20 and a bid of $53.85. The market
/// was above the floor, so nothing about it reads as over a limit, and the ruler marks no miss.
@MainActor
private func aSellCancelledWithTheMarketAboveItsFloorNeverReadsAsOverALimit() throws {
    let source = try SourceActivityBuilder()
        .decision("trade", reason: "Sold")
        .posted(at: "2026-10-23T13:30:27Z")
        .calls([
            [
                "action": "reduce", "symbol": "SOXS", "price": "54.20", "entry_price": "53.50", "fraction": "0.5",
                "exit_basis": "original_position",
            ]
        ])
        .destination(
            "zhap-account-2", status: "done", outcomes: ["order_linked"],
            orders: [
                [
                    "client_id": "s1", "symbol": "SOXS", "side": "sell", "status": "canceled", "quantity": "1.542291",
                    "filled_quantity": "0", "limit_price": "53.66", "average_fill_price": NSNull(),
                    "broker_id": "b1", "created_at": "2026-10-23T13:30:29Z", "instruction_index": 0,
                    "source_price": "54.20", "entry_tolerance_pct": "1", "quote_bid": "53.85", "quote_ask": "53.96",
                    "cancel_reason": "timeout", "submitted_at": "2026-10-23T13:30:29Z",
                    "ended_at": "2026-10-23T13:31:49Z",
                ]
            ]
        )
        .build()

    let result = try #require(ActivityCardOutcome(source, skipped: false).accounts.first?.results.first)

    try #require(result.headline == "Not sold: not filled in time", "headline was \(result.headline)")
    let prices = try #require(result.prices)
    try #require(!prices.buying && prices.market > prices.limit, "prices were \(prices)")
    try #require(
        result.facts.first == .init(label: "Guru's price", value: "$54.20 − 1% allowed"), "facts were \(result.facts)")
    try #require(!result.facts.contains { $0.value.contains("over your limit") }, "facts were \(result.facts)")
}

/// A sell still at its floor when the trading day ended: Alpaca expired it, and the card says the
/// market never came up to the floor.
@MainActor
private func aSellNotFilledByTheCloseSaysTheMarketStayedUnderItsFloor() throws {
    let source = try SourceActivityBuilder()
        .decision("trade", reason: "Sold")
        .posted(at: "2026-10-23T19:30:00Z")
        .calls([
            [
                "action": "close", "symbol": "F", "price": "12.00", "entry_price": NSNull(), "fraction": "1",
                "exit_basis": NSNull(),
            ]
        ])
        .destination(
            "zhap-account-2", status: "done", outcomes: ["order_linked"],
            orders: [
                [
                    "client_id": "s1", "symbol": "F", "side": "sell", "status": "expired", "quantity": "7",
                    "filled_quantity": "0", "limit_price": "11.88", "average_fill_price": NSNull(),
                    "broker_id": "b1", "created_at": "2026-10-23T19:30:02Z", "instruction_index": 0,
                    "source_price": "12.00", "entry_tolerance_pct": "1", "quote_bid": "11.60", "quote_ask": "11.61",
                    "cancel_reason": "expired", "ended_at": "2026-10-23T20:00:00Z",
                ]
            ]
        )
        .build()

    let result = try #require(ActivityCardOutcome(source, skipped: false).accounts.first?.results.first)

    try #require(
        result.headline == "Not sold by the close: the market stayed under your lowest price $11.88",
        "headline was \(result.headline)")
}

/// Zhao sold SOXL on Monday while copying was stopped and bought again on Wednesday: Monday's sell,
/// read back afterwards, leaves Wednesday's shares and says why, with both times.
@MainActor
private func aSellOlderThanEveryBuyHeldSaysWhenEachWasPosted() throws {
    let source = try SourceActivityBuilder()
        .decision("trade", reason: "Sold")
        .posted(at: "2026-10-05T17:02:00Z")
        .calls([
            [
                "action": "close", "symbol": "SOXL", "price": "92.30", "entry_price": NSNull(), "fraction": "1",
                "exit_basis": NSNull(),
            ]
        ])
        .destination(
            "zhap-account-2", status: "done", outcomes: ["bought_after_sell"],
            laterBuys: [["part": 0, "bought_at": "2026-10-07T16:41:00Z"]]
        )
        .build()

    let result = try #require(ActivityCardOutcome(source, skipped: false).accounts.first?.results.first)

    try #require(
        result.headline.hasPrefix("Not sold: zhap-account-2's SOXL was bought after this sell was posted ("),
        "headline was \(result.headline)")
    try #require(result.headline.contains("Wed") && result.headline.contains("Mon"), "headline was \(result.headline)")
}

/// A sell at the market read while Alpaca has no fresh bid: it keeps working, and says what for.
@MainActor
private func aSellWithNoBidYetSaysItWaitsForAPrice() throws {
    let source = try SourceActivityBuilder()
        .decision("trade", reason: "Sold")
        .calls([
            [
                "action": "close", "symbol": "SOXL", "price": NSNull(), "entry_price": NSNull(), "fraction": "1",
                "exit_basis": NSNull(),
            ]
        ])
        .destination("zhap-account-2", status: "queued", outcomes: ["waiting_for_quote"])
        .build()

    let card = ActivityCardOutcome(source, skipped: false)
    let result = try #require(card.accounts.first?.results.first)

    try #require(result.headline == "Waiting for a price to sell at", "headline was \(result.headline)")
    try #require(card.title != "Skipped", "title was \(card.title)")
}

/// A buy read 14 minutes after it was posted, past the account's signal age: it says how late.
@MainActor
private func aPostOfBuysReadTooLateSaysHowLate() throws {
    let late = try soun()
        .posted(at: "2026-10-05T14:30:00Z").captured(at: "2026-10-05T14:44:00Z")
        .destination("zhao-paper", status: "stale", outcomes: ["pending"])
        .build()

    let result = try #require(ActivityCardOutcome(late, skipped: false).accounts.first?.results.first)

    try #require(result.headline == "Not copied", "headline was \(result.headline)")
    try #require(
        result.note == "Read 14 min after it was posted: older than this account copies buys. A sell is always copied.",
        "note was \(String(describing: result.note))")
}

@MainActor
private func aCallHeldForApprovalAsksToBeApproved() throws {
    let source = try soun().destination("zhao-paper", status: "done", outcomes: ["approval_required"]).build()
    let sameDay = try Date("2026-10-05T15:00:00Z", strategy: .iso8601)
    let nextDay = try Date("2026-10-06T15:00:00Z", strategy: .iso8601)

    let open = ActivityCardOutcome(source, skipped: false, now: sameDay, zone: losAngeles, locale: english)
    let late = ActivityCardOutcome(source, skipped: false, now: nextDay)

    try #require(open.title == "Waiting for you", "badge was \(open.title)")
    let waiting = try #require(open.accounts.first?.results.first)
    try #require(waiting.headline == "Waiting for your approval", "headline was \(waiting.headline)")
    try #require(
        waiting.facts.map { [$0.label, plain($0.value)] } == [["Approve by", "5:00 PM PT today"]],
        "facts were \(waiting.facts)")
    try #require(open.accounts.first?.waits == true, "the account did not wait")
    try #require(
        late.accounts.first?.results.first?.headline == "Not sent",
        "an expired approval read \(late.accounts.first?.results.first?.headline ?? "nil")")
}

/// A post held for review without a reason code reads "Waiting for you" and its deadline, and no
/// note: there is nothing to explain, so no lone "—." sits under the deadline.
@MainActor
private func aCallWaitingWithNoReasonHasNoNote() throws {
    let source = try SourceActivityBuilder().decision("review")
        .suggested([SourceActivityBuilder.buy("SOUN", "5.85")])
        .destination("zhao-paper", status: "review_required", outcomes: ["review_required"])
        .build()
    let sameDay = try Date("2026-10-05T15:00:00Z", strategy: .iso8601)

    let outcome = ActivityCardOutcome(source, skipped: false, now: sameDay, zone: losAngeles, locale: english)

    let waiting = try #require(outcome.accounts.first?.results.first)
    try #require(waiting.headline == "Waiting for you", "headline was \(waiting.headline)")
    try #require(waiting.note == nil, "note was \(waiting.note ?? "nil")")
}

@MainActor
private func aBuyHeldForAResumeAsksToResumeByItsDeadline() throws {
    // Posted 14:30:00Z; entries wait for the owner's Resume after a restart.
    let source = try soun().destination("zhao-paper", status: "pending", outcomes: ["pending"]).build()
    let resume = ResumeWait(source, waiting: ["zhao-paper"], signalAge: { _ in 120 })
    let posted = try Date("2026-10-05T14:30:00Z", strategy: .iso8601)

    try #require(
        resume.deadlines["zhao-paper"] == posted.addingTimeInterval(120),
        "deadline was \(String(describing: resume.deadlines["zhao-paper"]))")
    let waiting = ActivityCardOutcome(source, skipped: false, resume: resume, now: posted.addingTimeInterval(30))
    try #require(waiting.title == "Waiting for you", "badge was \(waiting.title)")
    let account = try #require(waiting.accounts.first)
    try #require(account.awaitsResume, "the account did not ask for a resume")
    let result = try #require(account.results.first)
    try #require(result.headline == "Waiting for Start Copying", "headline was \(result.headline)")
    try #require(result.facts.first?.label == "Start by", "facts were \(result.facts)")
    let late = ActivityCardOutcome(source, skipped: false, resume: resume, now: posted.addingTimeInterval(300))
    try #require(
        late.accounts.first?.results.first?.note?.hasPrefix("Start Copying now") == true,
        "a late resume read \(late.accounts.first?.results.first?.note ?? "nil")")

    // Without a waiting account, or once an order went out, nothing asks for a resume.
    let ready = ActivityCardOutcome(
        source, skipped: false, resume: ResumeWait(source, waiting: [], signalAge: { _ in 120 }))
    try #require(ready.accounts.first?.awaitsResume == false, "a ready account asked for a resume")
    try #require(
        ready.accounts.first?.results.first?.headline == "Waiting to be sized and sent",
        "a ready account read \(ready.accounts.first?.results.first?.headline ?? "nil")")
    let skippedBuy = try soun().destination("zhao-paper", status: "done", outcomes: ["stale_waiting_for_resume"]).build()
    try #require(
        ResumeWait(skippedBuy, waiting: ["zhao-paper"], signalAge: { _ in 120 }).deadlines.isEmpty,
        "a buy already skipped as too old still asked for a resume")
}

/// Settings' time zone is the one every time is shown in: switching it moves a deadline.
@MainActor
private func theTimeZoneSettingMovesADeadline() throws {
    let preference = AppTimeZonePreference.shared
    let before = preference.chosen
    defer { preference.select(before) }
    let deadline = WaitingCall.endOfTradingDay(of: try Date("2026-10-05T15:00:00Z", strategy: .iso8601))
    let morning = try Date("2026-10-05T15:00:00Z", strategy: .iso8601)

    preference.select(AppTimeZonePreference.newYork)
    let newYork = plain(TradingDeadlineText.text(deadline, now: morning, locale: english))
    try #require(newYork == "8:00 PM ET today", "in New York the deadline read \(newYork ?? "nil")")

    preference.select("America/Los_Angeles")
    let losAngelesText = plain(TradingDeadlineText.text(deadline, now: morning, locale: english))
    try #require(losAngelesText == "5:00 PM PT today", "in Los Angeles the deadline read \(losAngelesText ?? "nil")")
    try #require(!preference.isAutomatic, "a chosen zone still read as automatic")

    preference.select(nil)
    try #require(preference.isAutomatic && preference.zone == .autoupdatingCurrent, "Automatic did not follow the Mac")
}
