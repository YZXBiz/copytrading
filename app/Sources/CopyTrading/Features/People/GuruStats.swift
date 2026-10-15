import DesktopCore
import Foundation

/// The numbers at the top of a guru's page and under their name in the sidebar, as the engine
/// counted them over the owner's whole day; the posts the app has loaded are only the newest few.
struct GuruStats: Equatable {
    let postsToday: Int
    /// Today's posts at least one account bought or sold on.
    let tradedToday: Int
    /// Posts with a call still waiting for the owner through the trading day, less the ones they
    /// skipped or entered by hand: the posts the Waiting tab lists.
    let waiting: Int
    /// How long the reader took per post today, on average; nil before any post was read.
    let averageRead: TimeInterval?

    /// A guru the engine counted nothing for has a quiet day. A page that lists the waiting posts
    /// passes their count, so the strip and the tab cannot differ.
    init(day: GuruDayStats?, waiting: Int) {
        postsToday = day?.posts ?? 0
        tradedToday = day?.traded ?? 0
        self.waiting = waiting
        averageRead = day?.readSeconds
    }

    init(day: GuruDayStats?, skipped: (String) -> Bool, now: Date = .now) {
        self.init(day: day, waiting: day?.stillWaiting(skipped: { skipped($0) }, now: now).count ?? 0)
    }

    /// The line under the guru's name in the sidebar: how many calls need the owner, else how
    /// busy today has been.
    @MainActor var sidebarDetail: String {
        if waiting > 0 { return L10n.string("%lld need you", Int64(waiting)) }
        if postsToday > 0 { return L10n.string("%@ today", Humanize.count(postsToday, "post")) }
        return L10n.string("Quiet today")
    }
}
