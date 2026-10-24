import DesktopCore
import Foundation

@MainActor
func runEquityChartScaleTests() throws {
    try aDaySpansMidnightToMidnight()
    try positionsTurnBackIntoTimes()
    try longerRangesAreLinear()
    try theValueAxisNeverReadsMinusZero()
    print("CopyTradingContractTests: a day runs midnight to midnight, positions map back to times, and longer ranges are linear")
}

private var newYork: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = NewYorkDay.timeZone
    return calendar
}

private func exchangeTime(_ hour: Int, _ minute: Int) -> Date {
    let day = newYork.date(from: DateComponents(year: 2026, month: 10, day: 1)) ?? .now
    return newYork.date(byAdding: .minute, value: hour * 60 + minute, to: day) ?? day
}

/// A coin call at 12:45 AM sits on the day's chart, and noon is its middle.
@MainActor
private func aDaySpansMidnightToMidnight() throws {
    let scale = EquityChartScale(range: .day, first: exchangeTime(0, 15), last: exchangeTime(10, 30))
    try verifyScale(abs(scale.x(exchangeTime(0, 0))) < 1e-9, "midnight is not the left edge")
    try verifyScale(abs(scale.x(exchangeTime(24, 0)) - 1) < 1e-9, "the next midnight is not the right edge")
    try verifyScale(abs(scale.x(exchangeTime(12, 0)) - 0.5) < 1e-9, "noon is not the middle of the day")
    try verifyScale(scale.x(exchangeTime(0, 45)) > 0, "a 12:45 AM call is pinned to the edge")
    let ticks = scale.ticks(in: NewYorkDay.timeZone, locale: Locale(identifier: "en_US"), width: 900)
    try verifyScale(ticks.count >= 4, "a wide day has only \(ticks.count) time labels")
    try verifyScale(
        zip(ticks, ticks.dropFirst()).allSatisfy { ($1.x - $0.x) * 900 >= EquityChartScale.minimumTickSpacing - 1e-6 },
        "two day labels are closer than \(EquityChartScale.minimumTickSpacing) points")
    // The formatter puts a narrow space before AM.
    let first = ticks.first?.label.replacingOccurrences(of: "\u{202F}", with: " ")
    try verifyScale(first == "12 AM", "the day's first label read \(first ?? "nothing")")
}

@MainActor
private func positionsTurnBackIntoTimes() throws {
    let scale = EquityChartScale(range: .day, first: exchangeTime(9, 45), last: exchangeTime(10, 30))
    for (hour, minute) in [(0, 30), (4, 30), (9, 29), (12, 0), (16, 1), (23, 30)] {
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
    try verifyScale(!scale.ticks(in: .current, locale: .current, width: 900).isEmpty, "a week has no time labels")
}

/// A range that starts just below zero puts a tick at zero, and it reads "$0", never "-$0".
@MainActor
private func theValueAxisNeverReadsMinusZero() throws {
    let axis = EquityValueAxis(lower: -50_000, upper: 1_300_000)
    let labels = axis.ticks.map(axis.money)
    try verifyScale(labels.contains("$0"), "no $0 tick in \(labels)")
    try verifyScale(!labels.contains { $0.hasPrefix("-") }, "a tick read \(labels)")
}

private func verifyScale(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else {
        throw NSError(domain: "EquityChartScaleTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
