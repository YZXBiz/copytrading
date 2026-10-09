import SwiftUI

/// A day's label in the timeline's gutter, in tracked capitals, with the rail running through and a
/// hairline across the rest of the row.
struct TimelineDayRow: View {
    let title: String
    let runsAbove: Bool
    var top: CGFloat = 0

    var body: some View {
        TimelineRow(mark: nil, runsAbove: runsAbove, runsBelow: true, isWide: true, trailingWidth: 0, top: top, bottom: 8) {
            Eyebrow(title)
                .accessibilityAddTraits(.isHeader)
        } content: {
            Hairline()
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4.5 }
        } trailing: {
            EmptyView()
        }
    }
}
