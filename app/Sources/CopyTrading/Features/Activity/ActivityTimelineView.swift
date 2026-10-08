import DesktopCore
import SwiftUI

/// The post's trip as a vertical list of timed steps: a dot and a rail, the step, its time to
/// the second, and how long it took since the step before. A slow step says so in orange.
struct ActivityTimelineView: View {
    let timeline: PostTimeline

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(timeline.rows) { row in
                    ActivityTimelineRow(row: row, isLast: row.id == timeline.rows.last?.id)
                }
            }
            if timeline.toOrder != nil || timeline.toFill != nil {
                HStack(spacing: 18) {
                    if let toOrder = timeline.toOrder {
                        total(L10n.string("Post to order sent"), toOrder)
                    }
                    if let toFill = timeline.toFill {
                        total(L10n.string("Post to fill"), toFill)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.string("Timeline"))
    }

    private func total(_ label: String, _ seconds: TimeInterval) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .foregroundStyle(Palette.secondaryInk)
            Text(PostTimeline.duration(seconds))
                .monospacedDigit()
                .foregroundStyle(Palette.ink)
                .fontWeight(.medium)
        }
        .font(DesignTokens.caption)
    }
}
