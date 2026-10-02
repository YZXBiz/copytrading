import DesktopCore
import Foundation

func runEquityCurveTests() throws {
    try combinedCurveSumsOnlySharedTimes()
    try segmentsSplitExactlyAtTheReference()
    try statsFindExtremesAndTheWorstFall()
    try measureOrdersThePickedPoints()
    try accountChangeIsAFractionOfItsOwnReference()
    try sessionsFollowExchangeTime()
    try daysBeforeTheAccountExistedAreNotLosses()
    try theCurveEndsAtTheLiveBalance()
}

private func history(_ range: EquityHistoryRange, base: String?, _ points: [(String, String)]) throws -> EquityHistory {
    let json: [String: Any] = [
        "window": ["range": range.rawValue, "day": NSNull()],
        "base_value": base ?? NSNull(),
        "points": points.map { ["at": $0.0, "equity": $0.1] },
    ]
    return try JSONDecoder().decode(EquityHistory.self, from: JSONSerialization.data(withJSONObject: json))
}

private func at(_ iso: String) -> Date { try! Date(iso, strategy: .iso8601) }

private func combinedCurveSumsOnlySharedTimes() throws {
    let first = try history(
        .day, base: "100.00",
        [
            ("2026-09-28T13:30:00Z", "100.00"), ("2026-09-28T13:35:00Z", "101.50"), ("2026-09-28T13:40:00Z", "99.00"),
        ])
    let second = try history(
        .day, base: "50.00",
        [
            ("2026-09-28T13:30:00Z", "50.00"), ("2026-09-28T13:40:00Z", "52.00"),
        ])
    let curve = EquityCurve(combining: [first, second])
    try verify(curve.points.map(\.value) == [150, 151], "a time one account lacks must not read as a drop")
    try verify(curve.baseline == 150, "a day's baseline is the accounts' previous closes combined")

    let missingBase = try history(.day, base: nil, [("2026-09-28T13:30:00Z", "10.00")])
    try verify(
        EquityCurve(combining: [first, missingBase]).baseline == nil,
        "a baseline missing from one account must not be guessed")
    let month = try history(.month, base: "100.00", [("2026-09-28T13:30:00Z", "100.00")])
    try verify(EquityCurve(combining: [month]).baseline == nil, "only a day has a previous close to compare with")
    try verify(EquityCurve(combining: []).points.isEmpty, "no accounts means no curve")
}

private func segmentsSplitExactlyAtTheReference() throws {
    let curve = EquityCurve(
        points: [
            EquityCurvePoint(at: at("2026-09-28T13:30:00Z"), value: 108),
            EquityCurvePoint(at: at("2026-09-28T13:42:00Z"), value: 96),
            EquityCurvePoint(at: at("2026-09-28T13:50:00Z"), value: 98),
        ], baseline: 100)
    let segments = curve.segments(around: 100)
    try verify(segments.map(\.gain) == [true, false], "the curve changes side once")
    // 108 to 96 meets 100 two thirds of the way through the 12 minutes: at 13:38.
    let crossing = at("2026-09-28T13:38:00Z")
    try verify(
        segments[0].points.last == EquityCurvePoint(at: crossing, value: 100),
        "the gain segment must end where the line meets the reference")
    try verify(segments[1].points.first == segments[0].points.last, "adjacent segments must join without a gap")
    try verify(segments[1].points.count == 3, "the loss segment keeps every later point")

    let flat = EquityCurve(points: [EquityCurvePoint(at: crossing, value: 100)], baseline: 100)
    try verify(
        flat.segments(around: 100) == [EquityCurveSegment(gain: true, points: flat.points)],
        "no change counts as not losing")
}

private func statsFindExtremesAndTheWorstFall() throws {
    let values: [Double] = [100, 120, 90, 110, 80, 95]
    let points = values.enumerated().map {
        EquityCurvePoint(at: at("2026-09-28T13:30:00Z").addingTimeInterval(Double($0.offset) * 60), value: $0.element)
    }
    let stats = try unwrap(EquityCurve(points: points, baseline: 98).stats)
    try verify(stats.high.value == 120 && stats.low.value == 80, "high and low are the curve's extremes")
    try verify(stats.maxDrawdown == 40, "the worst fall runs from the 120 high to the later 80 low")
    try verify(abs(stats.maxDrawdownFraction - 40.0 / 120.0) < 1e-12, "the fall is measured against its own high")
    try verify(stats.change == -3, "change is measured from the previous close when there is one")
    let firstBased = try unwrap(EquityCurve(points: points, baseline: nil).stats)
    try verify(firstBased.change == -5, "without a previous close, change is measured from the first point")

    let rising = EquityCurve(points: Array(points.prefix(2)), baseline: nil)
    try verify(rising.stats?.maxDrawdown == 0, "a curve that never fell has no drawdown")
    try verify(EquityCurve(points: [], baseline: nil).stats == nil, "an empty curve has no stats")
}

