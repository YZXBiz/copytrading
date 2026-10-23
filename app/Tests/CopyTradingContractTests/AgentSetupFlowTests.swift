import CopyTradingTestSupport
import DesktopCore
import Foundation

/// `copytrading setup …` through the app: the CLI's requests edit the draft Connections edits,
/// `setup apply` is Start Copying on it, keys go only to the Keychain, and anything that touches a
/// live account waits for the owner.
@MainActor
func runAgentSetupFlowTests() async throws {
    try await setupEditsTheDraftAndNeverEchoesAKey()
    try await editsThatCannotWorkSayWhoAndWhatToDo()
    try await applyRunsStartCopyingsChecksAndSaves()
    try await applyWhileCopyingStartsItAgain()
    try await aLiveSetupWaitsForTheOwnerAndAppliesWhatTheySaw()
    try await anEditWhileTheEngineDecidesIsNeverApproved()
    try await aSheetNeverSavesAnAgentsLiveLimits()
    try await aSavedModelKeyNeverGoesToANewAddress()
    try await anApplyDuringAStartSaysSo()
    try await aSetupNotReadyNamesWhatToFix()
    try await engineFailuresSayWhatHappened()
    try await liveFactsMatchTheSharedCases()
    try await startOnAPaperFirstSetupStartsCopying()
    try await startWithALiveAccountWaitsForTheOwner()
    try await startResumesPausedCopying()
    try await applyingTheSameSetupTwiceSavesAndStartsOnce()
    try await setupChangesNeedTheOwnerToTurnThemOn()
    try await aLineTheAppCannotReadIsStillRecorded()
    try await aLockedAppChangesNothing()
    try await aGuruIsTheirChannel()
    try await afterARestartIsAnAccountSetting()
    try await aSavedSetupFileIsUpgradedOrRefusedByItsVersion()
    print("CopyTradingContractTests: the CLI's setup edits the draft, applies with Start Copying, and live waits for the owner")
}

private struct SetupFlowFailure: Error, CustomStringConvertible {
    let description: String
}

private func verify(_ condition: Bool, _ message: String) throws {
    guard condition else { throw SetupFlowFailure(description: message) }
}

private let savedSecrets = TradingSecrets(
    discordToken: "saved-discord-token", providerAPIKey: "saved-model-key",
    brokers: [TradingBrokerCredentials(accountID: "paper", key: "saved-alpaca-key", secret: "saved-alpaca-secret")])

/// The engine's side: setup requests run unless they touch a live account, which become a
/// proposal; approving one leaves it running for the app to apply and report.
private actor SetupEngine: AgentProposalOperations {
    private(set) var asked: [String] = []
    private(set) var completed: [(String, Bool, String?)] = []
    private var subject = ""
    /// Runs while the engine decides, as an edit in the window could.
    private var whileDeciding: (@Sendable () async -> Void)?
    private var failure: (any Error)?

    func setWhileDeciding(_ hook: (@Sendable () async -> Void)?) { whileDeciding = hook }
    func setFailure(_ error: (any Error)?) { failure = error }

    func authorizeSetup(
        _ setup: AgentSetupAuthorizationRequest, context: AgentRequestContext
    ) async throws -> AgentSetupAuthorization {
        if let failure { throw failure }
        asked.append(String(decoding: try JSONEncoder().encode(setup), as: UTF8.self))
        await whileDeciding?()
        guard let facts = setup.apply, facts.touchesLive else { return .allowed }
        subject = String(decoding: try JSONEncoder().encode(facts), as: UTF8.self)
        return .answered(line: proposalLine(state: "pending", requestID: setup.requestID))
    }

    private func proposalLine(state: String, requestID: String = "") -> String {
        let facts = subject.dropFirst().dropLast()
        return """
            {"schema_version":1,"request_id":"\(requestID)","ok":{"type":"proposal","proposal_id":"p-0123456789ab",\
            "state":"\(state)","subject":{"kind":"apply_setup",\(facts)},"digest":"\(String(repeating: "a", count: 64))",\
            "command_id":"agent-1","created_at":"2026-10-23T15:00:00Z","expires_at":"2026-10-23T15:05:00Z",\
            "requested_by":{"pid":4242,"path":"/usr/bin/agent"},"outcome":null}}
            """
    }

    private func proposal(_ state: String) throws -> AgentProposal {
        let line = proposalLine(state: state)
        let object = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
        let ok = try JSONSerialization.data(withJSONObject: object?["ok"] ?? [:])
        return try JSONDecoder().decode(AgentProposal.self, from: ok)
    }

    func agentProposals() async throws -> [AgentProposal] { subject.isEmpty ? [] : [try proposal("pending")] }
    func approveProposal(id: String, digest: String) async throws -> AgentProposal { try proposal("running") }
    func completeProposal(id: String, succeeded: Bool, code: String?) async throws -> AgentProposal {
        completed.append((id, succeeded, code))
        return try proposal(succeeded ? "succeeded" : "failed")
    }
    func rejectProposal(id: String) async throws -> AgentProposal { try proposal("rejected") }
    func discardProposals() async throws -> Int { 0 }
}

private struct Fixture {
    let model: AppModel
    let starter: RecordingTradingStarter
    let engine: SetupEngine
    let store: TradingConfigurationStore
    let owner: OwnerAnswers
    let directory: URL
}

