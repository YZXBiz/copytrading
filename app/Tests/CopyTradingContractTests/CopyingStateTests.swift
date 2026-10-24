import AppLocalizationCore
import CopyTradingTestSupport
import DesktopCore
import Foundation
import Testing

private let readinessCodes = [
    "enabled", "enabled_waiting_for_session", "enabled_coins_only", "paused", "disabled", "manual_resume_required",
    "recovery_pending", "reconciliation_unavailable", "session_unavailable", "processing_stopped",
    "inactive_evidence", "unavailable", "account_unavailable", "outside_open_orders", "broker_account_inactive",
    "account_in_use", "alpaca_account_shared", "record_unreadable", "broker_keys_rejected", "broker_unreachable",
]

private func account(readiness: String, entries: String, active: Bool = true) throws -> AccountOverview {
    let contracts = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appending(path: "Resources/Contracts")
    let response = try JSONDecoder().decode(
        EngineResponse.self, from: Data(contentsOf: contracts.appending(path: "account-overviews-response.json")))
    guard case .accounts(let page) = try response.successValue(), let first = page.items.first else {
        struct NoAccount: Error {}
        throw NoAccount()
    }
    var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(first)) as? [String: Any])
    json["readiness"] = readiness
    json["entry_permission"] = entries
    json["active_configuration"] = active
    return try JSONDecoder().decode(AccountOverview.self, from: JSONSerialization.data(withJSONObject: json))
}

/// Every state the engine can report for an account reads as exactly one of the five words, and
/// a problem or a held buy always says why.
@Test @MainActor func everyAccountStateIsOneOfFiveWords() throws {
    let states: [TradingRunState?] = [nil, .paused, .starting, .running, .degraded, .pausing, .failed]
    for state in states {
        let status = try state.map { try TradingStatusBuilder($0).build() }
        for readiness in readinessCodes {
            for entries in ["enabled", "paused", "disabled", "unknown"] {
                for active in [true, false] {
                    let copying = CopyingState.account(
                        try account(readiness: readiness, entries: entries, active: active), processing: status)
                    #expect(CopyingState.Word.allCases.contains(copying.word))
                    if copying.word == .stopped || copying.word == .sellsOnly {
                        #expect(copying.detail != nil, "\(readiness)/\(entries) gave \(copying.word) without a reason")
                    }
                    #expect(!copying.text.contains("_"), "an engine code leaked into \(copying.text)")
                }
            }
        }
    }
}

@Test @MainActor func eachWordMeansOneThing() throws {
    let running = try TradingStatusBuilder(.running).build()
    func word(_ readiness: String, _ entries: String) throws -> CopyingState.Word {
        CopyingState.account(try account(readiness: readiness, entries: entries), processing: running).word
    }
    #expect(try word("enabled", "enabled") == .copying)
    #expect(try word("paused", "paused") == .sellsOnly)
    #expect(try word("manual_resume_required", "enabled") == .sellsOnly)
    #expect(try word("broker_keys_rejected", "enabled") == .stopped)
    #expect(try word("disabled", "disabled") == .notStarted)
    #expect(try word("processing_stopped", "enabled") == .paused)
    #expect(
        CopyingState.account(try account(readiness: "enabled", entries: "enabled", active: false)).word == .notStarted)
    let paused = try TradingStatusBuilder(.paused).build()
    #expect(CopyingState.account(try account(readiness: "enabled", entries: "enabled"), processing: paused).word == .paused)
}

@Test @MainActor func copyingAsAWholeSaysSellsOnlyWhenEveryAccountHoldsItsBuys() throws {
    let running = try TradingStatusBuilder(.running).build()
    let held = [try account(readiness: "paused", entries: "paused")]
    #expect(CopyingState.overall(running, accounts: held).word == .sellsOnly)
    let mixed = held + [try account(readiness: "enabled", entries: "enabled")]
    #expect(CopyingState.overall(running, accounts: mixed) == CopyingState(.copying))
}

@Test @MainActor func theFiveWordsReadInBothLanguages() throws {
    let preference = AppLanguagePreference.shared
    let original = preference.language
    defer { preference.select(original) }
    preference.select(.english)
    #expect(
        CopyingState.Word.allCases.map { CopyingState($0).title } == [
            "Copying", "Sells only", "Paused", "Stopped", "Not started",
        ])
    preference.select(.simplifiedChinese)
    #expect(CopyingState.Word.allCases.map { CopyingState($0).title } == ["正在跟单", "只卖出", "已暂停", "已停止", "未开始"])
}
