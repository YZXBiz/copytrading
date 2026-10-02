import SwiftUI

/// What CopyTrading does, in one picture: a guru's post, how it was read, and the order an account
/// placed. The first time the figure scrolls into view, each stage lights in turn, the way a post
/// travels; under Reduce Motion it stays still.
struct GuideFlowFigure: View {
    @State private var litStage = 0
    @State private var hasPlayed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GuideFigure(
            description: L10n.string(
                "Example: %@ posts “%@”. CopyTrading reads it as %@, a sixth of a position, and the paper account fills %@.",
                "Alex Chen", "ALERT: Bought NVDA 1/6 at 121.38", "buy NVDA at $121.38", "12 NVDA at $121.38"
            )
        ) {
            // The guide's page never gets narrower than three readable cards side by side.
            HStack(alignment: .top, spacing: 8) {
                GuideFlowStages(litStage: litStage)
            }
        }
        .onScrollVisibilityChange(threshold: 0.6, playOnce)
        .task(id: hasPlayed) {
            await play()
        }
    }

    private func playOnce(_ isVisible: Bool) {
        guard isVisible, !hasPlayed, !reduceMotion else { return }
        hasPlayed = true
    }

    /// Lights each stage in turn, then lets the figure settle.
    private func play() async {
        guard hasPlayed else { return }
        for stage in 1...3 {
            litStage = stage
            do {
                try await Task.sleep(for: .milliseconds(650))
            } catch {
                break
            }
        }
        litStage = 0
    }
}