private func measureOrdersThePickedPoints() throws {
    let curve = EquityCurve(
        points: [
            EquityCurvePoint(at: at("2026-09-28T13:30:00Z"), value: 200),
            EquityCurvePoint(at: at("2026-09-28T13:40:00Z"), value: 210),
            EquityCurvePoint(at: at("2026-09-28T13:50:00Z"), value: 190),
        ], baseline: nil)
    let measure = try unwrap(curve.measure(from: at("2026-09-28T13:52:00Z"), to: at("2026-09-28T13:38:00Z")))
    try verify(measure.start.value == 210 && measure.end.value == 190, "a right-to-left drag still reads forward in time")
    try verify(measure.change == -20 && measure.duration == 600, "the measure reports change and elapsed time")
    try verify(
        curve.measure(from: at("2026-09-28T13:31:00Z"), to: at("2026-09-28T13:32:00Z")) == nil,
        "two picks on the same point measure nothing")
}

private func accountChangeIsAFractionOfItsOwnReference() throws {
    let day = try history(.day, base: "200.00", [("2026-09-28T13:30:00Z", "210.00"), ("2026-09-28T13:35:00Z", "190.00")])
    try verify(EquityCurve(changeOf: day).points.map(\.value) == [0.05, -0.05], "a day's change is against its previous close")
    let month = try history(.month, base: nil, [("2026-09-01T13:30:00Z", "50.00"), ("2026-09-02T13:30:00Z", "55.00")])
    try verify(EquityCurve(changeOf: month).points.map(\.value) == [0, 0.1], "a range's change is against its first point")
    try verify(EquityCurve(changeOf: month).baseline == 0, "change curves share a zero baseline")
}

private func sessionsFollowExchangeTime() throws {
    try verify(MarketSession.of(at("2026-09-28T13:29:00Z")) == .preMarket, "9:29 in New York is pre-market")
    try verify(MarketSession.of(at("2026-09-28T13:30:00Z")) == .regular, "9:30 in New York opens the regular session")
    try verify(MarketSession.of(at("2026-09-28T20:00:00Z")) == .afterHours, "16:00 in New York starts after hours")
    try verify(MarketSession.of(at("2026-09-29T00:00:00Z")) == nil, "20:00 in New York is closed")
    let day = MarketSession.tradingDay(containing: at("2026-09-28T15:00:00Z"))
    try verify(
        day.lowerBound == at("2026-09-28T08:00:00Z") && day.upperBound == at("2026-09-29T00:00:00Z"),
        "the trading day runs 4:00 to 20:00 New York time")
    try verify(
        MarketSession.regular.interval(on: at("2026-12-01T15:00:00Z")).lowerBound == at("2026-12-01T14:30:00Z"),
        "sessions follow daylight saving time")
}

private func unwrap<T>(_ value: T?) throws -> T {
    guard let value else { throw VerificationFailure(description: "expected a value") }
    return value
}

private func daysBeforeTheAccountExistedAreNotLosses() throws {
    // The broker reports zero equity for the days before an account was funded.
    let funded = try history(
        .year, base: nil,
        [
            ("2026-06-01T20:00:00Z", "0.00"), ("2026-06-02T20:00:00Z", "0.00"),
            ("2026-06-03T20:00:00Z", "10000.00"), ("2026-06-04T20:00:00Z", "9900.00"),
        ])
    let curve = EquityCurve(combining: [funded])
    try verify(
        curve.points.map(\.value) == [10_000, 9_900],
        "zero equity before the first funded day must not be plotted as a balance")
    try verify(curve.stats?.change == -100, "the change is measured from the first funded day, not from zero")
    try verify(curve.stats?.low.value == 9_900, "a day the account did not exist is not the low")

    let change = EquityCurve(changeOf: funded)
    try verify(change.points.map(\.value) == [0, -0.01], "an account's change starts on its first funded day")

    let empty = try history(.year, base: nil, [("2026-06-01T20:00:00Z", "0.00"), ("2026-06-02T20:00:00Z", "0.00")])
    try verify(EquityCurve(combining: [empty]).points.isEmpty, "an account that was never funded has no curve")
    try verify(EquityCurve(changeOf: empty).points.isEmpty, "an account that was never funded has no change curve")

    // A balance that later reaches zero is a real loss and stays.
    let wiped = try history(
        .month, base: nil,
        [
            ("2026-09-01T20:00:00Z", "500.00"), ("2026-09-02T20:00:00Z", "0.00"),
        ])
    try verify(EquityCurve(combining: [wiped]).points.map(\.value) == [500, 0], "zero after funding is kept")
}

