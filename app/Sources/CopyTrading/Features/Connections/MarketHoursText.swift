import Foundation

/// Market hours as the owner reads them: hints say New York time, and add the owner's own clock
/// when their Mac is in another time zone.
enum MarketHoursText {
    private static let newYork = TimeZone(identifier: "America/New_York") ?? .gmt

    /// " Your time: 8:00–16:00." for New York ranges, or "" where the Mac keeps New York time.
    @MainActor
    static func yourTime(_ ranges: [(from: (Int, Int), to: (Int, Int))], now: Date = .now, zone: TimeZone = .current) -> String {
        guard zone.secondsFromGMT(for: now) != newYork.secondsFromGMT(for: now) else { return "" }
        let spans = ranges.map { "\(local($0.from, now: now, zone: zone))–\(local($0.to, now: now, zone: zone))" }
        return L10n.string(" Your time: %@.", ListFormatter.localizedString(byJoining: spans))
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
        let hour = local.component(.hour, from: date)
        let minute = local.component(.minute, from: date)
        return String(format: "%d:%02d", hour, minute)
    }
}
