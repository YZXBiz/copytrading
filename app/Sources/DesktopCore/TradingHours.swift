import Foundation

/// When a guru's calls can be copied: US stocks trade from 4:00 AM, before the open, to 8:00 PM
/// New York time after the close, Monday to Friday. Holidays are not counted.
public enum TradingHours {
    private static let newYork = TimeZone(identifier: "America/New_York")!

    public static func contains(_ date: Date) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = newYork
        let parts = calendar.dateComponents([.weekday, .hour], from: date)
        guard let weekday = parts.weekday, let hour = parts.hour else { return false }
        return (2...6).contains(weekday) && (4..<20).contains(hour)
    }
}
