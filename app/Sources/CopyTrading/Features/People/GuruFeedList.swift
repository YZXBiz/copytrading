import DesktopCore
import SwiftUI

/// A guru's posts, newest first, on one timeline, filtered by what came of them.
struct GuruFeedList: View {
    let days: [GuruFeed.Day]
    let guruName: String
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
                    message: L10n.string("No posts from %@ yet. They show here as soon as CopyTrading reads one.", guruName)
                )
                .padding(.top, 20)
            }
            GuruPostTimeline(entries: entries.filter(filter.includes), selection: $selection)
                .padding(.top, 28)
        }
    }
}
