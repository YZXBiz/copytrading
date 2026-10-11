import DesktopCore
import SwiftUI

/// A guru's posts in one column that reads top to bottom in time, newest first, split by day and
/// joined by the timeline's ink rail.
struct GuruPostTimeline: View {
    let entries: [GuruFeed.Entry]
    @Binding var selection: SourceActivity.ID?

    var body: some View {
        TimelineFeed(days: TimelineDay.days(of: entries) { $0.item.sourceDate }) { entry, place in
            GuruPostRow(entry: entry, place: place, selection: $selection)
        }
    }
}
