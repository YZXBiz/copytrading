import SwiftUI

/// A post in flight as one calm moment: a centred headline that changes with each step, a quiet
/// line with the running time, and the walker crossing the ground a few steps per stage. When the
/// order fills the walker hops once and everything stands still; nothing here loops.
struct PostLiveMoment: View {
    /// The step the post is on; nil once its order has filled.
    let progress: PostProgress?
    /// What filled, for the line under "Filled": "Bought 1 share of PM at $199.59".
    let filledLine: String
    @State private var hops = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var stage: Int { progress?.stage ?? PostProgress.filledStage }

    /// The walker's place along the ground for each stage; it does not move again to hop.
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
                        InkWalker(hop: hops)
                            // A new stage is a new walker, so it takes its few steps again on the
                            // way; filling keeps the same one, so it hops where it stands.
                            .id(min(stage, PostProgress.filledStage - 1))
                            .transition(.identity)
                            .position(x: proxy.size.width * fraction, y: proxy.size.height - 2 - 14.5)
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
