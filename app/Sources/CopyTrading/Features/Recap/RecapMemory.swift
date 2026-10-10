import DesktopCore
import Foundation

/// When the owner last looked at their accounts and what each was worth then, kept on this Mac so
/// the next open after a long while can say what changed.
enum RecapMemory {
    private static let seenKey = "recap.lastSeen"
    private static let equitiesKey = "recap.equities"
    /// Away at least this long before a recap is worth showing.
    static let awayLongEnough: TimeInterval = 6 * 60 * 60

    static var lastSeen: Date? {
        UserDefaults.standard.object(forKey: seenKey) as? Date
    }

    static var equities: [String: Decimal] {
        let stored = UserDefaults.standard.dictionary(forKey: equitiesKey) as? [String: String] ?? [:]
        return stored.compactMapValues { Decimal(string: $0) }
    }

    static func record(_ accounts: [AccountOverview], at now: Date = .now) {
        var values: [String: String] = [:]
        for account in accounts {
            if let equity = account.balance?.equity { values[account.accountID] = equity }
        }
        UserDefaults.standard.set(now, forKey: seenKey)
        UserDefaults.standard.set(values, forKey: equitiesKey)
    }
}
