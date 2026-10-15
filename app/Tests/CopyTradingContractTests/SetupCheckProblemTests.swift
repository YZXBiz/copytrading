import DesktopCore
import Foundation
import Testing

/// Setup Check names the account and the stocks a problem is about, offers the way forward, and
/// the changes bar counts exactly the rows that need attention.
@MainActor
func runSetupCheckProblemTests() throws {
    try aRemovedAccountsCheckDecodesItsStocks()
    try aRemovedAccountIsNamedWithWhatItHolds()
    try keepingARemovedAccountPutsItBackAsSaved()
    try keepingARenamedAccountUndoesTheRename()
    try openingTheAccountLeavesSetupCheck()
    try theChangesBarCountsTheRowsThatNeedAttention()
}

private func removedAccountCheck(
    _ reason: String, account: String = "primary", symbols: [String] = []
) -> TradingCapabilityCheck {
    TradingCapabilityCheck(
        name: .configuration, state: .failed, subject: account, adapter: "routing_revision", reasonCode: reason,
        symbols: symbols)
}

private func aRemovedAccountsCheckDecodesItsStocks() throws {
    let json = Data(
        """
        {"name":"configuration","state":"failed","subject":"primary","environment":null,"identity":null,\
        "adapter":"routing_revision","reason_code":"removed_account_holds_shares","suggestion":null,\
        "symbols":["GFS","NVDA","WMT"]}
        """.utf8)
    let check = try JSONDecoder().decode(TradingCapabilityCheck.self, from: json)
    try #require(check == removedAccountCheck("removed_account_holds_shares", symbols: ["GFS", "NVDA", "WMT"]))
}

@MainActor
private func aRemovedAccountIsNamedWithWhatItHolds() throws {
    let language = AppLanguagePreference.shared
    let original = language.language
    defer { language.select(original) }
    language.select(.english)

    let shares = ConnectionProblem.text(for: removedAccountCheck("removed_account_holds_shares", symbols: ["GFS", "NVDA", "WMT"]))
    try #require(
        shares
            == "primary still holds GFS, NVDA, and WMT that CopyTrading bought. Sell them from primary's page, or keep primary in the setup.",
        "a removed account's shares were not named: \(shares)")
    let one = ConnectionProblem.text(for: removedAccountCheck("removed_account_holds_shares", symbols: ["GFS"]))
    try #require(one.contains("holds GFS that") && one.contains("Sell it from"), "one stock read as many: \(one)")
    let many = ConnectionProblem.stocks(["A", "B", "C", "D", "E", "F"])
    try #require(many == "A, B, C, and 3 more", "a long list was not shortened: \(many)")
    for reason in ["removed_account_has_open_orders", "removed_account_needs_review", "removed_account_unreadable"] {
        let text = ConnectionProblem.text(for: removedAccountCheck(reason, symbols: ["AAPL"]))
        try #require(
            text.localizedCaseInsensitiveContains("keep primary in the setup"), "\(reason) gave no way forward: \(text)")
    }
    try #require(
        ConnectionProblem.text(for: removedAccountCheck("removed_account_has_open_orders", symbols: ["AAPL"])).contains("orders for AAPL"),
        "unfinished orders did not name their stock")
    try #require(CapabilityCheckTitle.text(for: removedAccountCheck("removed_account_holds_shares")) == "primary")

    // Every Configuration failure says what it is about, never the catch-all for a connection.
    let fallback = ConnectionProblem.text(for: removedAccountCheck("not_a_known_code"))
    for reason in [
        "removed_account_holds_shares", "removed_account_has_open_orders", "removed_account_needs_review",
        "removed_account_unreadable", "broker_keys_without_account", "routing_change_pending",
        "pause_before_configuration_change", "configuration_preflight_unavailable",
    ] {
        try #require(ConnectionProblem.text(for: removedAccountCheck(reason)) != fallback, "\(reason) has no words of its own")
    }

    language.select(.simplifiedChinese)
    let chinese = ConnectionProblem.text(for: removedAccountCheck("removed_account_holds_shares", symbols: ["GFS", "NVDA", "WMT"]))
    try #require(
        chinese.hasPrefix("primary 里还有 CopyTrading 买入的 GFS") && chinese.contains("请在 primary 的页面卖出"),
        "the Chinese text did not name the account and stocks: \(chinese)")
    try #require(CapabilityCheckTitle.text(for: TradingCapabilityCheck(name: .model, state: .ready, adapter: "deepseek")) == "AI 模型")
}

