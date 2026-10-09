import Foundation

/// One day of a timeline: its start, and its items in the order they came, newest first.
struct TimelineDay<Item: Identifiable>: Identifiable {
    let start: Date
    let items: [Item]

    var id: Date { start }

    /// The day's label over its posts: "Today", "Yesterday", then "Tue, Oct 7".
    @MainActor
    func title(now: Date = .now) -> String {
        let calendar = AppTime.calendar
        if calendar.isDate(start, inSameDayAs: now) { return L10n.string("Today") }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(start, inSameDayAs: yesterday) {
            return L10n.string("Yesterday")
        }
        let sameYear = calendar.isDate(start, equalTo: now, toGranularity: .year)
        let base = Date.FormatStyle.dateTime.weekday(.abbreviated).month(.abbreviated).day()
        return start.formatted(AppTime.style(sameYear ? base : base.year()))
    }

    /// Splits items that are already newest first into days; an item with no date joins the day before it.
    @MainActor
    static func days(of items: [Item], date: (Item) -> Date?) -> [Self] {
        let calendar = AppTime.calendar
        var days: [Self] = []
        for item in items {
            let start = date(item).map(calendar.startOfDay(for:)) ?? days.last?.start ?? .distantPast
            if let last = days.last, last.start == start {
                days[days.count - 1] = Self(start: start, items: last.items + [item])
            } else {
                days.append(Self(start: start, items: [item]))
            }
        }
        return days
    }
}