/// A saved setup: accounts by name and environment, gurus by name, channel, and the account they
/// copy into. Each guru takes the ID their channel gives them, as every saved setup does.
@MainActor
private func savedSetup(
    accounts: [(String, TradingEnvironment, String)] = [("paper", .paper, "100")],
    recovery: [String: RecoveryPreference] = [:],
    gurus: [(String, String, String)] = [("Launch Guru", "123", "paper")],
    provider: TradingProviderConfiguration = TradingProviderConfiguration(name: .anthropic, model: "launch-model")
) throws -> (TradingConfiguration, TradingSecrets) {
    let profiles = try gurus.map {
        try TradingProfileBuilder().build(
            TradingProfileDraft(guruID: GuruIdentity.id(channelID: $0.1), displayName: $0.0))
    }
    var channels = ["123"]
    for guru in gurus where !channels.contains(guru.1) { channels.append(guru.1) }
    let configuration = TradingConfiguration(
        source: TradingSourceConfiguration(channelIDs: channels, authorIDs: ["456"]),
        provider: provider,
        accounts: accounts.map {
            var policy = TradingAccountPolicy()
            policy.maxOrderUSD = $0.2
            policy.recoveryPreference = recovery[$0.0] ?? .manual
            return TradingAccountConfiguration(id: $0.0, environment: $0.1, policy: policy)
        },
        profiles: profiles,
        routes: zip(gurus, profiles).map { guru, profile in
            TradingRouteConfiguration(
                channelID: guru.1, authorID: "456", guruID: profile.guruID, profileRevision: profile.profileRevision,
                connections: [TradingRouteConnection(accountID: guru.2, fullPositionUSD: "600")])
        })
    let secrets = TradingSecrets(
        discordToken: savedSecrets.discordToken, providerAPIKey: savedSecrets.providerAPIKey,
        brokers: accounts.map {
            TradingBrokerCredentials(
                accountID: $0.0, key: $0.0 == "paper" ? "saved-alpaca-key" : "saved-key-\($0.0)",
                secret: $0.0 == "paper" ? "saved-alpaca-secret" : "saved-secret-\($0.0)")
        })
    return (configuration, secrets)
}

@MainActor
private func fixture(
    ownerConfirms: Bool = true, setup: (TradingConfiguration, TradingSecrets)? = nil
) async throws -> Fixture {
    let directory = FileManager.default.temporaryDirectory.appending(
        path: "agent-setup-\(UUID().uuidString)", directoryHint: .isDirectory)
    let store = TradingConfigurationStore(url: directory.appending(path: "configuration.json"), secrets: TestSecretRevisions())
    let (configuration, secrets) = try setup ?? savedSetup()
    try store.save(configuration: configuration, revision: fakeEngineRevision(configuration), secrets: secrets, when: .paused)
    let starter = RecordingTradingStarter()
    let engine = SetupEngine()
    let owner = OwnerAnswers(confirms: ownerConfirms)
    let model = AppModel(
        tradingConfigurationStore: store, tradingStarter: starter, appUnlock: try await unlocked(by: owner),
        agentProposalOperations: engine)
    model.isTradingUnlocked = true
    model.tradingStatus = try TradingStatusBuilder(.paused).build()
    model.savedTradingConfiguration = configuration
    model.hasTradingSecrets = true
    model.syncSetupDraftWithSaved()
    return Fixture(model: model, starter: starter, engine: engine, store: store, owner: owner, directory: directory)
}

private let context = AgentRequestContext(
    accessLevel: .propose, unlocked: true, callerPID: 4242, callerPath: "/usr/bin/agent", setupChanges: true)

@MainActor
private func send(_ model: AppModel, _ fields: [String: Any]) async throws -> [String: Any] {
    var request: [String: Any] = ["schema_version": 1, "request_id": "r-\(UUID().uuidString.prefix(8))"]
    request.merge(fields) { _, new in new }
    let line = String(decoding: try JSONSerialization.data(withJSONObject: request), as: UTF8.self)
    let answer = await model.answerAgentSetup(line: line, context: context)
    for secret in [
        "saved-discord-token", "saved-model-key", "saved-alpaca-key", "saved-alpaca-secret", "typed-discord-token",
        "typed-alpaca-key", "typed-alpaca-secret",
    ] {
        try verify(!answer.contains(secret), "a setup answer showed a key: \(answer)")
    }
    let object = try JSONSerialization.jsonObject(with: Data(answer.utf8)) as? [String: Any]
    try verify(object?["request_id"] as? String == request["request_id"] as? String, "the answer lost its request ID")
    return object ?? [:]
}

private func ok(_ answer: [String: Any]) throws -> [String: Any] {
    guard let ok = answer["ok"] as? [String: Any] else {
        throw SetupFlowFailure(description: "the request failed: \(answer)")
    }
    return ok
}

private func error(_ answer: [String: Any]) throws -> (code: String, message: String) {
    guard let error = answer["error"] as? [String: Any], let code = error["code"] as? String,
        let message = error["message"] as? String
    else { throw SetupFlowFailure(description: "the request did not fail: \(answer)") }
    return (code, message)
}

