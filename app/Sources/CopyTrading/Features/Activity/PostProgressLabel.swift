import SwiftUI

/// A post's live step with its running time, ticking once a second. It is only built for a post
/// still in flight, so a settled post never ticks.
struct PostProgressLabel: View {
    let progress: PostProgress
    /// The list row's short words instead of the card's sentence.
    var compact = false

    var body: some View {
        TimelineView(.periodic(from: progress.since, by: 1)) { context in
            let slow = progress.isSlow(at: context.date)
            Label {
                Text(compact ? progress.short(at: context.date) : progress.line(at: context.date))
                    .monospacedDigit()
            } icon: {
                Image(systemName: symbol)
            }
            .foregroundStyle(slow ? Color.orange : Palette.accent)
        }
        .accessibilityIdentifier("activity.progress")
    }

    private var symbol: String {
        switch progress.step {
        case .waitingToRead, .reading: "text.magnifyingglass"
        case .handingOff, .nextCycle: "arrow.triangle.branch"
        case .heldForResume: "pause.circle"
        case .awaitingFill: "hourglass"
        }
    }
}
