import DesktopCore
import Foundation

@MainActor
func runEquityChartScaleTests() throws {
    try dayGivesRegularHoursTheRoom()
    try positionsTurnBackIntoTimes()
    try longerRangesAreLinear()
    try runsDimOnlyOutsideRegularHours()
    print("CopyTradingContractTests: the chart gives regular hours the room, maps positions back to times, and dims extended hours")
}

private var newYork: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = MarketSession.timeZone
    return calendar
}

private func exchangeTime(_ hour: Int, _ minute: Int) -> Date {
    let day = newYork.date(from: DateComponents(year: 2026, month: 10, day: 1)) ?? .now
    return newYork.date(byAdding: .minute, value: hour * 60 + minute, to: day) ?? day
}

@MainActor
private func dayGivesRegularHoursTheRoom() throws {
    let scale = EquityChartScale(range: .day, first: exchangeTime(9, 45), last: exchangeTime(10, 30))
    try verifyScale(abs(scale.x(exchangeTime(4, 0))) < 1e-9, "4:00 is not the left edge")
    try verifyScale(abs(scale.x(exchangeTime(20, 0)) - 1) < 1e-9, "20:00 is not the right edge")
    try verifyScale(abs(scale.openX - EquityChartScale.preMarketShare) < 1e-9, "the open does not follow the pre-market strip")
    try verifyScale(abs(scale.closeX - (1 - EquityChartScale.afterHoursShare)) < 1e-9, "the close does not precede after hours")
    let regularWidth = scale.closeX - scale.openX
    try verifyScale(regularWidth > 0.75, "regular hours got only \(regularWidth) of the width")
    try verifyScale(
        abs(scale.x(exchangeTime(12, 45)) - (scale.openX + regularWidth / 2)) < 1e-9,
        "the middle of regular hours is not the middle of their span")
    try verifyScale(scale.isExtended(exchangeTime(8, 0)) && scale.isExtended(exchangeTime(17, 0)), "extended hours not recognized")
    try verifyScale(!scale.isExtended(exchangeTime(9, 30)) && !scale.isExtended(exchangeTime(16, 0)), "the open or close read as extended")
    try verifyScale(scale.ticks.map(\.x).allSatisfy { $0 >= scale.openX && $0 < scale.closeX }, "a day tick fell outside regular hours")
    try verifyScale(scale.ticks.first?.x == scale.openX, "a day's labels did not start at the opening bell")
}

@MainActor
private func positionsTurnBackIntoTimes() throws {
    let scale = EquityChartScale(range: .day, first: exchangeTime(9, 45), last: exchangeTime(10, 30))
    for (hour, minute) in [(4, 30), (9, 29), (9, 31), (12, 0), (15, 59), (16, 1), (19, 30)] {
        let date = exchangeTime(hour, minute)
        let back = scale.date(atX: scale.x(date))
        try verifyScale(abs(back.timeIntervalSince(date)) < 1, "\(hour):\(minute) did not survive the round trip")
    }
}

@MainActor
private func longerRangesAreLinear() throws {
    let first = exchangeTime(9, 30)
    let last = first.addingTimeInterval(7 * 86_400)
    let scale = EquityChartScale(range: .week, first: first, last: last)
    try verifyScale(abs(scale.x(first.addingTimeInterval(3.5 * 86_400)) - 0.5) < 1e-9, "a week is not linear in time")
    try verifyScale(!scale.isExtended(first.addingTimeInterval(-3_600 * 3)), "a week dimmed extended hours")
    try verifyScale(!scale.ticks.isEmpty, "a week has no time labels")
}

@MainActor
private func runsDimOnlyOutsideRegularHours() throws {
    let scale = EquityChartScale(range: .day, first: exchangeTime(9, 0), last: exchangeTime(17, 0))
    let points = [(9, 0), (9, 25), (9, 35), (12, 0), (16, 5), (17, 0)].map {
        EquityCurvePoint(at: exchangeTime($0.0, $0.1), value: 100)
    }
    let runs = EquityLineRun.runs(points, on: scale)
    try verifyScale(runs.map(\.isExtended) == [true, false, true], "runs did not follow the sessions")
    try verifyScale(
        zip(runs, runs.dropFirst()).allSatisfy { $0.points.last == $1.points.first }, "adjacent runs do not share their joint")
}

private func verifyScale(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else {
        throw NSError(domain: "EquityChartScaleTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
