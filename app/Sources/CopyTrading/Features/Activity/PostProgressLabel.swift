import SwiftUI

/// A post's live step with its running time, ticking once a second, as one quiet line. It is only
/// built for a post still in flight, so a settled post never ticks.
struct PostProgressLabel: View {
    let progress: PostProgress

    var body: some View {
        TimelineView(.periodic(from: progress.since, by: 1)) { context in
            Text(progress.line(at: context.date))
                .monospacedDigit()
                .foregroundStyle(progress.waitsOnOwner ? Palette.amber : Palette.secondaryInk)
        }
    }
}
