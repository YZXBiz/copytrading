import DesktopCore
import SwiftUI

/// The post's trip drawn as one ink line: a dot for each phase (received, read, sent, how it
/// ended) with its name under it and the time it took over the stretch before it. A phase that
/// ended badly or waits on the owner is a hollow dot; the rest are solid.
struct PostJourneyLine: View {
    let timeline: PostTimeline

    var body: some View {
        let phases = timeline.phases
        if phases.count >= 2 {
            VStack(alignment: .leading, spacing: 8) {
                GeometryReader { proxy in
                    let step = proxy.size.width / CGFloat(max(phases.count - 1, 1))
                    ZStack(alignment: .topLeading) {
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: 30))
                            path.addLine(to: CGPoint(x: proxy.size.width, y: 30))
                        }
                        .stroke(Palette.ink, style: InkStroke.style)
                        ForEach(Array(phases.enumerated()), id: \.element.id) { index, phase in
                            let x = CGFloat(index) * step
                            if let duration = phase.duration, index > 0 {
                                Text(PostTimeline.duration(duration))
                                    .font(DesignTokens.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(Palette.tertiaryInk)
                                    .fixedSize()
                                    .position(x: x - step / 2, y: 12)
                            }
                            dot(phase)
                                .position(x: x, y: 30)
                            // The line names the phase; its full story is in Technical details.
                            Text(phase.title.components(separatedBy: " · ").first ?? phase.title)
                                .font(DesignTokens.caption.weight(.medium))
                                .foregroundStyle(phase.caution ? Palette.amber : Palette.ink)
                                .fixedSize()
                                .position(x: label(x, in: proxy.size.width), y: 52)
                        }
                    }
                }
                .frame(height: 62)
                .padding(.horizontal, 24)
                if let toFill = timeline.toFill {
                    Text(L10n.string("Post to fill in %@", PostTimeline.duration(toFill)))
                        .font(DesignTokens.lede)
                        .tracking(DesignTokens.ledeTracking)
                        .foregroundStyle(Palette.tertiaryInk)
                } else if let toOrder = timeline.toOrder {
                    Text(L10n.string("Post to order in %@", PostTimeline.duration(toOrder)))
                        .font(DesignTokens.lede)
                        .tracking(DesignTokens.ledeTracking)
                        .foregroundStyle(Palette.tertiaryInk)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                phases.map { phase in
                    phase.duration.map { L10n.string("%@ after %@", phase.title, PostTimeline.duration($0)) } ?? phase.title
                }
                .joined(separator: ", "))
        }
    }

    @ViewBuilder
    private func dot(_ phase: PostTimeline.Phase) -> some View {
        if phase.caution {
            Circle()
                .strokeBorder(Palette.amber, lineWidth: InkStroke.width)
                .background(Circle().fill(Palette.page))
                .frame(width: 11, height: 11)
        } else {
            Circle()
                .fill(Palette.ink)
                .frame(width: 9, height: 9)
        }
    }

    /// Names at the ends stay inside the line's width.
    private func label(_ x: CGFloat, in width: CGFloat) -> CGFloat {
        min(max(x, 18), width - 18)
    }
}
