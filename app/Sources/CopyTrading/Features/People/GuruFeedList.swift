import DesktopCore
import SwiftUI

/// A guru's posts, newest first, on one timeline, filtered by what came of them.
struct GuruFeedList: View {
    let days: [GuruFeed.Day]
    /// Whether the engine's posts have been read at all; until then no post is not the same as none.
    let isRead: Bool
    /// Why the guru's posts could not be read, if the last read failed.
    let error: String?
    @Binding var selection: SourceActivity.ID?
    /// Reads the guru's next older posts; nil once the oldest is shown.
    let loadMore: (() -> Void)?
    @State private var filter = GuruPostFilter.all

    private var entries: [GuruFeed.Entry] { days.flatMap(\.entries) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The tabs name what is listed; a heading shows only over an empty list.
            if days.isEmpty {
                ListHeading("Posts")
            } else {
                SectionSwitcher(
                    choices: GuruPostFilter.allCases, selection: $filter, title: \.title,
                    count: { choice in entries.count { choice.includes($0) } }, identifier: "guru.filter"
                )
            }
            if let error {
                Callout(error, tone: .critical)
                    .padding(.top, 12)
            }
            if days.isEmpty {
                InkEmptyState(
                    message: isRead
                        ? L10n.string("No posts yet")
                        : L10n.string("Not read yet")
                )
                .padding(.top, 20)
            }
            GuruPostTimeline(entries: entries.filter(filter.includes), selection: $selection)
                .padding(.top, 28)
            if let loadMore {
                Button(L10n.string("Show Older Posts"), action: loadMore)
                    .buttonStyle(PageButtonStyle())
                    .padding(.top, 8)
            }
        }
    }
}