@MainActor
private func setupEditsTheDraftAndNeverEchoesAKey() async throws {
    let setup = try await fixture()
    defer { try? FileManager.default.removeItem(at: setup.directory) }
    let model = setup.model

    let shown = try ok(try await send(model, ["operation": "get_setup"]))
    let discord = shown["discord"] as? [String: Any]
    let accounts = shown["accounts"] as? [[String: Any]]
    try verify(
        shown["type"] as? String == "setup" && discord?["token"] as? String == "saved"
            && accounts?.first?["keys"] as? String == "saved" && (shown["model"] as? [String: Any])?["key"] as? String == "saved",
        "show did not read the saved keys as saved: \(shown)")
    try verify(shown["unsaved_changes"] as? Bool == false, "a fresh setup read as changed")

    let edited = try ok(
        try await send(
            model,
            ["operation": "edit_setup_discord", "channel_ids": ["123", "789"], "author_ids": [], "token": "typed-discord-token"]))
    try verify(
        model.setupDraft.discordToken == "typed-discord-token" && model.setupDraft.sourceChannelIDs == ["123", "789"]
            && model.setupDraft.authors.isEmpty,
        "the Discord edit did not reach the draft")
    try verify(
        (edited["discord"] as? [String: Any])?["token"] as? String == "entered" && edited["unsaved_changes"] as? Bool == true,
        "a typed token did not read as entered: \(edited)")

    _ = try ok(
        try await send(
            model,
            [
                "operation": "edit_setup_account", "action": "add", "account_id": "paper-2", "key": "typed-alpaca-key",
                "secret": "typed-alpaca-secret", "limits": [["field": "max_order_usd", "value": "250"]],
            ]))
    let added = model.setupDraft.accounts.first { $0.name == "paper-2" }
    try verify(
        added?.key == "typed-alpaca-key" && added?.secret == "typed-alpaca-secret" && added?.policy.maxOrderUSD == "250"
            && added?.environment == .paper,
        "the new account did not reach the draft as asked")

    let guru = try ok(
        try await send(
            model,
            [
                "operation": "edit_setup_guru", "action": "add", "guru": "Bea", "account_id": "paper-2",
                "channel_id": "789", "full_position_usd": "900", "repeat_window_minutes": 0,
            ]))
    let bea = model.setupDraft.routes.first { $0.displayName == "Bea" }
    try verify(
        bea?.connection?.accountID == "paper-2" && bea?.repeatWindowMinutes == nil
            && bea?.connection?.fullPositionUSD == "900"
            && model.setupDraft.policy(of: "paper-2")?.maxSymbolUSD == TradingAccountPolicy().maxSymbolUSD,
        "the new guru did not copy into paper-2 with their own full position, leaving its maximum per stock")
    try verify(
        (guru["gurus"] as? [[String: Any]])?.contains {
            $0["name"] as? String == "Bea" && $0["guru_id"] as? String == GuruIdentity.id(channelID: "789")
        } == true,
        "the new guru did not take the ID their channel gives them: \(guru)")

    _ = try ok(try await send(model, ["operation": "edit_setup_model", "service": "deepseek", "key": "typed-model-key"]))
    try verify(
        model.setupDraft.provider == .deepseek && !model.setupDraft.modelName.isEmpty
            && model.setupDraft.providerAPIKey == "typed-model-key",
        "a new model service did not take its suggested model and key")

    _ = try ok(
        try await send(model, ["operation": "edit_setup_alerts", "enabled": true, "service": "discord", "token": "https://hook"]))
    try verify(
        model.setupDraft.notificationsEnabled && model.setupDraft.notificationService == .discord,
        "alerts did not turn on")

    let imported = try ok(
        try await send(model, ["operation": "import_setup", "text": "Discord token:\ntyped-discord-token\nGuru: Cy\n"]))
    try verify(
        imported["type"] as? String == "setup_imported" && (imported["filled"] as? [String])?.isEmpty == false,
        "an import did not list what it filled: \(imported)")

    _ = try ok(try await send(model, ["operation": "edit_setup_guru", "action": "remove", "guru": "Bea"]))
    try verify(!model.setupDraft.routes.contains { $0.displayName == "Bea" }, "a removed guru stayed")

    let discarded = try ok(try await send(model, ["operation": "discard_setup"]))
    try verify(
        discarded["unsaved_changes"] as? Bool == false && !model.setupDraft.hasTypedSecrets
            && model.setupDraft.accounts.map(\.name) == ["paper"],
        "discard did not drop the unsaved changes: \(discarded)")

    let asked = await setup.engine.asked
    try verify(asked.count == 9, "every setup request must be authorized by the engine, saw \(asked.count)")
    try verify(
        !asked.contains { $0.contains("typed-") || $0.contains("hook") }, "a key was sent to the engine: \(asked)")
}

@MainActor
private func editsThatCannotWorkSayWhoAndWhatToDo() async throws {
    let setup = try await fixture()
    defer { try? FileManager.default.removeItem(at: setup.directory) }
    let model = setup.model
    let missing = try error(
        try await send(model, ["operation": "edit_setup_account", "action": "edit", "account_id": "paper-9", "environment": "live"]))
    try verify(
        missing.code == "not_found" && missing.message.contains("paper-9")
            && missing.message.contains("copytrading setup account add paper-9"),
        "an unknown account was refused as \(missing)")
    let taken = try error(
        try await send(model, ["operation": "edit_setup_guru", "action": "add", "guru": "Cy", "account_id": "paper"]))
    try verify(
        taken.code == "conflict" && taken.message.contains("paper already copies Launch Guru"),
        "a taken account was refused as \(taken)")
    let twice = try error(try await send(model, ["operation": "edit_setup_account", "action": "add", "account_id": "paper"]))
    try verify(twice.code == "conflict" && twice.message.contains("already in the setup"), "a second paper was \(twice)")
    let bad = try error(
        try await send(
            model,
            [
                "operation": "edit_setup_account", "action": "edit", "account_id": "paper",
                "limits": [["field": "max_order_usd", "value": "lots"]],
            ]))
    try verify(bad.code == "invalid_request" && bad.message == "paper: max_order_usd takes a number.", "a bad limit was \(bad)")
    let fixed = try error(try await send(model, ["operation": "edit_setup_model", "base_url": "https://example.com"]))
    try verify(fixed.message.contains("fixed address"), "a base URL for a hosted service was \(fixed)")
    let invalid = try error(try await send(model, ["operation": "edit_setup_discord", "channel_ids": ["general"]]))
    try verify(invalid.code == "invalid_request" && invalid.message.contains("digits"), "a named channel was \(invalid)")
    try verify(!model.hasUnsavedSetupChanges, "a refused edit changed the draft")
}

