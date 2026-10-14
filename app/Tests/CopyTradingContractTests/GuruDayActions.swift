import CopyTradingTestSupport
import DesktopCore
import Foundation

/// The engine on a busy day: one page of posts loaded, and each guru's whole day counted, read from
/// the shared wire fixtures. Records the day the app asked about.
actor GuruDayActions: AccountOperations {
    private(set) var window: (start: Date, end: Date)?

    func accounts(beforeAccountID: String?, limit: Int) throws -> AccountOverviewPage {
        guard case .accounts(let page) = try response("account-overviews-response.json") else {
            throw EngineContractError.missingResult
        }
        return page
    }

    func sourceActivity(beforeSeq: Int?, limit: Int) throws -> SourceActivityPage {
        guard case .sourceActivity(let page) = try response("source-activity-response.json") else {
            throw EngineContractError.missingResult
        }
        return page
    }

    func guruDayStats(dayStart: Date, dayEnd: Date) throws -> GuruDayStatsPage {
        window = (dayStart, dayEnd)
        guard case .guruDayStats(let page) = try response("guru-day-stats-response.json") else {
            throw EngineContractError.missingResult
        }
        return page
    }

    func accountFeed(accountID: String, beforeSeq: Int?, limit: Int) throws -> AccountFeedPage {
        throw EngineContractError.missingResult
    }

    func controlAccount(_ command: AccountControlCommand) throws -> AccountControlResult {
        throw EngineContractError.missingResult
    }

    func equityHistory(accountID: String, window: EquityHistoryWindow) throws -> EquityHistory? { nil }

    func resolveOwnership(accountID: String, resolution: OwnershipResolutionRequest) throws -> OwnershipResolution {
        throw EngineContractError.missingResult
    }

    private func response(_ name: String) throws -> EngineResult {
        let contracts = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "Resources/Contracts")
        return try JSONDecoder().decode(EngineResponse.self, from: Data(contentsOf: contracts.appending(path: name)))
            .successValue()
    }
}