private func savedSetup() throws -> TradingConfiguration {
    let profile = try TradingProfileBuilder().build(TradingProfileDraft(guruID: "alex", displayName: "Alex"))
    let accounts = ["primary", "second"].map { TradingAccountConfiguration(id: $0, environment: .paper) }
    return TradingConfiguration(
        source: TradingSourceConfiguration(channelIDs: ["123"]),
        provider: TradingProviderConfiguration(name: .anthropic, model: "claude-sonnet-5-5"),
        accounts: accounts,
        profiles: [profile],
        routes: [
            TradingRouteConfiguration(
                channelID: "123", authorID: nil, guruID: "alex", profileRevision: profile.profileRevision,
                connections: [TradingRouteConnection(accountID: "primary", fullPositionUSD: accounts[0].policy.maxSymbolUSD)])
        ]
    )
}

@MainActor
private func modelShowingCheck(_ checks: [TradingCapabilityCheck]) throws -> AppModel {
    let model = AppModel()
    model.savedTradingConfiguration = try savedSetup()
    model.hasTradingSecrets = true
    model.syncSetupDraftWithSaved()
    model.tradingValidation = TradingValidation(
        report: TradingCapabilityReport(
            configurationRevision: "checked", activatable: checks.allSatisfy { $0.state != .failed }, checks: checks,
            costNotice: ""),
        activationToken: nil)
    model.isShowingSetupCheck = true
    return model
}

@MainActor
private func keepingARemovedAccountPutsItBackAsSaved() throws {
    let model = try modelShowingCheck([])
    model.removeAccount(named: "primary")
    try #require(model.hasUnsavedSetupChanges, "removing an account was not a change")
    model.tradingValidation = try modelShowingCheck([removedAccountCheck("removed_account_holds_shares", symbols: ["GFS"])])
        .tradingValidation
    model.isShowingSetupCheck = true

    model.keepAccount("primary")

    try #require(model.setupDraft.accounts.map(\.name) == ["primary", "second"], "primary did not come back where it was saved")
    try #require(!model.hasUnsavedSetupChanges, "keeping the only removed account left a change behind")
    try #require(model.tradingValidation == nil && !model.isShowingSetupCheck, "the check of the old setup stayed up")
    try #require(model.message == "primary is back in the setup.", "keeping said nothing: \(model.message ?? "nil")")
}

@MainActor
private func keepingARenamedAccountUndoesTheRename() throws {
    let model = try modelShowingCheck([])
    model.setupDraft.accounts[0].name = "main"
    model.renameAccountReferences(from: "primary", to: "main")

    model.keepAccount("primary")

    try #require(model.setupDraft.accounts.map(\.name) == ["primary", "second"], "the rename was not undone")
    try #require(
        model.setupDraft.routes[0].connection?.accountID == "primary", "the guru still copies into the new name")
    try #require(!model.hasUnsavedSetupChanges, "undoing the only rename left a change behind")
}

@MainActor
private func openingTheAccountLeavesSetupCheck() throws {
    let model = try modelShowingCheck([removedAccountCheck("removed_account_holds_shares", symbols: ["GFS"])])
    model.openAccountFromSetupCheck("primary")
    try #require(model.selectedScreen == .account("primary") && !model.isShowingSetupCheck, "primary's page did not open")
}

@MainActor
private func theChangesBarCountsTheRowsThatNeedAttention() throws {
    let model = try modelShowingCheck([
        TradingCapabilityCheck(name: .source, state: .ready, adapter: "discord"),
        removedAccountCheck("removed_account_holds_shares", symbols: ["GFS"]),
    ])
    try #require(model.setupCheckProblemCount == 1, "one failed row counted as \(model.setupCheckProblemCount)")
    model.tradingValidation?.report.checks.append(removedAccountCheck("removed_account_needs_review", account: "second"))
    try #require(model.setupCheckProblemCount == 2, "two failed rows counted as \(model.setupCheckProblemCount)")
}
