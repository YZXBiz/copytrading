import SwiftUI

/// One phase: its dot on the rail, what happened and when, how long the phase took, the finer
/// steps in one quiet line, its waits in orange, and, for a post in flight, the live step.
struct ActivityTimelineRow: View {
    let phase: PostTimeline.Phase
    let isLast: Bool
    /// The step a post in flight is on now, shown under the phase it follows.
    var progress: PostProgress?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Circle()
                    .fill(phase.caution ? Color.orange : Palette.accent)
                    .frame(width: 8, height: 8)
                    .padding(.top, 5)
                if !isLast {
                    Rectangle()
                        .fill(Palette.secondaryInk.opacity(0.25))
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 8)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(phase.title)
                        .font(DesignTokens.bodyText)
                        .foregroundStyle(phase.caution ? .orange : Palette.ink)
                    Spacer(minLength: 8)
                    if let duration = phase.duration {
                        Text(PostTimeline.duration(duration))
                            .font(DesignTokens.caption.monospacedDigit())
                            .foregroundStyle(Palette.tertiaryInk)
                    }
                    Text(phase.at.formatted(AppTime.style(.dateTime.hour().minute().second())))
                        .font(DesignTokens.caption.monospacedDigit())
                        .foregroundStyle(Palette.secondaryInk)
                }
                if let detail = phase.detail {
                    Text(detail)
                        .font(DesignTokens.caption)
                        .foregroundStyle(Palette.secondaryInk)
                        .textSelection(.enabled)
                }
                ForEach(phase.waits, id: \.self) { wait in
                    Label(wait, systemImage: "hourglass")
                        .font(DesignTokens.caption)
                        .foregroundStyle(.orange)
                }
                if let progress {
                    PostProgressLabel(progress: progress)
                        .font(DesignTokens.caption.weight(.medium))
                        .padding(.top, 2)
                }
            }
            .padding(.bottom, isLast ? 0 : 14)
        }
        .accessibilityElement(children: .combine)
    }
}