@MainActor
private func applyRunsStartCopyingsChecksAndSaves() async throws {
    let setup = try await fixture()
    defer { try? FileManager.default.removeItem(at: setup.directory) }
    let model = setup.model
    model.setStartsCopying(true)
    _ = try ok(
        try await send(
            model,
            [
                "operation": "edit_setup_account", "action": "add", "account_id": "paper-2", "key": "typed-alpaca-key",
                "secret": "typed-alpaca-secret",
            ]))

    await setup.starter.setValidationActivatable(false)
    let failed = try ok(try await send(model, ["operation": "apply_setup"]))
    let checks = failed["checks"] as? [[String: Any]] ?? []
    try verify(failed["status"] as? String == "failed_checks", "a failed check was not reported: \(failed)")
    try verify(
        checks.contains {
            $0["state"] as? String == "failed" && ($0["message"] as? String)?.hasPrefix("Interpreter: ") == true
        },
        "the failed check did not say which connection and what to do: \(checks)")
    try verify(
        model.savedTradingConfiguration?.accounts.map(\.id) == ["paper"], "a failed check saved the setup")

    await setup.starter.setValidationActivatable(true)
    let applied = try ok(try await send(model, ["operation": "apply_setup"]))
    try verify(applied["status"] as? String == "applied", "a passing apply did not save: \(applied)")
    try verify(
        applied["message"] as? String == "Saved. Copying stays paused, as you left it.",
        "a paused apply did not say copying stays paused: \(applied)")
    try verify(
        model.savedTradingConfiguration?.accounts.map(\.id) == ["paper", "paper-2"] && model.tradingStatus?.state == .paused,
        "the applied setup is not saved, or copying the owner paused started")
    let events = await setup.starter.events()
    try verify(!events.contains("start"), "an apply while copying was paused started copying: \(events)")
    let saved = try setup.store.load()
    try verify(
        saved?.secrets.brokers.contains { $0.accountID == "paper-2" && $0.key == "typed-alpaca-key" } == true,
        "the new account's keys did not reach the Keychain")
    let unchanged = try ok(try await send(model, ["operation": "apply_setup"]))
    try verify(
        unchanged["status"] as? String == "unchanged" && model.tradingStatus?.state == .paused,
        "applying a saved, paused setup was \(unchanged)")
}

@MainActor
private func applyWhileCopyingStartsItAgain() async throws {
    let setup = try await fixture()
    defer { try? FileManager.default.removeItem(at: setup.directory) }
    let model = setup.model
    await model.startTrading()
    try verify(model.tradingStatus?.state == .running, "the fixture did not start copying: \(model.message ?? "")")
    _ = try ok(
        try await send(
            model,
            [
                "operation": "edit_setup_account", "action": "edit", "account_id": "paper",
                "limits": [["field": "max_order_usd", "value": "250"]],
            ]
        ))
    let limits = try ok(try await send(model, ["operation": "apply_setup"]))
    try verify(
        limits["status"] as? String == "applied" && model.savedTradingConfiguration?.accounts[0].policy.maxOrderUSD == "250",
        "limits alone did not save while copying: \(limits)")
    let events = await setup.starter.events()
    try verify(events.last == "update_limits", "limits alone did more than update the limits: \(events)")
    _ = try ok(try await send(model, ["operation": "edit_setup_discord", "channel_ids": ["123", "789"]]))
    let restarted = try ok(try await send(model, ["operation": "apply_setup"]))
    try verify(
        restarted["status"] as? String == "applied" && model.tradingStatus?.state == .running
            && model.savedTradingConfiguration?.source.channelIDs == ["123", "789"],
        "a change while copying did not apply and keep copying: \(restarted) \(model.message ?? "")")
}

@MainActor
private func aLiveSetupWaitsForTheOwnerAndAppliesWhatTheySaw() async throws {
    let setup = try await fixture()
    defer { try? FileManager.default.removeItem(at: setup.directory) }
    let model = setup.model
    _ = try ok(
        try await send(
            model,
            [
                "operation": "edit_setup_account", "action": "edit", "account_id": "paper", "environment": "live",
                "key": "typed-alpaca-key", "secret": "typed-alpaca-secret",
            ]))
    let shown = model.setupDraft.signature
    let proposed = try ok(try await send(model, ["operation": "apply_setup"]))
    let subject = proposed["subject"] as? [String: Any]
    try verify(
        proposed["type"] as? String == "proposal" && subject?["made_live"] as? [String] == ["paper"]
            && subject?["new_live_keys"] as? [String] == ["paper"] && subject?["starts_live"] as? [String] == [],
        "making an account live did not wait for the owner: \(proposed)")
    let events = await setup.starter.events()
    try verify(!events.contains("validate"), "a live apply ran before the owner approved")
    try verify(
        model.agentSetupProposals["p-0123456789ab"]?.signature == shown,
        "the app did not keep the setup as it was when the engine was asked")
    guard let pending = model.pendingAgentProposal else {
        throw SetupFlowFailure(description: "the approval sheet has no request to show")
    }
    try verify(model.environment(of: pending) == .live, "a live setup's sheet did not say Live")
    try verify(
        model.setupRows(of: pending).map(\.title) == ["Becomes live", "New keys"],
        "the sheet did not list what the setup does: \(model.setupRows(of: pending))")

    // An edit after the request is never applied by approving it.
    model.setupDraft.accounts[0].policy.maxOrderUSD = "999"
    let changed = await model.applyApprovedAgentSetup(proposalID: "p-0123456789ab")
    try verify(changed == "setup_changed", "a setup edited after the request was applied: \(changed ?? "nil")")
    model.setupDraft.accounts[0].policy.maxOrderUSD = "100"

    model.setStartsCopying(true)
    _ = try ok(try await send(model, ["operation": "apply_setup"]))
    guard let again = model.pendingAgentProposal else { throw SetupFlowFailure(description: "no second request") }
    await model.approveAgentProposal(again)
    let completed = await setup.engine.completed
    try verify(
        completed.count == 1 && completed[0].1, "the approved apply did not report success: \(completed) \(model.message ?? "")")
    try verify(
        model.savedTradingConfiguration?.accounts.first?.environment == .live && model.tradingStatus?.state == .paused,
        "the approved live setup is not saved, or copying the owner paused started")
    let confirmations = await setup.owner.confirmations
    try verify(confirmations == 1, "approving did not ask the owner exactly once: \(confirmations)")
}

