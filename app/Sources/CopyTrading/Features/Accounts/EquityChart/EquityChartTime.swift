import DesktopCore
import Foundation

/// Chart times in the zone and language the rest of the app reads in (the Mac's own by default).
@MainActor
enum EquityChartTime {
    /// When a recorded point was, at the precision its range records.
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

    /// A time of day, e.g. "8:35 AM".
    static func clock(_ date: Date) -> String {
        date.formatted(AppTime.style(.dateTime.hour().minute()))
    }

    /// How long a measured span lasted, e.g. "2 hr, 35 min" or "12 days".
    nonisolated static func duration(_ seconds: TimeInterval, locale: Locale = .current) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 2 * 86_400 ? [.day] : [.hour, .minute]
        formatter.unitsStyle = .short
        var calendar = Calendar.current
        calendar.locale = locale
        formatter.calendar = calendar
        return formatter.string(from: seconds) ?? ""
    }

    private static func style(_ format: Date.FormatStyle) -> Date.FormatStyle {
        AppTime.style(format)
    }
}
