import DesktopCore
import SwiftUI

/// The post's trip in four timed phases on a rail: received, read, sent, and how it ended, with
/// a post in flight's live step under the phase it is past.
struct ActivityTimelineView: View {
    let timeline: PostTimeline
    /// The step a post in flight is on now, ticking under its latest phase.
    var progress: PostProgress?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(timeline.phases) { phase in
                    let isLast = phase.id == timeline.phases.last?.id
                    ActivityTimelineRow(phase: phase, isLast: isLast, progress: isLast ? progress : nil)
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