@MainActor
private func anEditWhileTheEngineDecidesIsNeverApproved() async throws {
    let setup = try await fixture()
    defer { try? FileManager.default.removeItem(at: setup.directory) }
    let model = setup.model
    _ = try ok(
        try await send(
            model,
            [
                "operation": "edit_setup_account", "action": "add", "account_id": "paper-2", "key": "typed-alpaca-key",
                "secret": "typed-alpaca-secret",
            ]))
    await setup.engine.setWhileDeciding { @MainActor in model.setupDraft.accounts[0].policy.maxOrderUSD = "9999" }
    let raced = try error(try await send(model, ["operation": "apply_setup"]))
    try verify(raced.code == "conflict" && raced.message.contains("changed"), "a paper apply raced an edit: \(raced)")
    try verify(model.savedTradingConfiguration?.accounts.count == 1, "a raced apply saved")

    model.setupDraft.accounts[0].policy.maxOrderUSD = "100"
    model.setupDraft.accounts[1].environment = .live
    await setup.engine.setWhileDeciding { @MainActor in model.setupDraft.accounts[1].policy.maxOrderUSD = "9999" }
    _ = try ok(try await send(model, ["operation": "apply_setup"]))
    await setup.engine.setWhileDeciding(nil)
    let approved = await model.applyApprovedAgentSetup(proposalID: "p-0123456789ab")
    try verify(approved == "setup_changed", "an edit made while the engine decided was approved: \(approved ?? "applied")")
    try verify(model.savedTradingConfiguration?.accounts.count == 1, "the raced live setup was saved")
}

@MainActor
private func aSheetNeverSavesAnAgentsLiveLimits() async throws {
    let setup = try await fixture(
        setup: try savedSetup(accounts: [("paper", .paper, "100"), ("live-main", .live, "100")]))
    defer { try? FileManager.default.removeItem(at: setup.directory) }
    let model = setup.model
    _ = try ok(
        try await send(
            model,
            [
                "operation": "edit_setup_account", "action": "edit", "account_id": "live-main",
                "limits": [["field": "max_order_usd", "value": "50000"]],
            ]
        ))
    // The owner then edits the paper account's limits and closes its sheet.
    model.setupDraft.accounts[0].policy.maxOrderUSD = "300"
    let paper = await model.saveLimitOnlyChanges(for: ["paper"])
    let saved = model.savedTradingConfiguration?.accounts
    try verify(paper == true && saved?[0].policy.maxOrderUSD == "300", "the paper sheet did not save its own limits")
    try verify(saved?[1].policy.maxOrderUSD == "100", "a paper sheet saved the agent's live limits: \(saved?[1].policy.maxOrderUSD ?? "")")
    let live = await model.saveLimitOnlyChanges(for: ["live-main"])
    try verify(
        live == nil && model.savedTradingConfiguration?.accounts[1].policy.maxOrderUSD == "100", "the live sheet saved the agent's limits")
    try verify(!model.hasOnlyLimitChanges, "the agent's live limits read as limits that save on their own")
    model.limitsAwaitingStart = true
    model.limitsAwaitingAccountIDs = ["paper"]
    await model.saveLimitsAwaitingStart()
    try verify(model.savedTradingConfiguration?.accounts[1].policy.maxOrderUSD == "100", "a settled start saved the agent's live limits")
    let proposed = try ok(try await send(model, ["operation": "apply_setup"]))
    try verify(
        proposed["type"] as? String == "proposal" && (proposed["subject"] as? [String: Any])?["changed_live"] as? [String] == ["live-main"],
        "the agent's live limits did not wait for the owner: \(proposed)")
}

@MainActor
private func aSavedModelKeyNeverGoesToANewAddress() async throws {
    let setup = try await fixture(
        setup: try savedSetup(
            provider: TradingProviderConfiguration(name: .openAICompatible, model: "own-model", baseURL: "https://models.example.com/v1")))
    defer { try? FileManager.default.removeItem(at: setup.directory) }
    let model = setup.model
    let moved = try error(try await send(model, ["operation": "edit_setup_model", "base_url": "https://elsewhere.example.net/v1"]))
    try verify(
        moved.code == "invalid_request" && moved.message.contains("never sent to a new address"),
        "a new address took the saved key: \(moved)")
    try verify(model.setupDraft.providerBaseURL == "https://models.example.com/v1", "a refused address reached the draft")
    _ = try ok(
        try await send(model, ["operation": "edit_setup_model", "base_url": "https://elsewhere.example.net/v1", "key": "typed-model-key"]))
    try verify(model.setupDraft.providerAPIKey == "typed-model-key", "a new address with its own key was refused")
    // Moved some other way, an apply still never sends the saved key there.
    model.setupDraft.providerAPIKey = ""
    let applied = try ok(try await send(model, ["operation": "apply_setup"]))
    try verify(
        applied["status"] as? String == "failed" && (applied["message"] as? String)?.contains("never sent to a new address") == true,
        "an apply sent the saved key to a new address: \(applied)")
    let validations = await setup.starter.validationCallCount()
    try verify(validations == 0, "the saved key was checked against the new address")
}

@MainActor
private func anApplyDuringAStartSaysSo() async throws {
    let setup = try await fixture()
    defer { try? FileManager.default.removeItem(at: setup.directory) }
    let model = setup.model
    await model.startTrading()
    _ = try ok(
        try await send(
            model,
            [
                "operation": "edit_setup_account", "action": "edit", "account_id": "paper",
                "limits": [["field": "max_order_usd", "value": "250"]],
            ]
        ))
    guard let saved = model.savedTradingConfiguration else { throw SetupFlowFailure(description: "nothing saved") }
    try setup.store.stageValidatedActivation(
        configuration: saved, revision: fakeEngineRevision(saved), secrets: savedSecrets,
        activationID: UUID().uuidString.lowercased(), when: .paused)
    let settling = try ok(try await send(model, ["operation": "apply_setup"]))
    try verify(
        settling["status"] as? String == "failed" && (settling["message"] as? String)?.contains("still settling") == true,
        "an apply during a start read as \(settling)")
}

@MainActor
private func aSetupNotReadyNamesWhatToFix() async throws {
    let setup = try await fixture()
    defer { try? FileManager.default.removeItem(at: setup.directory) }
    let model = setup.model
    _ = try ok(
        try await send(model, ["operation": "edit_setup_account", "action": "edit", "account_id": "paper", "rename": "paper-x"]))
    let notReady = try ok(try await send(model, ["operation": "apply_setup"]))
    let message = notReady["message"] as? String ?? ""
    try verify(
        message.contains("paper-x has no Alpaca keys (renamed from paper, whose keys stay with that name)")
            && message.contains("`copytrading setup account edit paper-x --secret-stdin`"),
        "a renamed account's missing keys were not named with the command: \(message)")
}

