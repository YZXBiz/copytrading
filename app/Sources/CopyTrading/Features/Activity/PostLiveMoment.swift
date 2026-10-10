import SwiftUI

/// A post in flight as one calm moment: a centred headline that changes with each step, a quiet
/// line under it, and the four stops (Read · Sized · Sent · Filled) on one ink line with the bead
/// where the post is. A fill wait grows along the Sent–Filled stretch with its countdown over it.
/// When the order fills the bead bounces once and everything stands still; nothing here loops.
struct PostLiveMoment: View {
    /// The step the post is on; nil once its order has filled.
    let progress: PostProgress?
    /// What filled, for the line under "Filled": "Bought 1 share of PM at $199.59".
    let filledLine: String
    @State private var hops = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var stage: Int { progress?.stage ?? PostProgress.filledStage }

    var body: some View {
        VStack(spacing: 8) {
            Text(progress?.headline ?? L10n.string("Filled"))
                .font(DisplayFont.font(size: 24, relativeTo: .title2))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
            if let progress {
                // Ticks once a second only while the post is in flight.
                TimelineView(.periodic(from: progress.since, by: 1)) { context in
                    VStack(spacing: 14) {
                        calm(progress.calmLine(at: context.date), color: progress.waitsOnOwner ? Palette.amber : Palette.tertiaryInk)
                        PostStageLine(
                            stage: stage, fillWait: progress.fillWait(at: context.date),
                            waitText: progress.fillWaitText(at: context.date), waitsOnOwner: progress.waitsOnOwner)
                    }
                }
            } else {
                VStack(spacing: 14) {
                    calm(filledLine, color: Palette.tertiaryInk)
                    PostStageLine(stage: stage, hops: hops)
                }
            }
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

    private func calm(_ text: String, color: Color) -> some View {
        Text(text)
            .font(DesignTokens.lede)
            .tracking(DesignTokens.ledeTracking)
            .monospacedDigit()
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }
}
