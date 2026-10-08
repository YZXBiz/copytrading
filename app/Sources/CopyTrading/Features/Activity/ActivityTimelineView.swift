import DesktopCore
import SwiftUI

/// The post's trip in four timed phases, one hairline row each: received, read, sent, and how it ended, with
/// a post in flight's live step under the phase it is past.
struct ActivityTimelineView: View {
    let timeline: PostTimeline
    /// The step a post in flight is on now, ticking under its latest phase.
    var progress: PostProgress?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(timeline.phases) { phase in
                ActivityTimelineRow(phase: phase, progress: phase.id == timeline.phases.last?.id ? progress : nil)
            }
            if timeline.toOrder != nil || timeline.toFill != nil {
                Hairline()
                HStack(spacing: 28) {
                    if let toOrder = timeline.toOrder {
                        total(L10n.string("Post to order sent"), toOrder)
                    }
                    if let toFill = timeline.toFill {
                        total(L10n.string("Post to fill"), toFill)
                    }
                }
                .padding(.top, 12)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.string("Timeline"))
    }

    private func total(_ label: String, _ seconds: TimeInterval) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ActivityLabel(text: label)
            Text(PostTimeline.duration(seconds))
                .font(DesignTokens.statValue)
                .monospacedDigit()
                .foregroundStyle(Palette.ink)
        }
        .accessibilityElement(children: .combine)
    }
}