@MainActor
private func engineFailuresSayWhatHappened() async throws {
    let setup = try await fixture()
    defer { try? FileManager.default.removeItem(at: setup.directory) }
    await setup.engine.setFailure(EngineTransportError.requestTimedOut)
    let slow = try error(try await send(setup.model, ["operation": "get_setup"]))
    try verify(slow.code == "unavailable" && slow.message.contains("didn't answer in time"), "a timeout read as \(slow)")
    await setup.engine.setFailure(EngineContractError.missingResult)
    let garbled = try error(try await send(setup.model, ["operation": "get_setup"]))
    try verify(garbled.message.contains("can't read"), "an unreadable answer read as \(garbled)")
}

private struct FactsCase: Decodable {
    struct Account: Decodable {
        let id: String
        let environment: TradingEnvironment
        let maxOrderUSD: String
        let recoveryPreference: RecoveryPreference?
        let savedName: String?
        let keysTyped: Bool?

        enum CodingKeys: String, CodingKey {
            case id, environment
            case maxOrderUSD = "max_order_usd"
            case recoveryPreference = "recovery_preference"
            case savedName = "saved_name"
            case keysTyped = "keys_typed"
        }
    }

    /// A guru, known by their channel.
    struct Route: Decodable {
        let channel: String
        let account: String
    }

    struct Setup: Decodable {
        let accounts: [Account]
        let routes: [Route]
    }

    let name: String
    let copying: Bool
    let start: Bool?
    let saved: Setup
    let draft: Setup
    let facts: AgentSetupApplyFacts
}

@MainActor
private func liveFactsMatchTheSharedCases() async throws {
    struct Cases: Decodable { let cases: [FactsCase] }
    let contracts = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appending(path: "Resources/Contracts")
    let cases = try JSONDecoder().decode(
        Cases.self, from: Data(contentsOf: contracts.appending(path: "agent-setup-apply-facts.json"))
    ).cases
    for item in cases {
        let setup = try await fixture(
            setup: try savedSetup(
                accounts: item.saved.accounts.map { ($0.id, $0.environment, $0.maxOrderUSD) },
                recovery: Dictionary(
                    item.saved.accounts.compactMap { account in account.recoveryPreference.map { (account.id, $0) } },
                    uniquingKeysWith: { first, _ in first }),
                gurus: item.saved.routes.map { ("Guru \($0.channel)", $0.channel, $0.account) }))
        defer { try? FileManager.default.removeItem(at: setup.directory) }
        let model = setup.model
        model.tradingStatus = try TradingStatusBuilder(item.copying ? .running : .paused).build()
        model.setupDraft.accounts = item.draft.accounts.map { wanted in
            var account =
                model.setupDraft.accounts.first { $0.savedName != nil && $0.savedName == wanted.savedName }
                ?? TradingAccountDraft(name: wanted.id, environment: wanted.environment)
            account.name = wanted.id
            account.environment = wanted.environment
            account.policy.maxOrderUSD = wanted.maxOrderUSD
            if let preference = wanted.recoveryPreference { account.policy.recoveryPreference = preference }
            if wanted.keysTyped == true {
                account.key = "typed-alpaca-key"
                account.secret = "typed-alpaca-secret"
            }
            return account
        }
        for route in item.draft.routes {
            let draft = model.setupDraft
            if let index = draft.routes.firstIndex(where: { draft.effectiveChannel(for: $0) == route.channel }) {
                model.setupDraft.routes[index].connection = TradingConnectionDraft(
                    accountID: route.account, fullPositionUSD: draft.routes[index].connection?.fullPositionUSD ?? "")
            }
        }
        let facts = model.agentApplyFacts(start: item.start ?? false)
        try verify(facts == item.facts, "\(item.name): the app found \(facts), the shared case says \(item.facts)")
    }
}

