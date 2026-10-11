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

    /// Time labels spaced for the range: the opening bell and each hour of regular trading on a day,
    /// so a morning drawn across the whole width still reads, then days or months.
    var ticks: [Tick] {
        if isDay {
            var style = Date.FormatStyle.dateTime.hour().minute()
            style.timeZone = Self.calendar.timeZone
            let hours = (10...15).map { hour in
                let date = Self.calendar.date(byAdding: .hour, value: hour, to: Self.calendar.startOfDay(for: open)) ?? open
                return Tick(x: x(date), label: Self.hourLabel(date))
            }
            return [Tick(x: x(open), label: open.formatted(style))] + hours
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
        var style = format
        style.timeZone = Self.calendar.timeZone
        var ticks: [Tick] = []
        var date = Self.calendar.startOfDay(for: start)
        if unit == .month, let month = Self.calendar.dateInterval(of: .month, for: start)?.start { date = month }
        while date <= end {
            if date >= start { ticks.append(Tick(x: x(date), label: date.formatted(style))) }
            guard let next = Self.calendar.date(byAdding: unit, value: step, to: date) else { break }
            date = next
        }
        return ticks
    }

    /// An hour as the reader's clock writes it: "10 AM" with AM and PM, "10:00" on a 24-hour clock.
    static func hourLabel(_ date: Date) -> String {
        let hour = calendar.component(.hour, from: date)
        let template = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? "h a"
        guard template.contains("a") else { return "\(hour):00" }
        let twelve = hour % 12 == 0 ? 12 : hour % 12
        return "\(twelve) \(hour < 12 ? Calendar.current.amSymbol : Calendar.current.pmSymbol)"
    }

    /// Exchange time, so hour marks fall on New York hours wherever the Mac is.
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = EquityChartTime.zone
        return calendar
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
