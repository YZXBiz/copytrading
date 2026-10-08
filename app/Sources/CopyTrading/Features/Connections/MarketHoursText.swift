import Foundation

/// Market hours as the owner reads them: on their own clock first, then New York's, the
/// exchange's, in brackets; just New York's when their Mac keeps New York time.
enum MarketHoursText {
    private static let newYork = TimeZone(identifier: "America/New_York") ?? .gmt

    /// "1 AM–6:30 AM and 1 PM–5 PM your time (4 AM–9:30 AM and 4 PM–8 PM New York)", or
    /// "8 PM–4 AM New York time" on a Mac in New York.
    @MainActor
    static func hours(
        _ ranges: [(from: (Int, Int), to: (Int, Int))], now: Date = .now, zone: TimeZone = .current,
        locale: Locale = .current
    ) -> String {
        let inNewYork = L10n.list(ranges.map { span($0, now: now, zone: newYork, locale: locale) })
        guard zone.secondsFromGMT(for: now) != newYork.secondsFromGMT(for: now) else {
            return L10n.string("%@ New York time", inNewYork)
        }
        let local = L10n.list(ranges.map { span($0, now: now, zone: zone, locale: locale) })
        return L10n.string("%@ your time (%@ New York)", local, inNewYork)
    }

    private static func span(
        _ range: (from: (Int, Int), to: (Int, Int)), now: Date, zone: TimeZone, locale: Locale
    ) -> String {
        "\(clock(range.from, now: now, zone: zone, locale: locale))–\(clock(range.to, now: now, zone: zone, locale: locale))"
    }

    /// A New York time of day on the clock in `zone`: "5 PM", "9:30 AM", or "17:00" where the
    /// locale keeps a 24-hour clock.
    private static func clock(_ time: (Int, Int), now: Date, zone: TimeZone, locale: Locale) -> String {
        var exchange = Calendar(identifier: .gregorian)
        exchange.timeZone = newYork
        var parts = exchange.dateComponents([.year, .month, .day], from: now)
        parts.hour = time.0
        parts.minute = time.1
        let date = exchange.date(from: parts) ?? now
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: zone)
            .hour(.defaultDigits(amPM: .abbreviated))
        return calendar.component(.minute, from: date) == 0
            ? date.formatted(style) : date.formatted(style.minute(.twoDigits))
    }
}