@MainActor
private func aLockedAppChangesNothing() async throws {
    let setup = try await fixture()
    defer { try? FileManager.default.removeItem(at: setup.directory) }
    setup.model.isTradingUnlocked = false
    let locked = try error(try await send(setup.model, ["operation": "edit_setup_discord", "token": "typed-discord-token"]))
    try verify(locked.code == "locked" && locked.message == "Unlock CopyTrading first.", "a locked app was \(locked)")
    try verify(setup.model.setupDraft.discordToken.isEmpty, "a locked app took a key")
    let garbage = await setup.model.answerAgentSetup(line: #"{"operation":"apply_setup"}"#, context: context)
    try verify(garbage.contains(#""code":"invalid_request""#), "a malformed setup line was \(garbage)")
}

@MainActor
private func startOnAPaperFirstSetupStartsCopying() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(
        path: "agent-setup-first-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = TradingConfigurationStore(url: directory.appending(path: "configuration.json"), secrets: TestSecretRevisions())
    let starter = RecordingTradingStarter()
    let model = AppModel(
        tradingConfigurationStore: store, tradingStarter: starter, appUnlock: try await unlocked(by: OwnerAnswers(confirms: false)),
        agentProposalOperations: SetupEngine())
    model.isTradingUnlocked = true
    model.tradingStatus = try TradingStatusBuilder(.paused).build()
    for request: [String: Any] in [
        ["operation": "edit_setup_discord", "channel_ids": ["123"], "token": "typed-discord-token"],
        ["operation": "edit_setup_model", "service": "deepseek", "model": "deepseek-flash", "key": "typed-model-key"],
        [
            "operation": "edit_setup_account", "action": "add", "account_id": "paper", "key": "typed-alpaca-key",
            "secret": "typed-alpaca-secret",
        ],
        ["operation": "edit_setup_guru", "action": "add", "guru": "Alex", "account_id": "paper"],
    ] {
        _ = try ok(try await send(model, request))
    }
    let started = try ok(try await send(model, ["operation": "apply_setup", "start": true]))
    try verify(
        started["status"] as? String == "applied" && started["message"] as? String == "Saved, and copying started.",
        "--start on a first paper setup was \(started) \(model.message ?? "")")
    try verify(
        model.tradingStatus?.state == .running && model.savedTradingConfiguration?.accounts.map(\.id) == ["paper"],
        "--start did not save the first setup and start copying")
    let saved = try store.load()
    try verify(saved?.secrets.discordToken == "typed-discord-token", "the first setup's keys did not reach the Keychain")
}

@MainActor
private func startWithALiveAccountWaitsForTheOwner() async throws {
    let setup = try await fixture(setup: try savedSetup(accounts: [("paper", .live, "100")]))
    defer { try? FileManager.default.removeItem(at: setup.directory) }
    let model = setup.model
    let plain = try ok(try await send(model, ["operation": "apply_setup"]))
    try verify(plain["status"] as? String == "unchanged", "a plain apply of a saved live setup was \(plain)")
    let proposed = try ok(try await send(model, ["operation": "apply_setup", "start": true]))
    try verify(
        proposed["type"] as? String == "proposal"
            && (proposed["subject"] as? [String: Any])?["starts_live"] as? [String] == ["paper"],
        "--start into a live account did not wait for the owner: \(proposed)")
    let events = await setup.starter.events()
    try verify(events.isEmpty, "--start into a live account ran before approval: \(events)")
    try verify(model.agentSetupProposals["p-0123456789ab"]?.start == true, "the approval forgot it was asked to start")
    guard let pending = model.pendingAgentProposal else { throw SetupFlowFailure(description: "no request to approve") }
    model.setStartsCopying(true)
    await model.approveAgentProposal(pending)
    let confirmations = await setup.owner.confirmations
    try verify(
        model.tradingStatus?.state == .running && confirmations == 2,
        "an approved --start did not ask Touch ID to start live, then start: \(confirmations), \(model.message ?? "")")
}

@MainActor
private func startResumesPausedCopying() async throws {
    let setup = try await fixture()
    defer { try? FileManager.default.removeItem(at: setup.directory) }
    let model = setup.model
    let plain = try ok(try await send(model, ["operation": "apply_setup"]))
    try verify(plain["status"] as? String == "unchanged" && model.tradingStatus?.state == .paused, "a plain apply resumed copying")
    let resumed = try ok(try await send(model, ["operation": "apply_setup", "start": true]))
    try verify(
        resumed["status"] as? String == "applied" && model.tradingStatus?.state == .running,
        "--start did not resume paused copying: \(resumed) \(model.message ?? "")")
}

@MainActor
private func applyingTheSameSetupTwiceSavesAndStartsOnce() async throws {
    let setup = try await fixture()
    defer { try? FileManager.default.removeItem(at: setup.directory) }
    let model = setup.model
    _ = try ok(try await send(model, ["operation": "edit_setup_discord", "channel_ids": ["123", "789"]]))
    let first = try ok(try await send(model, ["operation": "apply_setup"]))
    let again = try ok(try await send(model, ["operation": "apply_setup"]))
    try verify(
        first["status"] as? String == "applied" && again["status"] as? String == "unchanged",
        "a second apply of the same setup was \(again) after \(first)")
    let checked = await setup.starter.validationCallCount()
    try verify(checked == 1, "the same setup was checked and saved \(checked) times")
    let started = try ok(try await send(model, ["operation": "apply_setup", "start": true]))
    let startedAgain = try ok(try await send(model, ["operation": "apply_setup", "start": true]))
    let starts = await setup.starter.events().filter { $0 == "start" }.count
    try verify(
        started["status"] as? String == "applied" && startedAgain["status"] as? String == "unchanged" && starts == 1,
        "the same setup started \(starts) times: \(started), then \(startedAgain)")
}

@MainActor
private func setupChangesNeedTheOwnerToTurnThemOn() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(
        path: "agent-setup-access-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    for confirms in [false, true] {
        let owner = OwnerAnswers(confirms: confirms)
        let model = AppModel(appUnlock: try await unlocked(by: owner))
        model.isTradingUnlocked = true
        model.loadAgentAccess(stateRoot: directory)
        try verify(!model.agentSetupChanges, "setup changes were on before the owner turned them on")
        await model.setAgentSetupChanges(true)
        let asked = await owner.confirmations
        try verify(asked == 1, "turning on setup changes did not ask the owner")
        try verify(model.agentSetupChanges == confirms, "setup changes turned on without the owner")
        let saved = try AgentAccessStore(stateRoot: directory).load()
        try verify(saved.setupChanges == confirms, "the owner's choice was not saved as made")
    }
}

/// The engine's trail records who sent a line the app refused before asking.
private actor RecordingAuthorizer: AgentProposalOperations {
    private(set) var asked: [AgentSetupAuthorizationRequest] = []

    func authorizeSetup(
        _ setup: AgentSetupAuthorizationRequest, context: AgentRequestContext
    ) async throws -> AgentSetupAuthorization {
        asked.append(setup)
        return .answered(line: "{}")
    }

    func agentProposals() async throws -> [AgentProposal] { [] }
    func approveProposal(id: String, digest: String) async throws -> AgentProposal { throw CancellationError() }
    func completeProposal(id: String, succeeded: Bool, code: String?) async throws -> AgentProposal {
        throw CancellationError()
    }
    func rejectProposal(id: String) async throws -> AgentProposal { throw CancellationError() }
    func discardProposals() async throws -> Int { 0 }
}

@MainActor
private func aLineTheAppCannotReadIsStillRecorded() async throws {
    let authorizer = RecordingAuthorizer()
    let model = AppModel(agentProposalOperations: authorizer)
    model.isTradingUnlocked = true
    let answer = await model.answerAgentSetup(
        line: #"{"schema_version":1,"request_id":"bad-1","operation":"edit_setup_discord","channel_ids":["general"]}"#,
        context: context)
    try verify(answer.contains(#""code":"invalid_request""#), "an unreadable line was \(answer)")
    let asked = await authorizer.asked
    try verify(
        asked.count == 1 && asked[0].invalid && asked[0].operation == .discord && asked[0].requestID == "bad-1",
        "the refused line was not recorded with the engine: \(asked)")
}

@MainActor
private func aGuruIsTheirChannel() async throws {
    let setup = try await fixture()
    defer { try? FileManager.default.removeItem(at: setup.directory) }
    let model = setup.model
    _ = try ok(try await send(model, ["operation": "edit_setup_discord", "channel_ids": ["123", "789"]]))
    _ = try ok(try await send(model, ["operation": "edit_setup_account", "action": "add", "account_id": "paper-3"]))
    let shared = try error(
        try await send(model, ["operation": "edit_setup_guru", "action": "add", "guru": "Dee", "account_id": "paper-3"]))
    try verify(
        shared.code == "conflict" && shared.message.contains("Launch Guru already reads channel 123")
            && shared.message.contains("--channel"),
        "a second guru on one channel was \(shared)")
    try verify(!model.setupDraft.routes.contains { $0.displayName == "Dee" }, "a refused guru reached the draft")
    let typedID = try error(
        try await send(
            model,
            [
                "operation": "edit_setup_guru", "action": "add", "guru": "guru-0123abcd", "channel_id": "789",
                "account_id": "paper-3",
            ]))
    try verify(
        typedID.code == "invalid_request" && typedID.message.contains("comes from their channel"),
        "a typed guru ID was \(typedID)")
    let added = try ok(
        try await send(
            model,
            ["operation": "edit_setup_guru", "action": "add", "guru": "Dee", "channel_id": "789", "account_id": "paper-3"]))
    let dee = GuruIdentity.id(channelID: "789")
    try verify(
        (added["gurus"] as? [[String: Any]])?.contains { $0["name"] as? String == "Dee" && $0["guru_id"] as? String == dee }
            == true,
        "Dee did not take channel 789's ID: \(added)")
    _ = try ok(try await send(model, ["operation": "edit_setup_guru", "action": "edit", "guru": dee, "rename": "Dee Two"]))
    try verify(model.setupDraft.routes.contains { $0.displayName == "Dee Two" }, "a guru named by their ID was not found")
    let moved = try error(
        try await send(model, ["operation": "edit_setup_guru", "action": "edit", "guru": "Dee Two", "channel_id": "123"]))
    try verify(
        moved.code == "conflict" && moved.message.contains("each channel copies one guru"),
        "a move onto a taken channel was \(moved)")
    try verify(
        model.setupDraft.routes.first { $0.displayName == "Dee Two" }?.channelID == "789",
        "a refused channel move changed the draft")
}

@MainActor
private func afterARestartIsAnAccountSetting() async throws {
    let setup = try await fixture()
    defer { try? FileManager.default.removeItem(at: setup.directory) }
    let model = setup.model
    let shown = try ok(try await send(model, ["operation": "get_setup"]))
    try verify(
        (shown["accounts"] as? [[String: Any]])?.first?["recovery_preference"] as? String == "manual",
        "an account did not show it waits after a restart: \(shown)")
    let edited = try ok(
        try await send(
            model,
            ["operation": "edit_setup_account", "action": "edit", "account_id": "paper", "recovery_preference": "automatic"]
        ))
    try verify(
        model.setupDraft.policy(of: "paper")?.recoveryPreference == .automatic
            && (edited["accounts"] as? [[String: Any]])?.first?["recovery_preference"] as? String == "automatic"
            && edited["unsaved_changes"] as? Bool == true,
        "the after-restart choice did not reach the draft: \(edited)")
    let applied = try ok(try await send(model, ["operation": "apply_setup"]))
    try verify(
        applied["status"] as? String == "applied"
            && model.savedTradingConfiguration?.accounts.first?.policy.recoveryPreference == .automatic,
        "the after-restart choice was not saved with the setup: \(applied) \(model.message ?? "")")
}

@MainActor
private func aSavedSetupFileIsUpgradedOrRefusedByItsVersion() async throws {
    let setup = try await fixture()
    defer { try? FileManager.default.removeItem(at: setup.directory) }
    let model = setup.model
    // A setup saved by beta.7: version 9, with no after-restart choice in it, and one live account.
    let (configuration, _) = try savedSetup(accounts: [("paper", .paper, "100"), ("live-x", .live, "250")])
    func file(version: Int) throws -> String {
        var raw = try JSONSerialization.jsonObject(with: JSONEncoder().encode(configuration)) as? [String: Any] ?? [:]
        raw["version"] = version
        raw["accounts"] = (raw["accounts"] as? [[String: Any]])?.map { account in
            var old = account
            var policy = account["policy"] as? [String: Any] ?? [:]
            policy.removeValue(forKey: "recovery_preference")
            old["policy"] = policy
            return old
        }
        let saved: [String: Any] = ["version": 1, "configuration": raw]
        return String(decoding: try JSONSerialization.data(withJSONObject: saved), as: UTF8.self)
    }
    let imported = try ok(try await send(model, ["operation": "import_setup", "text": try file(version: 9)]))
    let filled = imported["filled"] as? [String] ?? []
    try verify(
        model.setupDraft.accounts.map(\.name) == ["paper", "live-x"]
            && model.setupDraft.accounts.allSatisfy { $0.environment == .paper && $0.policy.recoveryPreference == .manual }
            && model.setupDraft.policy(of: "live-x")?.maxOrderUSD == "250"
            && filled.contains("account live-x (paper; after a restart Wait for me)")
            && (imported["missing"] as? [String])?.contains("Alpaca keys for live-x") == true,
        "a version 9 setup was not upgraded into a paper draft: \(imported)")
    try verify(
        (imported["setup"] as? [String: Any]).flatMap { $0["gurus"] as? [[String: Any]] }?.first?["guru_id"] as? String
            == GuruIdentity.id(channelID: "123"),
        "an upgraded guru did not keep their channel's ID: \(imported)")
    for (version, words) in [(7, "version 7, from before"), (TradingConfiguration.currentVersion + 1, "newer CopyTrading")] {
        let before = model.setupDraft.signature
        let refused = try error(try await send(model, ["operation": "import_setup", "text": try file(version: version)]))
        try verify(
            refused.code == "invalid_request" && refused.message.contains(words)
                && refused.message.contains("Nothing was imported"),
            "a version \(version) setup was \(refused)")
        try verify(model.setupDraft.signature == before, "a refused setup file changed the draft")
    }
}
