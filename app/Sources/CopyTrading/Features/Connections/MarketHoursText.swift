import Foundation

/// Market hours as the owner reads them: New York time, followed in brackets by the same hours on
/// the owner's own clock, with its zone named, when their Mac keeps another time zone.
enum MarketHoursText {
    private static let newYork = TimeZone(identifier: "America/New_York") ?? .gmt

    /// "4:00–9:30 and 16:00–20:00 New York time (1:00–6:30 and 13:00–17:00 PT)", or without the
    /// brackets where the Mac keeps New York time.
    @MainActor
    static func hours(
        _ ranges: [(from: (Int, Int), to: (Int, Int))], now: Date = .now, zone: TimeZone = .current
    ) -> String {
        let newYorkSpans = ranges.map { "\(clock($0.from))–\(clock($0.to))" }
        let inNewYork = L10n.string("%@ New York time", L10n.list(newYorkSpans))
        guard zone.secondsFromGMT(for: now) != newYork.secondsFromGMT(for: now) else { return inNewYork }
        let localSpans = ranges.map { "\(local($0.from, now: now, zone: zone))–\(local($0.to, now: now, zone: zone))" }
        return "\(inNewYork) (\(L10n.list(localSpans)) \(zoneName(zone, at: now)))"
    }

    /// The owner's zone as people write it: "PT", "CET"; a GMT offset where there is no short name.
    private static func zoneName(_ zone: TimeZone, at date: Date) -> String {
        if let name = zone.localizedName(for: .shortGeneric, locale: .current), !name.hasPrefix("GMT") {
            return name
        }
        return zone.abbreviation(for: date) ?? zone.identifier
    }

    private static func clock(_ time: (Int, Int)) -> String {
        String(format: "%d:%02d", time.0, time.1)
    }

    private static func local(_ time: (Int, Int), now: Date, zone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = newYork
        var parts = calendar.dateComponents([.year, .month, .day], from: now)
        parts.hour = time.0
        parts.minute = time.1
        let date = calendar.date(from: parts) ?? now
        var local = Calendar(identifier: .gregorian)
        local.timeZone = zone
        return clock((local.component(.hour, from: date), local.component(.minute, from: date)))
    }
}
