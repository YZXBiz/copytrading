import Foundation

/// When a waiting call can still be copied, in the app's time zone, short name included:
/// "5:00 PM PT today", "5:00 PM PT tomorrow", or "Fri 5:00 PM PT" further out.
enum TradingDeadlineText {
    @MainActor
    static func text(_ deadline: Date, now: Date, zone: TimeZone? = nil, locale: Locale? = nil) -> String {
        let zone = zone ?? AppTime.zone
        let locale = locale ?? AppTime.locale
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let clock = deadline.formatted(
            Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar, timeZone: zone))
        let time = "\(clock) \(AppTime.shortName(zone, locale: locale))"
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
