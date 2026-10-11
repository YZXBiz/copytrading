import SwiftUI

/// A day's start on the timeline: a solid ink stop on the rail, then the day in the display face
/// ("Today") with its date beside it in quiet type ("Thu, Oct 9"), so a new day reads at a glance
/// before its posts.
struct TimelineDayRow: View {
    let title: String
    var date: String?
    let runsAbove: Bool
    var top: CGFloat = 0

    var body: some View {
        TimelineRow(mark: .day, runsAbove: runsAbove, runsBelow: true, isWide: true, trailingWidth: 0, top: top, bottom: 6) {
            // Holds the time column's width, so the day's stop sits on the same rail as the posts.
            Color.clear.frame(height: 1)
        } content: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title)
                    .font(DesignTokens.cardTitle)
                    .tracking(DesignTokens.listHeadingTracking)
                    .foregroundStyle(Palette.ink)
                if let date {
                    Text(date)
                        .font(DesignTokens.caption)
                        .foregroundStyle(Palette.tertiaryInk)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
        } trailing: {
            EmptyView()
        }
    }
}
