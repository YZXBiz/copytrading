import DesktopCore
import SwiftUI

/// The account's activity in one column that reads top to bottom in time, newest first, split by day
/// and joined by the timeline's ink rail. Opening a post marks every row of the holding its buy
/// opened or joined, the other buys and the sales of it too, and quiets the rest.
struct AccountFeedTimeline: View {
    let items: [AccountFeedItem]
    let directory: GuruDirectory
    let selectedPostID: SourceActivity.ID?
    /// The post a row came from, if Activity still holds it.
    let post: (AccountFeedItem) -> SourceActivity?
    let openPost: (SourceActivity.ID) -> Void

    /// The holdings the open post's trades belong to.
    private var linkedLots: Set<String> {
        guard let selectedPostID else { return [] }
        return Set(items.filter { post($0)?.id == selectedPostID }.compactMap(\.lotID))
    }

    var body: some View {
        let lots = linkedLots
        // Only a holding with more than one row is worth quieting the rest for.
        let quiets = items.filter { $0.lotID.map(lots.contains) == true }.count > 1
        TimelineFeed(days: TimelineDay.days(of: items) { Humanize.date($0.at) }) { item, place in
            let post = post(item)
            let isSelected = post != nil && post?.id == selectedPostID
            let isLinked = isSelected || item.lotID.map(lots.contains) == true
            AccountFeedRow(
                item: item, directory: directory, place: place, isSelected: isLinked,
                open: post.map { post in { openPost(post.id) } }
            )
            .opacity(!quiets || isLinked ? 1 : 0.4)
        }
    }
}
