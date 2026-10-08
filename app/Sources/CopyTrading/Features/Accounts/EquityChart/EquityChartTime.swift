import DesktopCore
import Foundation

/// Chart times read in exchange (New York) time, marked "ET", wherever the Mac is.
enum EquityChartTime {
    static let zone = MarketSession.timeZone

    /// When a recorded point was, at the precision its range records.
    @MainActor
    static func point(_ date: Date, in range: EquityHistoryRange) -> String {
        switch range {
        case .day:
            clock(date)
        case .week:
            "\(date.formatted(style(.dateTime.weekday(.abbreviated).month(.abbreviated).day()).locale(AppLanguagePreference.shared.language.locale))), \(clock(date))"
        case .month, .threeMonths, .year:
            date.formatted(
                style(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
                    .locale(AppLanguagePreference.shared.language.locale)
            )
        }
    }

    /// A time of day, e.g. "11:35 AM ET".
    @MainActor
    static func clock(_ date: Date) -> String {
        L10n.string(
            "%@ ET",
            date.formatted(style(.dateTime.hour().minute()).locale(AppLanguagePreference.shared.language.locale))
        )
    }

    /// How long a measured span lasted, e.g. "2 hr, 35 min" or "12 days".
    static func duration(_ seconds: TimeInterval, locale: Locale = .current) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 2 * 86_400 ? [.day] : [.hour, .minute]
        formatter.unitsStyle = .short
        var calendar = Calendar.current
        calendar.locale = locale
        formatter.calendar = calendar
        return formatter.string(from: seconds) ?? ""
    }

    private static func style(_ format: Date.FormatStyle) -> Date.FormatStyle {
        var format = format
        format.timeZone = zone
        return format
    }
}
