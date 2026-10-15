import DesktopCore
import Foundation

/// One guru's posts for their page: newest first, grouped by day, each with how it was read and
/// what each account did.
@MainActor
struct GuruFeed: Equatable {
    struct Entry: Equatable, Identifiable {
        let item: SourceActivity
        /// How the reader took the post, in one line: "Buy PM at $201 · Full position".
        let readAs: String
        let accounts: [GuruAccountOutcome]
        /// A call of the post still waits for the owner: the engine counted it, and it is neither
        /// skipped, entered by hand, nor past its trading day.
        let isWaiting: Bool

        var id: SourceActivity.ID { item.id }
    }

    struct Day: Equatable, Identifiable {
        let start: Date
        let entries: [Entry]

        var id: Date { start }
    }

    let days: [Day]
    /// How many posts wait for the owner: the sidebar's count and the Waiting tab's, one number.
    let waitingCount: Int

    /// `day` is the engine's count for the guru; the posts it holds as waiting are listed whether
    /// or not they are among the newest `activity`, and they are the only ones that read as waiting.
    init(
        guruID: String, activity: [SourceActivity], day: GuruDayStats? = nil, skipped: (String) -> Bool,
        now: Date = .now, calendar: Calendar = AppTime.calendar
    ) {
        let waiting = day?.stillWaiting(skipped: skipped, now: now) ?? []
        let waitingIDs = Set(waiting.map(\.id))
        let entries = Self.posts(of: guruID, in: waiting + activity.filter { !waitingIDs.contains($0.id) }).map { item in
            Entry(
                item: item, readAs: Self.readAs(item),
                accounts: GuruAccountOutcome.outcomes(of: item, skipped: skipped(item.sourceID), now: now),
                isWaiting: waitingIDs.contains(item.id))
        }
        waitingCount = entries.count { $0.isWaiting }
        var days: [Day] = []
        for entry in entries {
            let start = calendar.startOfDay(for: entry.item.sourceDate ?? .distantPast)
            if let last = days.last, last.start == start {
                days[days.count - 1] = Day(start: start, entries: last.entries + [entry])
            } else {
                days.append(Day(start: start, entries: [entry]))
            }
        }
        self.days = days
    }

    /// The guru's posts, newest first; ties keep the engine's newest sequence first.
    static func posts(of guruID: String, in activity: [SourceActivity]) -> [SourceActivity] {
        activity.filter { $0.guruID == guruID }.sorted {
            let left = $0.sourceDate ?? .distantPast
            let right = $1.sourceDate ?? .distantPast
            return left == right ? $0.sequence > $1.sequence : left > right
        }
    }

    /// Each call as the card's headline and its size, joined; a post with no calls says what it was.
    static func readAs(_ item: SourceActivity) -> String {
        guard let reading = item.reading, !reading.calls.isEmpty else {
            return [item.headline, item.sortedNote].compactMap(\.self).joined(separator: " · ")
        }
        return reading.calls.map { call in
            let (title, detail) = ReadAsText.headline(call)
            return [title, detail].compactMap(\.self).joined(separator: " · ")
        }
        .joined(separator: "; ")
    }
}
