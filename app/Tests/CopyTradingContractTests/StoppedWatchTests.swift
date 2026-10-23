import AppLocalizationCore
import CopyTradingTestSupport
import DesktopCore
import Foundation
import Testing

private func status(_ state: TradingRunState, _ accounts: [(String, String)]) throws -> TradingStatus {
    try accounts.reduce(TradingStatusBuilder(state)) { $0.account($1.0, $1.1) }.build()
}

/// An account that stops on its own is said once, however many reads see it stopped; one the owner
/// stopped, or that never opened, is not said.
@Test func anAccountThatStopsOnItsOwnIsSaidOnce() throws {
    var watch = StoppedWatch()
    #expect(try watch.stopped(in: status(.running, [("a", "running"), ("b", "running")])).isEmpty)

    let failed = try status(.degraded, [("a", "running"), ("b", "failed")])
    #expect(watch.stopped(in: failed) == ["b"], "the account that failed was not announced")
    #expect(watch.stopped(in: failed).isEmpty, "the same failure was announced on the next read")
    #expect(watch.stopped(in: failed).isEmpty)

    // It runs again after the owner restarts copying, and stopping again is news again.
    #expect(try watch.stopped(in: status(.running, [("a", "running"), ("b", "running")])).isEmpty)
    #expect(watch.stopped(in: failed) == ["b"], "a second failure was swallowed")
}

@Test func whatTheOwnerStoppedOrNeverOpenedIsNotAStop() throws {
    var watch = StoppedWatch()
    // Failed from the start: the owner was there when copying started.
    #expect(try watch.stopped(in: status(.degraded, [("a", "running"), ("b", "failed")])).isEmpty)
    // The app opening onto an account that was already failed says nothing either.
    #expect(try watch.stopped(in: status(.degraded, [("a", "running"), ("b", "failed")])).isEmpty)

    // Stop All: the accounts pause, nothing failed.
    #expect(try watch.stopped(in: status(.pausing, [("a", "running"), ("b", "failed")])).isEmpty)
    #expect(try watch.stopped(in: status(.paused, [("a", "paused"), ("b", "failed")])).isEmpty)
    #expect(try watch.stopped(in: status(.paused, [])).isEmpty)
}

@Test func aRunThatFailsStopsEveryAccountThatWasRunning() throws {
    var watch = StoppedWatch()
    _ = try watch.stopped(in: status(.running, [("a", "running"), ("b", "running"), ("c", "paused")]))
    let stopped = try watch.stopped(in: status(.failed, [("a", "paused"), ("b", "paused"), ("c", "paused")]))
    #expect(stopped == ["a", "b"], "a failed run announced \(stopped)")
}

@Test func losingTheEngineForgetsWhatWasRunning() throws {
    var watch = StoppedWatch()
    _ = try watch.stopped(in: status(.running, [("a", "running")]))
    #expect(watch.stopped(in: nil).isEmpty)
    // The engine is back with the account failed: nothing was seen running, so nothing stopped.
    #expect(try watch.stopped(in: status(.degraded, [("a", "failed")])).isEmpty)
}

/// The notification names the account and says what to do, in both languages, with no engine code.
@Test @MainActor func theStoppedNotificationNamesTheAccountInBothLanguages() {
    let preference = AppLanguagePreference.shared
    let original = preference.language
    defer { preference.select(original) }

    preference.select(.english)
    #expect(AccountStoppedText.title("zhap-account-2") == "Copying into zhap-account-2 stopped")
    #expect(AccountStoppedText.body == "CopyTrading hit a problem it couldn't fix. Stop copying everywhere, then start again to reopen it.")

    preference.select(.simplifiedChinese)
    #expect(AccountStoppedText.title("zhap-account-2") == "zhap-account-2 已停止跟单")
    #expect(AccountStoppedText.body == "CopyTrading 遇到无法自行解决的问题。先停止所有跟单，再重新开始，即可重新打开该账户。")
    for text in [AccountStoppedText.title("a"), AccountStoppedText.body] {
        #expect(!text.contains("_"), "an engine code leaked into \(text)")
    }
}

private func account(readiness: String, active: Bool = true) throws -> AccountOverview {
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
    json["active_configuration"] = active
    return try JSONDecoder().decode(AccountOverview.self, from: JSONSerialization.data(withJSONObject: json))
}

/// The sidebar and the menu bar call an account stopped when the engine could not keep it running,
/// and never when the owner stopped it or it is simply off.
@Test @MainActor func onlyAnAccountTheEngineCouldNotKeepIsStopped() throws {
    for readiness in ["account_unavailable", "outside_open_orders", "broker_account_inactive", "account_in_use"] {
        #expect(CopyingState.isStopped(try account(readiness: readiness)), "\(readiness) was not called stopped")
    }
    for readiness in ["enabled", "enabled_waiting_for_session", "manual_resume_required", "processing_stopped", "disabled"] {
        #expect(!CopyingState.isStopped(try account(readiness: readiness)), "\(readiness) was called stopped")
    }
    #expect(!CopyingState.isStopped(try account(readiness: "account_unavailable", active: false)))
}
