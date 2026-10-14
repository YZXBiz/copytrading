import Foundation

/// Every guru's numbers for one day of the owner's, from its start up to its end.
public struct GuruDayStatsPage: Codable, Equatable, Sendable {
    public let dayStart: String
    public let dayEnd: String
    public let gurus: [GuruDayStats]
    public let unavailableAccounts: [AccountUnavailable]

    enum CodingKeys: String, CodingKey {
        case dayStart = "day_start"
        case dayEnd = "day_end"
        case gurus
        case unavailableAccounts = "unavailable_accounts"
    }
}
