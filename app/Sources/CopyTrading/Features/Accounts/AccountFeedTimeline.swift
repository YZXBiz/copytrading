import DesktopCore
import SwiftUI

/// The account's activity in one column that reads top to bottom in time, newest first, split by day
/// and joined by the timeline's ink rail.
struct AccountFeedTimeline: View {
    let items: [AccountFeedItem]
    let directory: GuruDirectory
    let selectedPostID: SourceActivity.ID?
    /// The post a row came from, if Activity still holds it.
    let post: (AccountFeedItem) -> SourceActivity?
    let openPost: (SourceActivity.ID) -> Void

    var body: some View {
        TimelineFeed(days: TimelineDay.days(of: items) { Humanize.date($0.at) }) { item, place in
            let post = post(item)
            AccountFeedRow(
                item: item, directory: directory, place: place, isSelected: post != nil && post?.id == selectedPostID,
                open: post.map { post in { openPost(post.id) } })
        }
    }
}
