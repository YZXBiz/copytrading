import DesktopCore
import SwiftUI

/// A guru's posts, newest first, on one timeline, filtered by what came of them.
struct GuruFeedList: View {
    let days: [GuruFeed.Day]
    let guruName: String
    /// Whether the engine's posts have been read at all; until then no post is not the same as none.
    let isRead: Bool
    @Binding var selection: SourceActivity.ID?
    @State private var filter = GuruPostFilter.all

    private var entries: [GuruFeed.Entry] { days.flatMap(\.entries) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ListHeading("Posts")
            if !days.isEmpty {
                TrackedSwitcher(
                    choices: GuruPostFilter.allCases, selection: $filter, title: \.title,
                    count: { choice in entries.count { choice.includes($0) } }, identifier: "guru.filter"
                )
                .padding(.top, 16)
            }
            if days.isEmpty {
                InkEmptyState(
                    message: isRead
                        ? L10n.string("No posts from %@ yet. They show here as soon as CopyTrading reads one.", guruName)
                        : L10n.string("%@'s posts show here once CopyTrading has read them.", guruName)
                )
                .padding(.top, 20)
            }
            GuruPostTimeline(entries: entries.filter(filter.includes), selection: $selection)
                .padding(.top, 28)
        }
    }
}
