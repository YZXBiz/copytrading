import DesktopCore
import SwiftUI
import TipKit

/// A segmented track above the post list, with how many posts are showing.
struct ActivityFilterBar: View {
    @Binding var filter: ActivityFilter
    let activity: [SourceActivity]
    let shown: Int
    /// Older posts are still on the engine: every count here covers only what is loaded.
    let hasMore: Bool

    @Environment(\.tipGeneration) private var tipGeneration
    @Environment(SkippedCalls.self) private var skippedCalls: SkippedCalls?

    private var more: String { hasMore ? "+" : "" }
    private var hasPostsToReview: Bool { activity.contains { ActivityFilter.waiting.includes($0, skipped: skippedCalls) } }

    var body: some View {
        HStack(spacing: 12) {
            SegmentedTrack(options: ActivityFilter.allCases, selection: $filter) { option in
                let count = activity.filter { option.includes($0, skipped: skippedCalls) }.count
                Text(
                    option == .all || count == 0
                        ? option.title
                        : L10n.string("%@  %@", option.title, "\(count.formatted())\(more)")
                )
                .monospacedDigit()
            }
            .popoverTip(NeedsReviewTip(generation: tipGeneration), arrowEdge: .top)
            Text(
                L10n.string(
                    shown == 1 && !hasMore ? "%@ post" : "%@ posts",
                    "\(shown.formatted())\(more)"
                )
            )
            .font(DesignTokens.caption)
            .foregroundStyle(Palette.tertiaryInk)
            .monospacedDigit()
            .fixedSize()
        }
        .task(id: hasPostsToReview) {
            if hasPostsToReview { await NeedsReviewTip.reviewWaiting.donate() }
        }
        .onChange(of: filter) { _, chosen in
            if chosen == .waiting { NeedsReviewTip(generation: tipGeneration).invalidate(reason: .actionPerformed) }
        }
    }
}
