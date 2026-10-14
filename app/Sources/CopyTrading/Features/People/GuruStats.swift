import DesktopCore
import Foundation

/// The numbers at the top of a guru's page and under their name in the sidebar, as the engine
/// counted them over the owner's whole day; the posts the app has loaded are only the newest few.
struct GuruStats: Equatable {
    let postsToday: Int
    /// Today's posts at least one account bought or sold on.
    let tradedToday: Int
    /// Posts with a call still waiting for the owner, any day, less the ones they skipped.
    let waiting: Int
    /// How long the reader took per post today, on average; nil before any post was read.
    let averageRead: TimeInterval?

    /// A guru the engine counted nothing for has a quiet day.
    init(day: GuruDayStats?, skipped: (String) -> Bool) {
        postsToday = day?.posts ?? 0
        tradedToday = day?.traded ?? 0
        waiting = day?.waitingSourceIDs.filter { !skipped($0) }.count ?? 0
        averageRead = day?.readSeconds
    }

    /// The line under the guru's name in the sidebar: how many calls need the owner, else how
    /// busy today has been.
    @MainActor var sidebarDetail: String {
        if waiting > 0 { return L10n.string("%lld need you", Int64(waiting)) }
        if postsToday > 0 { return L10n.string("%@ today", Humanize.count(postsToday, "post")) }
        return L10n.string("Quiet today")
    }
}
