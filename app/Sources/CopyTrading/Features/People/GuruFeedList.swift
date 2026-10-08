import DesktopCore
import SwiftUI

/// A guru's posts, newest first, under a spaced-capital label for each day, rows split by hairlines.
struct GuruFeedList: View {
    let days: [GuruFeed.Day]
    let guruName: String
    @Binding var selection: SourceActivity.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ListHeading("Posts") {
                if !days.isEmpty {
                    Text(L10n.string("Newest first"))
                }
            }
            if days.isEmpty {
                InkEmptyState(
                    message: L10n.string("No posts from %@ yet. They show here as soon as CopyTrading reads one.", guruName)
                )
                .padding(.top, 20)
            }
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(days) { day in
                    GuruFeedDayLabel(start: day.start)
                        .padding(.top, 28)
                        .padding(.bottom, 10)
                    Hairline()
                    ForEach(day.entries) { entry in
                        GuruFeedRow(entry: entry, selection: $selection)
                        Hairline()
                    }
                }
            }
        }
    }
}
