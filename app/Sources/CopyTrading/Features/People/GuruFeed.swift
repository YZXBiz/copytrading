import DesktopCore
import Foundation

/// One guru's posts for their page: newest first, grouped by day, each with how it was read and
/// what each account did, and the numbers counted from them.
@MainActor
struct GuruFeed: Equatable {
    struct Entry: Equatable, Identifiable {
        let item: SourceActivity
        /// How the reader took the post, in one line: "Buy PM at $201 · Full position".
        let readAs: String
        let accounts: [GuruAccountOutcome]

        var id: SourceActivity.ID { item.id }
    }

    struct Day: Equatable, Identifiable {
        let start: Date
        let entries: [Entry]

        var id: Date { start }
    }

    let days: [Day]
    let stats: GuruStats

    init(
        guruID: String, activity: [SourceActivity], skipped: (String) -> Bool, now: Date = .now,
        calendar: Calendar = AppTime.calendar
    ) {
        let entries = Self.posts(of: guruID, in: activity).map { item in
            Entry(
                item: item, readAs: Self.readAs(item),
                accounts: GuruAccountOutcome.outcomes(of: item, skipped: skipped(item.sourceID), now: now))
        }
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
        stats = GuruStats(entries: entries, calendar: calendar, now: now)
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
        guard let reading = item.reading, !reading.calls.isEmpty else { return item.headline }
        return reading.calls.map { call in
            let (title, detail) = ReadAsText.headline(call)
            return [title, detail].compactMap(\.self).joined(separator: " · ")
        }
        .joined(separator: "; ")
    }
}