private func balance(_ equity: String, observedAt: String) throws -> AccountBalance {
    let json: [String: Any] = [
        "equity": equity, "previous_close_equity": "100.00", "day_change_usd": "0.00",
        "cash": "0.00", "buying_power": "0.00", "observed_at": observedAt,
    ]
    return try JSONDecoder().decode(AccountBalance.self, from: JSONSerialization.data(withJSONObject: json))
}

private func liveValues(_ entries: [LiveEquity.AccountHistory]) -> [[String]] {
    entries.map { $0.history.points.map(\.equity) }
}

private func theCurveEndsAtTheLiveBalance() throws {
    let today = try history(
        .day, base: "100.00",
        [
            ("2026-09-30T19:10:00Z", "101.00"), ("2026-09-30T19:15:00Z", "102.00"),
        ])
    let live = try balance("104.50", observedAt: "2026-09-30T19:19:54.250000Z")
    let extended = LiveEquity.extend([("a", today)], balances: ["a": live])
    try verify(
        liveValues(extended) == [["101.00", "102.00", "104.50"]],
        "a day's curve must end at the balance read after its last five-minute bar")
    try verify(
        EquityCurve(combining: extended.map(\.history)).stats?.last.value == 104.5,
        "the chart's latest value must equal the balance")

    let stale = try balance("99.00", observedAt: "2026-09-30T19:15:00Z")
    try verify(
        liveValues(LiveEquity.extend([("a", today)], balances: ["a": stale])) == liveValues([("a", today)]),
        "a balance no newer than the last bar adds nothing")
    let unfunded = try balance("0", observedAt: "2026-09-30T19:19:00Z")
    try verify(
        liveValues(LiveEquity.extend([("a", today)], balances: ["a": unfunded])) == liveValues([("a", today)]),
        "an unfunded balance is not a point on the curve")

    let pastDay = try JSONDecoder().decode(
        EquityHistory.self,
        from: JSONSerialization.data(
            withJSONObject: [
                "window": ["range": "day", "day": "2026-09-29"], "base_value": "100.00",
                "points": [["at": "2026-09-29T19:15:00Z", "equity": "102.00"]],
            ] as [String: Any]))
    try verify(
        liveValues(LiveEquity.extend([("a", pastDay)], balances: ["a": live])) == liveValues([("a", pastDay)]),
        "a chosen past day never takes today's balance")

    let friday = try history(.day, base: "100.00", [("2026-09-25T19:10:00Z", "101.00"), ("2026-09-25T19:15:00Z", "102.00")])
    let saturday = try balance("102.00", observedAt: "2026-09-26T17:00:00Z")
    try verify(
        liveValues(LiveEquity.extend([("a", friday)], balances: ["a": saturday])) == liveValues([("a", friday)]),
        "a balance from another day must not land on the day the market last traded")
    let afterClose = try balance("102.00", observedAt: "2026-10-01T00:30:00Z")
    try verify(
        liveValues(LiveEquity.extend([("a", today)], balances: ["a": afterClose])) == liveValues([("a", today)]),
        "a balance after the extended session closes has no place on the day chart")

    let week = try history(.week, base: nil, [("2026-09-28T13:30:00Z", "100.00"), ("2026-09-29T20:00:00Z", "103.00")])
    try verify(
        liveValues(LiveEquity.extend([("a", week)], balances: ["a": live])) == [["100.00", "103.00", "104.50"]],
        "a range that ends now also ends at the balance")

    let second = try history(.day, base: "50.00", [("2026-09-30T19:10:00Z", "51.00"), ("2026-09-30T19:15:00Z", "51.50")])
    let earlier = try balance("52.00", observedAt: "2026-09-30T19:19:30Z")
    let pair = LiveEquity.extend([("a", today), ("b", second)], balances: ["a": live, "b": earlier])
    let combined = EquityCurve(combining: pair.map(\.history))
    try verify(
        combined.points.last?.value == 156.5 && combined.points.count == 3,
        "two accounts share the latest reading time, so the combined curve adds up at the end")

    let missing = LiveEquity.extend([("a", today), ("b", second)], balances: ["a": live])
    try verify(
        EquityCurve(combining: missing.map(\.history)).points.last?.value == 153.5,
        "without every balance the combined curve keeps its recorded end rather than guessing")
}
