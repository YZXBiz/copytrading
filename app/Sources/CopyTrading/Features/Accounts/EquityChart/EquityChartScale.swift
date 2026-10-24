import DesktopCore
import Foundation

/// Where each moment sits across the plot, from 0 at the left edge to 1 at the right, linear in
/// time. A day spans its whole New York day, midnight to midnight, since coins trade around the
/// clock; longer ranges span their first point to their last.
struct EquityChartScale {
    /// A labeled position on the time axis.
    struct Tick: Hashable {
        let x: Double
        let label: String
    }

    let range: EquityHistoryRange
    private let start: Date
    private let end: Date

    /// - Parameters:
    ///   - first: the earliest time on the chart; for a day, any time on that New York day.
    ///   - last: the latest time on the chart; ignored for a day, which always spans the whole day.
    init(range: EquityHistoryRange, first: Date, last: Date) {
        self.range = range
        if range == .day {
            let day = NewYorkDay.containing(first)
            (start, end) = (day.lowerBound, day.upperBound)
        } else {
            (start, end) = (first, max(last, first.addingTimeInterval(1)))
        }
    }

    var isDay: Bool { range == .day }

    /// The position of `date`, clamped to the plot.
    func x(_ date: Date) -> Double {
        let span = end.timeIntervalSince(start)
        guard span > 0 else { return 0 }
        return min(1, max(0, date.timeIntervalSince(start) / span))
    }

    /// The moment at position `x`, the inverse of `x(_:)`.
    func date(atX x: Double) -> Date {
        start.addingTimeInterval(end.timeIntervalSince(start) * min(1, max(0, x)))
    }

    /// The steps a day's marks may take, in hours, finest first.
    static let dayStepsHours = [1, 2, 3, 4, 6]
    /// The least room between two time marks, in points, so labels never touch.
    static let minimumTickSpacing: Double = 90

    /// Time labels spaced for the range and the plot's width, in the zone and language the rest
    /// of the app reads in. A day marks round hours at the finest step that leaves room between
    /// labels; longer ranges mark days or months.
    @MainActor
    func ticks(in zone: TimeZone, locale: Locale, width: Double) -> [Tick] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        if isDay {
            var clock = Date.FormatStyle.dateTime.hour().locale(locale)
            clock.timeZone = zone
            let pointsPerHour = max(width, 1) / max(end.timeIntervalSince(start) / 3_600, 1)
            let step = Self.dayStepsHours.first { Double($0) * pointsPerHour >= Self.minimumTickSpacing } ?? 6
            var marks: [Tick] = []
            var mark = calendar.dateInterval(of: .hour, for: start)?.start ?? start
            if mark < start { mark = calendar.date(byAdding: .hour, value: 1, to: mark) ?? start }
            while mark <= end {
                if calendar.component(.hour, from: mark) % step == 0 {
                    marks.append(Tick(x: x(mark), label: mark.formatted(clock)))
                }
                guard let next = calendar.date(byAdding: .hour, value: 1, to: mark) else { break }
                mark = next
            }
            return marks
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
}
