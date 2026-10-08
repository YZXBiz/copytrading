import Foundation

/// When a waiting call can still be copied, on the owner's own clock: "5:00 PM today",
/// "5:00 PM tomorrow", or "Fri 5:00 PM" further out.
enum TradingDeadlineText {
    @MainActor
    static func text(_ deadline: Date, now: Date, zone: TimeZone = .current, locale: Locale = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let time = deadline.formatted(
            Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar, timeZone: zone))
        if calendar.isDate(deadline, inSameDayAs: now) {
            return L10n.string("%@ today", time)
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(deadline, inSameDayAs: tomorrow) {
            return L10n.string("%@ tomorrow", time)
        }
        let day = deadline.formatted(
            Date.FormatStyle(locale: locale, calendar: calendar, timeZone: zone).weekday(.abbreviated))
        return "\(day) \(time)"
    }
}
