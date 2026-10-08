import SwiftUI

/// A day's heading in a guru's feed: TODAY, YESTERDAY, or the date, small and spaced.
struct GuruFeedDayLabel: View {
    let start: Date

    private var title: String {
        let calendar = AppTime.calendar
        if calendar.isDateInToday(start) { return L10n.string("Today") }
        if calendar.isDateInYesterday(start) { return L10n.string("Yesterday") }
        return start.formatted(AppTime.style(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
    }

    var body: some View {
        Text(title)
            .font(DesignTokens.activitySection)
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(Palette.tertiaryInk)
            .accessibilityAddTraits(.isHeader)
    }
}
