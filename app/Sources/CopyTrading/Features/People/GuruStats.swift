import DesktopCore
import Foundation

/// The numbers at the top of a guru's page, counted from the posts CopyTrading has loaded.
struct GuruStats: Equatable {
    let postsToday: Int
    /// Today's posts at least one account bought or sold on.
    let tradedToday: Int
    /// Posts with a call still waiting for the owner, any day.
    let waiting: Int
    /// How long the reader took per post, on average; nil before any post was read.
    let averageRead: TimeInterval?

    @MainActor
    init(entries: [GuruFeed.Entry], calendar: Calendar, now: Date) {
        let today = entries.filter { $0.item.sourceDate.map { calendar.isDate($0, inSameDayAs: now) } ?? false }
        postsToday = today.count
        tradedToday = today.filter { $0.accounts.contains { $0.kind == .traded } }.count
        waiting = entries.filter { $0.accounts.contains { $0.kind == .waiting } }.count
        let reads = entries.compactMap { entry -> TimeInterval? in
            guard let started = Humanize.date(entry.item.readStartedAt), let read = Humanize.date(entry.item.readAt) else {
                return nil
            }
            return max(0, read.timeIntervalSince(started))
        }
        averageRead = reads.isEmpty ? nil : reads.reduce(0, +) / Double(reads.count)
    }
}
