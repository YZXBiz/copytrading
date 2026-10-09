import SwiftUI

/// A post in flight as one calm moment: a centred headline that changes with each step, a quiet
/// line with the running time, and an ink dot moving along the ground a stage at a time. When the
/// order fills the dot bounces once and everything stands still; nothing here loops.
struct PostLiveMoment: View {
    /// The step the post is on; nil once its order has filled.
    let progress: PostProgress?
    /// What filled, for the line under "Filled": "Bought 1 share of PM at $199.59".
    let filledLine: String
    @State private var hops = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var stage: Int { progress?.stage ?? PostProgress.filledStage }

    /// The ink dot's place along the ground for each stage; it does not move again to hop.
    private var fraction: CGFloat {
        [0.14, 0.36, 0.58, 0.8, 0.8][min(stage, PostProgress.filledStage)]
    }

    var body: some View {
        VStack(spacing: 8) {
            Text(progress?.headline ?? L10n.string("Filled"))
                .font(DisplayFont.font(size: 24, relativeTo: .title2))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
            calmLine
                .font(DesignTokens.lede)
                .tracking(DesignTokens.ledeTracking)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            InkGround(height: 56)
                .overlay {
                    GeometryReader { proxy in
                        // One dot glides on a stage at a time and bounces where it stands on a fill.
                        InkBead(hop: hops)
                            .position(x: proxy.size.width * fraction, y: proxy.size.height - 2 - 6)
                            .animation(reduceMotion ? nil : .smooth(duration: 0.6), value: fraction)
                    }
                }
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .animation(reduceMotion ? nil : .easeInOut(duration: 1.2), value: stage)
        .task(id: stage) {
            guard stage == PostProgress.filledStage else { return }
            try? await Task.sleep(for: .milliseconds(300))
            hops += 1
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("activity.progress")
    }

    @ViewBuilder
    private var calmLine: some View {
        if let progress {
            // Ticks once a second only while the post is in flight.
            TimelineView(.periodic(from: progress.since, by: 1)) { context in
                Text(progress.calmLine(at: context.date))
                    .monospacedDigit()
                    .foregroundStyle(progress.waitsOnOwner ? Palette.amber : Palette.tertiaryInk)
            }
        } else {
            Text(filledLine)
                .monospacedDigit()
                .foregroundStyle(Palette.tertiaryInk)
        }
    }
}
