import DesktopCore
import Foundation

/// One row of Activity's list: a guru's post, or a sale the owner made, placed by time.
enum ActivityListEntry: Identifiable {
    case post(SourceActivity)
    case sale(accountID: String, AccountFeedItem)

    var id: String {
        switch self {
        case .post(let item): "post:\(item.id)"
        case .sale(let accountID, let item): "sale:\(accountID):\(item.sequence)"
        }
    }

    var date: Date? {
        switch self {
        case .post(let item): item.sourceDate
        case .sale(_, let item): Humanize.date(item.at)
        }
    }

    /// Posts and sales newest first. A sale older than every loaded post waits for older posts
    /// to load, so the list never shows it above posts it came after.
    static func merged(
        posts: [SourceActivity], sales: [(accountID: String, item: AccountFeedItem)], hasMorePosts: Bool
    ) -> [ActivityListEntry] {
        let oldest = posts.compactMap(\.sourceDate).min()
        let shown = sales.filter { sale in
            guard hasMorePosts, let oldest else { return true }
            return (Humanize.date(sale.item.at) ?? .distantPast) >= oldest
        }
        let entries = posts.map(ActivityListEntry.post) + shown.map { ActivityListEntry.sale(accountID: $0.accountID, $0.item) }
        return entries.enumerated()
            .sorted { lhs, rhs in
                let left = lhs.element.date ?? .distantPast
                let right = rhs.element.date ?? .distantPast
                return left == right ? lhs.offset < rhs.offset : left > right
            }
            .map(\.element)
    }
}
