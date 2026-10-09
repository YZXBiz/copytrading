import SwiftUI

/// Rows that read strictly top to bottom in time, newest first: each day's label in the gutter, then
/// its rows, joined by one ink rail from the first day down to the last row's dot.
struct TimelineFeed<Item: Identifiable, Row: View>: View {
    let days: [TimelineDay<Item>]
    @ViewBuilder let row: (Item, TimelinePlace) -> Row
    @State private var width: CGFloat = 0

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.element.id) { dayIndex, day in
                TimelineDayRow(title: day.title(), runsAbove: dayIndex > 0, top: dayIndex > 0 ? 30 : 0)
                ForEach(Array(day.items.enumerated()), id: \.element.id) { index, item in
                    let isLast = dayIndex == days.count - 1 && index == day.items.count - 1
                    row(item, TimelinePlace(runsBelow: !isLast, isWide: width >= TimelineMetrics.wideWidth))
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: {
            width = $0
        }
    }
}
