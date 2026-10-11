import DesktopCore
import Foundation

extension EquityHistoryWindow {
    /// Trading days are New York dates, whatever the Mac's time zone.
    private static let tradingCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        return calendar
    }()

    /// One chosen day; today reads as the latest session rather than a fixed date.
    static func day(_ date: Date) -> EquityHistoryWindow {
        let calendar = tradingCalendar
        if calendar.isDate(date, inSameDayAs: .now) { return .today }
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let text = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        return EquityHistoryWindow(range: .day, day: text)
    }

    /// The chosen day as a date, or now for the latest session.
    var chosenDay: Date {
        guard let day else { return .now }
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return .now }
        return Self.tradingCalendar.date(
            from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)
        ) ?? .now
    }

    @MainActor var title: String {
        switch range {
        case .day:
            day == nil
                ? L10n.string("Equity today")
                : L10n.string(
                    "Equity on %@",
                    chosenDay.formatted(
                        .dateTime.weekday(.abbreviated).month(.abbreviated).day()
                            .locale(AppLanguagePreference.shared.language.locale)
                    )
                )
        case .week: L10n.string("Equity this week")
        case .month: L10n.string("Equity this month")
        case .threeMonths: L10n.string("Equity over 3 months")
        case .year: L10n.string("Equity over the year")
        }
    }
}
