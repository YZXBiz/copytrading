import SwiftUI

/// One phase as a hairline row: what happened and when, how long the phase took, the finer steps
/// in one quiet line, its waits, and, for a post in flight, the live step.
struct ActivityTimelineRow: View {
    let phase: PostTimeline.Phase
    /// The step a post in flight is on now, shown under the phase it follows.
    var progress: PostProgress?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Hairline()
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(phase.title)
                        .font(DesignTokens.activityBody.weight(.medium))
                        .foregroundStyle(Palette.ink)
                    Spacer(minLength: 8)
                    if let duration = phase.duration {
                        Text(PostTimeline.duration(duration))
                            .foregroundStyle(Palette.tertiaryInk)
                            .padding(.trailing, 6)
                    }
                    Text(phase.at.formatted(AppTime.style(.dateTime.hour().minute().second())))
                        .foregroundStyle(Palette.secondaryInk)
                }
                .font(DesignTokens.activityIdentifier)
                if let detail = phase.detail {
                    Text(detail)
                        .font(DesignTokens.activityMeta)
                        .foregroundStyle(Palette.secondaryInk)
                        .monospacedDigit()
                        .textSelection(.enabled)
                }
                ForEach(phase.waits, id: \.self) { wait in
                    Text(wait)
                        .font(DesignTokens.activityMeta)
                        .foregroundStyle(Palette.tertiaryInk)
                }
                if let progress {
                    PostProgressLabel(progress: progress)
                        .font(DesignTokens.activityMeta.weight(.medium))
                        .padding(.top, 2)
                }
            }
            .padding(.vertical, 10)
        }
        .accessibilityElement(children: .combine)
    }
}
