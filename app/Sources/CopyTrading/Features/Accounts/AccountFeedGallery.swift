import DesktopCore
import SwiftUI

/// The account's activity as a two-column gallery, newest first across the top, each column taking
/// the next tile while it is the shorter one. A narrow page shows one column.
struct AccountFeedGallery: View {
    let items: [AccountFeedItem]
    let directory: GuruDirectory
    let selectedPostID: SourceActivity.ID?
    /// The post a tile came from, if Activity still holds it.
    let post: (AccountFeedItem) -> SourceActivity?
    let openPost: (SourceActivity.ID) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 28) {
                ForEach(Array(Self.columns(items, count: 2).enumerated()), id: \.offset) { _, column in
                    stack(column)
                        .frame(minWidth: 280)
                }
            }
            stack(items)
        }
    }

    private func stack(_ column: [AccountFeedItem]) -> some View {
        LazyVStack(spacing: 20) {
            ForEach(Array(column.enumerated()), id: \.element.id) { index, item in
                let post = post(item)
                AccountFeedTile(
                    item: item, directory: directory, isSelected: post != nil && post?.id == selectedPostID,
                    open: post.map { post in { openPost(post.id) } }, showsRule: index > 0)
            }
        }
    }

    /// Deals tiles into columns by a rough height: a trade carries its big figure.
    static func columns(_ items: [AccountFeedItem], count: Int) -> [[AccountFeedItem]] {
        var columns = Array(repeating: [AccountFeedItem](), count: count)
        var heights = Array(repeating: 0.0, count: count)
        for item in items {
            let target = heights.indices.min { heights[$0] < heights[$1] } ?? 0
            columns[target].append(item)
            heights[target] += item.isTrade ? 170 : 130
        }
        return columns
    }
}
