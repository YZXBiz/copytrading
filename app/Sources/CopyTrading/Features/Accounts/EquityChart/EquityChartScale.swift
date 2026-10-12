import DesktopCore
import Foundation

/// Where each moment sits across the plot, from 0 at the left edge to 1 at the right.
///
/// A day keeps the whole extended session (4:00 to 20:00 exchange time) but gives regular hours
/// most of the width: pre-market and after hours are narrow strips at either side, so the hours
/// that move money read at a useful scale. Longer ranges are linear in time.
struct EquityChartScale {
    /// A labeled position on the time axis.
    struct Tick: Hashable {
        let x: Double
        let label: String
    }

    /// A stretch of a day outside regular hours, shaded on the plot with its name inside.
    struct Session: Hashable {
        let start: Double
        let end: Double
        let name: String
    }

    static let preMarketShare = 0.12
    static let afterHoursShare = 0.1

    let range: EquityHistoryRange
    private let start: Date
    private let end: Date
    private let open: Date
    private let close: Date

    /// - Parameters:
    ///   - first: the earliest time on the chart; for a day, any time on that trading day.
    ///   - last: the latest time on the chart; ignored for a day, which always spans its session.
    init(range: EquityHistoryRange, first: Date, last: Date) {
        self.range = range
        if range == .day {
            let day = MarketSession.tradingDay(containing: first)
            let regular = MarketSession.regular.interval(on: first)
            (start, end, open, close) = (day.lowerBound, day.upperBound, regular.lowerBound, regular.upperBound)
        } else {
            let last = max(last, first.addingTimeInterval(1))
            (start, end, open, close) = (first, last, first, last)
        }
    }

    var isDay: Bool { range == .day }
    /// Where regular hours begin and end on a day.
    var openX: Double { x(open) }
    var closeX: Double { x(close) }

    /// The position of `date`, clamped to the plot.
    func x(_ date: Date) -> Double {
        guard isDay else { return Self.fraction(of: date, from: start, to: end) }
        let pre = Self.preMarketShare
        let after = Self.afterHoursShare
        if date < open { return pre * Self.fraction(of: date, from: start, to: open) }
        if date <= close { return pre + (1 - pre - after) * Self.fraction(of: date, from: open, to: close) }
        return 1 - after + after * Self.fraction(of: date, from: close, to: end)
    }

    /// The moment at position `x`, the inverse of `x(_:)`.
    func date(atX x: Double) -> Date {
        let x = min(1, max(0, x))
        guard isDay else { return Self.interpolate(start, end, x) }
        let pre = Self.preMarketShare
        let after = Self.afterHoursShare
        if x < pre { return Self.interpolate(start, open, x / pre) }
        if x <= 1 - after { return Self.interpolate(open, close, (x - pre) / (1 - pre - after)) }
        return Self.interpolate(close, end, (x - (1 - after)) / after)
    }

    /// Whether `date` falls outside regular hours on a day.
    func isExtended(_ date: Date) -> Bool {
        isDay && (date < open || date > close)
    }

    /// The steps a day's marks may take, finest first.
    static let dayStepsMinutes = [15, 30, 60, 120]
    /// The least room between two time marks, in points, so labels never touch.
    static let minimumTickSpacing: Double = 90

    /// A day's pre-market and after-hours strips; none for longer ranges.
    @MainActor
    var extendedSessions: [Session] {
        guard isDay else { return [] }
        return [
            Session(start: 0, end: Self.preMarketShare, name: L10n.string("Pre-market")),
            Session(start: 1 - Self.afterHoursShare, end: 1, name: L10n.string("After hours")),
        ]
    }

    /// Time labels spaced for the range and the plot's width, in the zone and language the rest
    /// of the app reads in. A day marks the opening bell and the close and the finest round step
    /// that leaves room between labels (15, 30, or 60 minutes, then 2 hours), with AM or PM where
    /// the language uses them; longer ranges mark days or months.
    @MainActor
    func ticks(in zone: TimeZone, locale: Locale, width: Double) -> [Tick] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        var clock = Date.FormatStyle.dateTime.hour().minute().locale(locale)
        clock.timeZone = zone
        if isDay {
            let regularWidth = max(width, 1) * (1 - Self.preMarketShare - Self.afterHoursShare)
            let pointsPerMinute = regularWidth / max(close.timeIntervalSince(open) / 60, 1)
            let step = Self.dayStepsMinutes.first { Double($0) * pointsPerMinute >= Self.minimumTickSpacing } ?? 120
            let clear = Double(step) * 0.75 * 60
            var marks: [Tick] = []
            let startOfDay = calendar.startOfDay(for: open)
            var minutes = Int(open.timeIntervalSince(startOfDay) / 60) / step * step + step
            while let mark = calendar.date(byAdding: .minute, value: minutes, to: startOfDay), mark < close {
                if mark.timeIntervalSince(open) >= clear, close.timeIntervalSince(mark) >= clear {
                    marks.append(Tick(x: x(mark), label: mark.formatted(clock)))
                }
                minutes += step
            }
            return [Tick(x: x(open), label: open.formatted(clock))] + marks
                + [Tick(x: x(close), label: close.formatted(clock))]
        }
        let span = end.timeIntervalSince(start)
        let (unit, step, format): (Calendar.Component, Int, Date.FormatStyle) =
            switch range {
            case .day, .week: (.day, 1, .dateTime.weekday(.abbreviated).day())
            case .month: (.day, 7, .dateTime.month(.abbreviated).day())
            case .threeMonths, .year:
                span <= 75 * 86_400
                    ? (.day, 14, .dateTime.month(.abbreviated).day())
                    : (.month, span > 200 * 86_400 ? 2 : 1, .dateTime.month(.abbreviated))
            }
        var style = format.locale(locale)
        style.timeZone = zone
        var ticks: [Tick] = []
        var date = calendar.startOfDay(for: start)
        if unit == .month, let month = calendar.dateInterval(of: .month, for: start)?.start { date = month }
        while date <= end {
            if date >= start { ticks.append(Tick(x: x(date), label: date.formatted(style))) }
            guard let next = calendar.date(byAdding: unit, value: step, to: date) else { break }
            date = next
        }
        return ticks
    }

    private static func fraction(of date: Date, from lower: Date, to upper: Date) -> Double {
        let span = upper.timeIntervalSince(lower)
        guard span > 0 else { return 0 }
        return min(1, max(0, date.timeIntervalSince(lower) / span))
    }

    private static func interpolate(_ lower: Date, _ upper: Date, _ fraction: Double) -> Date {
        lower.addingTimeInterval(upper.timeIntervalSince(lower) * min(1, max(0, fraction)))
    }
}
