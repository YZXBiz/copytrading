import CopyTradingTestSupport
import DesktopCore
import Darwin
import Foundation

@MainActor
struct TradingSettingsSaveTests {
    /// The save and start flow through AppModel; ContractChecks runs it after the other checks.
    static func runSettingsSaveFlow() async throws {
        print("CopyTradingContractTests: connections draft round-trips saved configuration and never keeps typed secrets")
        print(
            "CopyTradingContractTests: registered NSWindow.willClose callback closed and reopened model sessions; stale auth cleanup and retry remained scoped"
        )
        print("CopyTradingContractTests: Stop report explains unconfirmed drain, forced local stop, and outstanding broker orders")
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "app-model-trading-\(UUID().uuidString)", directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        try checkLogSettingsPersistBeforeRuntime(
            directory.appending(path: "first-run-log-settings", directoryHint: .isDirectory)
        )
        let store = TradingConfigurationStore(
            url: directory.appending(path: "configuration.json"),
            secrets: TestSecretRevisions()
        )
        let starter = RecordingTradingStarter()
        let model = AppModel(tradingConfigurationStore: store, tradingStarter: starter)
        model.isTradingUnlocked = true
        model.tradingStatus = try status(.paused)
        try checkNavigationContract()
        try checkCopyingSummary()
        try checkActivityScreenStateAndStatusPolicy()

        let profile = try TradingProfileBuilder().build(
            TradingProfileDraft(
                guruID: GuruIdentity.id(channelID: "123"), displayName: "Stable Guru"
            ))
        let configuration = TradingConfiguration(
            source: TradingSourceConfiguration(channelIDs: ["123"]),
            provider: TradingProviderConfiguration(name: .anthropic, model: "test-model"),
            accounts: [TradingAccountConfiguration(id: "paper", environment: .paper)],
            profiles: [profile],
            routes: [
                TradingRouteConfiguration(
                    channelID: "123", authorID: "456", guruID: profile.guruID,
                    profileRevision: profile.profileRevision,
                    connections: [
                        TradingRouteConnection(
                            accountID: "paper", fullPositionUSD: "600"
                        )
                    ]
                )
            ]
        )
        let credentials = TradingSecrets(
            discordToken: "private-source-credential", providerAPIKey: "private-provider-credential",
            brokers: [
                TradingBrokerCredentials(
                    accountID: "paper", key: "private-broker-key", secret: "private-broker-secret"
                )
            ]
        )

        await model.validateTradingSettings(configuration, enteredSecrets: credentials)
        try check(model.savedTradingConfiguration == nil, "Validation persisted configuration early")
        let beforeActivation = try store.load()
        try check(beforeActivation == nil, "Validation wrote the config or Keychain reference")
        try check(model.tradingValidation?.report.activatable == true, "Capability report was not activatable")
        await model.activateValidatedTradingSettings()
        try check(model.savedTradingConfiguration == configuration, model.message ?? "AppModel activation failed")
        guard let loaded = try store.load() else { throw ContractFailure("Saved profile missing") }
        try check(loaded.configuration.version == TradingConfiguration.currentVersion, "Saved profile version changed")
        try check(loaded.configuration == configuration, "Saved profile content changed")
        try check(loaded.secrets == credentials, "Saved credentials changed")

        let evaluation = try await model.evaluateHistoricalProfile(
            sourceID: "discord:123:historical-message", routeID: configuration.routes[0].id
        )
        try check(evaluation.simulated && evaluation.noOrder, "Historical evaluation was not marked no-order")
        try check(evaluation.profileRevision == profile.profileRevision, "Evaluation lost profile revision")
        let evaluationRequest = await starter.evaluationRequest()
        try check(evaluationRequest?.sourceID == "discord:123:historical-message", "AppModel changed historical source identity")
        try check(
            evaluationRequest?.providerAPIKey == credentials.providerAPIKey, "AppModel did not use saved Keychain provider credential")
        try check(evaluationRequest?.destinations == configuration.routes[0].connections, "Evaluation did not use saved route destinations")

        let started = await starter.startedConfiguration()
        try check(started == configuration, "Start received a different profile")
        try check(model.tradingStatus?.state == .running, model.message ?? "AppModel start failed")
        try await checkValidationClientRequest(configuration: configuration, secrets: credentials)
        try await checkHistoricalEvaluationClientRequest(profile: profile)
        try await checkFailedActivationRestoresPriorRevision()
        try await checkLaunchStartRetriesAFailedCheck()
        try await checkLaunchStartRetriesATimedOutRequest()
        try await checkPauseEndsLaunchStartRetries()
        try await checkAgentStartRunsStartCopyingsOwnChecks()
        try await checkAgentLimitChangesSaveOverTheSavedSetup()
        try await checkAgentLimitChangesNeverTouchUnsavedWork()
        try await checkEngineRestartStartsCopyingAgain()
        try await checkLaunchStartNeedsNoWindow()
        try await checkLaunchStartWaitsForTheSetupUpgrade()
        try await checkEngineRestartKeepsAPausedSetupPaused()
        try await checkAcceptedActivationWithLostResponseRemainsPending()
        try await checkPendingActivationReconcilesAfterAppReopen(configuration: configuration, secrets: credentials)
        try await checkFailedSameRevisionActivationRetainsPreviousSecrets(configuration: configuration)
        try await checkAFailedStartNamesTheAccountAndCanBeTriedAgain(configuration: configuration, secrets: credentials)
        try checkEveryStartFailureSaysWhatToDo()
        try await checkInterruptedSameRevisionActivationRollsBackAfterReopen(configuration: configuration)
        try await checkReadySameRevisionActivationFinalizesAfterStoppedReopen(configuration: configuration)
        try await checkResumeThatKeepsCopyingIsApplied(configuration: configuration, secrets: credentials)
        try await checkSavedLiveResumeUsesConfirmedActivationPath(configuration: configuration, secrets: credentials)
        try await checkLiveStartNeedsTheOwnerAndPaperDoesNot(configuration: configuration, secrets: credentials)
        try await checkStartAfterALongLookChecksAgain(configuration: configuration, secrets: credentials)
        try await checkACheckedSetupIsNotStarting(configuration: configuration, secrets: credentials)
        try await checkPlaybookLearningUsesSavedKeysAndExplainsFailures(configuration: configuration, secrets: credentials)
        try await checkRejectedValidationDoesNotPersist(configuration: configuration, secrets: credentials)
        try await checkValidationCancellationDoesNotPersist(configuration: configuration, secrets: credentials)
        try await checkDiscardedCheckAndLockedDraft(configuration: configuration, secrets: credentials)
        try await checkSetupCheckKeepsKeysAndFollowsEdits(configuration: configuration, secrets: credentials)
        try await checkAccountStartUsesTheEdits(configuration: configuration, secrets: credentials)
        try await checkApplyChangesWhileCopying(configuration: configuration, secrets: credentials)
        try await checkLimitOnlyChangesApplyWithoutAPause(configuration: configuration, secrets: credentials)
        try await checkConnectionClientRequest(provider: configuration.provider)
        try await checkOneConnectionUsesSavedKeysAndFollowsEdits(configuration: configuration, secrets: credentials)
        try await checkSetupSavedWithTheRetiredChatFilterLoadsAndStartsOnTheEnginesRevision(
            configuration: configuration, secrets: credentials)
        try await checkConfigurationWriteFailureDoesNotStart()
        try checkOperatorWireFixtures()
        try await checkAccountPageClientRequest()
        try await checkAccountFeatureActions()
        try await checkAnEarlierAccountsRecordIsDeletedOnlyWhenAsked()
        try await checkOwnershipResolution(configuration: configuration)
        try await checkAccountFeatureLockInterleavings()
        try await checkManualReviewActionPath()
        try await checkManualCorrectionReplicaRepairPath()
        try await checkFreshPreviewIdentityAction()
        try await checkDurableCommandRecoveryActionPath()
        print("CopyTradingContractTests: AppModel validated and activated a v3 profile")
    }

    private static func status(_ state: TradingRunState) throws -> TradingStatus {
        try TradingStatusBuilder(state).build()
    }

    private static func status(_ state: TradingRunState, errorCode: String?) throws -> TradingStatus {
        try TradingStatusBuilder(state).connected().error(errorCode).build()
    }

    private static func checkCopyingSummary() throws {
        let starting = CopyingState.overall(try status(.degraded, errorCode: nil))
        try check(
            starting == CopyingState(.notStarted, "Starting…") && starting.tone == .inactive,
            "A degraded engine with no error is still starting, not a problem: \(starting.text)")
        let problem = CopyingState.overall(try status(.degraded, errorCode: "account_unavailable"))
        try check(
            problem.word == .copying && problem.detail != nil && problem.tone == .caution,
            "A degraded engine with an error code copies with a warning: \(problem.text)")
        let running = CopyingState.overall(try status(.running))
        try check(running.text == "Copying", "Running must read as copying")
        let failed = CopyingState.overall(try status(.failed))
        try check(failed.word == .stopped && failed.tone == .critical, "A failed engine must read as stopped")
        try check(CopyingState.overall(nil).text == "Paused", "No status reads as paused")
        print("CopyTradingContractTests: footer reads a start that is still finishing as Starting, and only a coded fault as a problem")
        try check(
            StatusTone(code: "unchecked") == .neutral,
            "A check that has not run yet is information, not a warning")
        try check(StatusTone(code: "unavailable") == .critical, "An unavailable check must still read as critical")
        try check(StatusTone(code: "queryable") == .positive, "A queryable check must still read as positive")
        print("CopyTradingContractTests: an unchecked status is neutral while unavailable and queryable keep their tones")
    }

    private static func checkNavigationContract() throws {
        let pages = AppModel.Screen.pages
        try check(
            pages.map(\.identifier) == [
                "navigation.connections", "navigation.gettingStarted", "navigation.settings", "navigation.diagnostics",
            ],
            "Native navigation lost a required operator page")
        try check(
            pages.map(\.title) == ["Connections", "Getting Started", "Settings", "Diagnostics"], "Native navigation titles changed")
        try check(
            AppModel.Screen.account("primary").identifier == "navigation.account.primary"
                && AppModel.Screen.guru("guru-1a2b").identifier == "navigation.guru.guru-1a2b",
            "Accounts and gurus lost their sidebar identifiers")
        try check(
            AppModel.Screen.account("primary").assistantName == "accounts" && AppModel.Screen.guru("g").assistantName == "people",
            "The assistant no longer reads accounts and gurus as the engine names them")
        print("CopyTradingContractTests: every account, guru, and operator page is navigable")
    }

    private static func checkValidationClientRequest(
        configuration: TradingConfiguration, secrets: TradingSecrets
    ) async throws {
        let validationWire = Data(
            """
            {"version":1,"request_id":"validation-request","ok":{"type":"trading_validation",
             "report":{"configuration_revision":"revision-1","activatable":true,
              "checks":[{"name":"source","state":"ready","subject":null,"environment":null,
                "identity":"discord_user:123","adapter":"discord-py-self-user-token","reason_code":null,"symbols":[]}],
              "cost_notice":"Model check may incur a charge."},"activation_token":"single-use-grant"}}
            """.utf8)
        let validationTransport = AccountPageTransport(responseFixture: validationWire)
        let validation = try await EngineClient(transport: validationTransport).validateTrading(
            configuration: configuration, secrets: secrets
        )
        let validationRequest = await validationTransport.sentRequest()
        guard
            let validationJSON = try JSONSerialization.jsonObject(with: validationRequest ?? Data())
                as? [String: Any]
        else { throw ContractFailure("Validation request was not JSON") }
        try check(validationJSON["operation"] as? String == "validate_trading", "Wrong validation IPC operation")
        try check(validationJSON["secrets"] != nil, "Capability validation omitted draft credentials")
        try check(validation.activationToken == "single-use-grant", "Validation grant was not decoded")
        let responseText = String(decoding: validationWire, as: UTF8.self)
        try check(!responseText.contains(secrets.discordToken), "Validation report leaked a source token")
        try check(!responseText.contains(secrets.providerAPIKey), "Validation report leaked a provider key")

        let startWire = Data(
            """
            {"version":1,"request_id":"start-request","ok":{"type":"trading_status","trading":
             {"state":"starting","configured_accounts":1,"active_accounts":0,"source_connected":false,
              "model_ready":false,"pending_source":0,"pending_signals":0,"processed_signals":0,
              "error_code":null,"accounts":[]}}}
            """.utf8)
        let startTransport = AccountPageTransport(responseFixture: startWire)
        _ = try await EngineClient(transport: startTransport).startTrading(
            configuration: configuration,
            secrets: secrets,
            validationToken: "single-use-grant",
            activationID: "00112233-4455-6677-8899-aabbccddeeff"
        )
        guard let startRequest = await startTransport.sentRequest(),
            let startJSON = try JSONSerialization.jsonObject(with: startRequest) as? [String: Any]
        else {
            throw ContractFailure("Start request was not captured")
        }
        try check(startJSON["operation"] as? String == "start_trading", "Wrong start IPC operation")
        try check(startJSON["validation_token"] as? String == "single-use-grant", "Start omitted validation grant")
        try check(
            startJSON["activation_id"] as? String == "00112233-4455-6677-8899-aabbccddeeff",
            "Start omitted durable activation identity")
        print("CopyTradingContractTests: validation and activation grant used typed engine IPC")
    }

    private static func checkHistoricalEvaluationClientRequest(
        profile: TradingProfileRevision
    ) async throws {
        let wire = Data(
            """
            {"version":1,"request_id":"evaluation-request","ok":{"type":"profile_evaluation",
             "evaluation":{"message_identity":"discord:123:historical-message","guru_id":"guru-be6f68ea",
              "profile_revision":"\(profile.profileRevision)","exit_basis":"original_position",
              "provider":"anthropic","model":"test-model","decision":"trade","reason":"explicit_entry",
              "simulated":true,"no_order":true,"cost_notice":"Provider charges may apply.",
              "instructions":[],"destinations":[],"review_reasons":[]}}}
            """.utf8)
        let transport = AccountPageTransport(responseFixture: wire)
        let request = HistoricalProfileEvaluationRequest(
            sourceID: "discord:123:historical-message",
            profile: profile,
            provider: TradingProviderConfiguration(name: .anthropic, model: "test-model"),
            providerAPIKey: "private-provider-key",
            destinations: [
                TradingRouteConnection(
                    accountID: "paper", fullPositionUSD: "600"
                )
            ]
        )
        let result = try await EngineClient(transport: transport).evaluateHistoricalProfile(request)
        try check(result.noOrder && result.simulated, "Typed preview response lost its no-order contract")
        guard let bytes = await transport.sentRequest(),
            let json = try JSONSerialization.jsonObject(with: bytes) as? [String: Any]
        else {
            throw ContractFailure("Historical evaluation request was not captured")
        }
        try check(json["operation"] as? String == "evaluate_historical_profile", "Wrong evaluation IPC operation")
        try check(json["source_id"] as? String == request.sourceID, "Historical source identity was changed")
        try check(json["profile"] != nil && json["destinations"] != nil, "Preview omitted profile or destination terms")
        try check(json["provider_api_key"] as? String == request.providerAPIKey, "Preview omitted configured model credentials")
        try check(json["command"] == nil && json["command_id"] == nil, "Preview request carried executable command fields")
        print("CopyTradingContractTests: historical evaluation used typed no-order IPC")
    }

    private static func checkFailedActivationRestoresPriorRevision() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "app-model-activation-rollback-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TradingConfigurationStore(
            url: directory.appending(path: "configuration.json"), secrets: TestSecretRevisions()
        )
        let originalProfile = try TradingProfileBuilder().build(
            TradingProfileDraft(
                guruID: GuruIdentity.id(channelID: "123"), displayName: "Prior Guru"
            ))
        let original = TradingConfiguration(
            source: TradingSourceConfiguration(channelIDs: ["123"], authorIDs: ["456"]),
            provider: TradingProviderConfiguration(name: .anthropic, model: "prior-model"),
            accounts: [TradingAccountConfiguration(id: "paper", environment: .paper)],
            profiles: [originalProfile],
            routes: [
                TradingRouteConfiguration(
                    channelID: "123", authorID: "456", guruID: originalProfile.guruID,
                    profileRevision: originalProfile.profileRevision,
                    connections: [TradingRouteConnection(accountID: "paper", fullPositionUSD: "600")]
                )
            ]
        )
        let originalSecrets = TradingSecrets(
            discordToken: "prior-source", providerAPIKey: "prior-provider",
            brokers: [TradingBrokerCredentials(accountID: "paper", key: "prior-key", secret: "prior-secret")]
        )
        try store.save(configuration: original, revision: fakeEngineRevision(original), secrets: originalSecrets, when: .paused)
        let starter = RecordingTradingStarter()
        await starter.setStartFailure(true)
        let model = AppModel(tradingConfigurationStore: store, tradingStarter: starter)
        model.isTradingUnlocked = true
        model.tradingStatus = try status(.paused)
        model.savedTradingConfiguration = original

        var replacement = original
        replacement.provider.model = "replacement-model"
        let replacementSecrets = TradingSecrets(
            discordToken: "new-source", providerAPIKey: "new-provider",
            brokers: [TradingBrokerCredentials(accountID: "paper", key: "new-key", secret: "new-secret")]
        )
        await model.validateTradingSettings(replacement, enteredSecrets: replacementSecrets)
        let afterValidation = try store.load()
        try check(afterValidation?.configuration == original, "Validation replaced prior config")
        try check(afterValidation?.secrets == originalSecrets, "Validation replaced prior credentials")
        await model.activateValidatedTradingSettings()
        let afterFailedStart = try store.load()
        try check(afterFailedStart?.configuration == original, "Failed Start did not restore prior config")
        try check(afterFailedStart?.secrets == originalSecrets, "Failed Start did not restore prior credentials")
        try check(model.savedTradingConfiguration == original, "AppModel published a failed revision")
        let failedStartConfiguration = await starter.startedConfiguration()
        try check(failedStartConfiguration == nil, "Failed Start was recorded as activated")
        print("CopyTradingContractTests: failed activation restored prior config and Keychain reference")
    }

    /// A paper setup saved and paused, the owner wanting copying to start on launch, and a model
    /// provider check that fails until the starter is told it passes.
    private static func launchStartFixture() async throws -> (AppModel, RecordingTradingStarter, URL) {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "app-model-launch-retry-\(UUID().uuidString)", directoryHint: .isDirectory
        )
        let store = TradingConfigurationStore(
            url: directory.appending(path: "configuration.json"), secrets: TestSecretRevisions()
        )
        let profile = try TradingProfileBuilder().build(
            TradingProfileDraft(
                guruID: GuruIdentity.id(channelID: "123"), displayName: "Launch Guru"
            ))
        let configuration = TradingConfiguration(
            source: TradingSourceConfiguration(channelIDs: ["123"], authorIDs: ["456"]),
            provider: TradingProviderConfiguration(name: .anthropic, model: "launch-model"),
            accounts: [TradingAccountConfiguration(id: "paper", environment: .paper)],
            profiles: [profile],
            routes: [
                TradingRouteConfiguration(
                    channelID: "123", authorID: "456", guruID: profile.guruID,
                    profileRevision: profile.profileRevision,
                    connections: [TradingRouteConnection(accountID: "paper", fullPositionUSD: "600")]
                )
            ]
        )
        let secrets = TradingSecrets(
            discordToken: "launch-source", providerAPIKey: "launch-provider",
            brokers: [TradingBrokerCredentials(accountID: "paper", key: "launch-key", secret: "launch-secret")]
        )
        try store.save(configuration: configuration, revision: fakeEngineRevision(configuration), secrets: secrets, when: .paused)
        let starter = RecordingTradingStarter()
        await starter.setValidationActivatable(false)
        let model = AppModel(tradingConfigurationStore: store, tradingStarter: starter)
        model.isTradingUnlocked = true
        model.tradingStatus = try status(.paused)
        model.savedTradingConfiguration = configuration
        model.setStartsCopying(true)
        return (model, starter, directory)
    }

    private static func checkLaunchStartRetriesAFailedCheck() async throws {
        let (model, starter, directory) = try await launchStartFixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        model.launchStartRetryDelays = [.milliseconds(40), .milliseconds(40), .milliseconds(40)]
        await model.startCopyingOnLaunchIfWanted()
        try check(model.tradingStatus?.state == .paused, "A failed check must leave processing paused")
        try check(
            model.message == "Copying didn't start. Interpreter: Couldn't check this connection. Try again in a moment.",
            "The failed check was not named: \(model.message ?? "no message")")
        try check(
            ConnectionStatus.interpreter(model)?.text == L10n.string("Couldn't connect"),
            "The failed check's row in Connections did not say so: \(ConnectionStatus.interpreter(model)?.text ?? "nil")")
        await starter.setValidationActivatable(true)
        for _ in 0..<100 where model.tradingStatus?.state != .running { try await Task.sleep(for: .milliseconds(20)) }
        try check(model.tradingStatus?.state == .running, "The launch start did not retry after a failed check")
        let validations = await starter.validationCallCount()
        try check(validations >= 2, "Retry did not run the connection checks again")
        print("CopyTradingContractTests: launch start retried a failed connection check")
    }

    /// The engine reading the posts it missed can be slow to answer the first start; a request that
    /// timed out is retried like a failed check, so copying does not stay paused until someone
    /// notices.
    private static func checkLaunchStartRetriesATimedOutRequest() async throws {
        let (model, starter, directory) = try await launchStartFixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        await starter.setValidationActivatable(true)
        await starter.setValidationTimesOut(1)
        model.launchStartRetryDelays = [.milliseconds(40), .milliseconds(40), .milliseconds(40)]
        await model.startCopyingOnLaunchIfWanted()
        try check(model.tradingStatus?.state == .paused, "A timed out start must leave processing paused")
        for _ in 0..<100 where model.tradingStatus?.state != .running { try await Task.sleep(for: .milliseconds(20)) }
        try check(model.tradingStatus?.state == .running, "The launch start did not retry after the engine timed out")
        let validations = await starter.validationCallCount()
        try check(validations == 2, "Expected one timed out check and one retry, saw \(validations)")
        print("CopyTradingContractTests: launch start retried a timed out request")
    }

    /// An approved agent start is Start Copying: the same checks, and a failed check says so.
    private static func checkAgentStartRunsStartCopyingsOwnChecks() async throws {
        let (model, starter, directory) = try await launchStartFixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        model.setStartsCopying(false)
        let failed = await model.startCopyingForAgent()
        try check(failed == "failed_checks", "A failed connection check was not reported: \(failed ?? "nil")")
        try check(model.tradingStatus?.state == .paused, "A failed check started copying")
        await starter.setValidationActivatable(true)
        let started = await model.startCopyingForAgent()
        try check(started == nil, "A passing start was refused: \(started ?? "")")
        try check(model.tradingStatus?.state == .running, "Copying did not start")
        let locked = try await launchStartFixture()
        defer { try? FileManager.default.removeItem(at: locked.2) }
        locked.0.isTradingUnlocked = false
        let refused = await locked.0.startCopyingForAgent()
        try check(refused == "unavailable", "A locked app started: \(refused ?? "nil")")
        print("CopyTradingContractTests: an agent's approved start ran Start Copying's checks")
    }

    /// An approved agent request changes the saved setup the way the account sheet's limit save
    /// does: copying takes the new values, and the saved file holds them.
    private static func checkAgentLimitChangesSaveOverTheSavedSetup() async throws {
        let (model, starter, directory) = try await launchStartFixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let failure = await model.applyAgentLimitChanges(
            accountID: "paper",
            changes: [
                AgentLimitChange(field: "max_order_usd", value: "300.50"),
                AgentLimitChange(field: "max_entries_per_day", value: "200"),
                AgentLimitChange(field: "overnight", value: "true"),
            ])
        try check(failure == nil, "A valid limits request was refused: \(failure ?? "")")
        let policy = model.savedTradingConfiguration?.accounts.first?.policy
        try check(
            policy?.maxOrderUSD == "300.50" && policy?.maxEntriesPerDay == 200 && policy?.overnight == true,
            "The saved setup did not take the new limits")
        let events = await starter.events()
        try check(events == ["update_limits"], "Copying was not handed the limits once: \(events)")
        try check(
            model.setupDraft.accounts.first?.policy.maxOrderUSD == "300.50",
            "The draft kept the old limits after the agent's change")
        print("CopyTradingContractTests: an approved limits request changed the saved setup")
    }

    /// Nothing the owner has typed, started, or never saved is overwritten, and a value settings
    /// would refuse changes nothing.
    private static func checkAgentLimitChangesNeverTouchUnsavedWork() async throws {
        let (model, starter, directory) = try await launchStartFixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = model.savedTradingConfiguration
        let change = [AgentLimitChange(field: "max_order_usd", value: "300")]

        let unknown = await model.applyAgentLimitChanges(accountID: "nope", changes: change)
        try check(unknown == "not_found", "An unknown account was not refused: \(unknown ?? "nil")")
        let bad = await model.applyAgentLimitChanges(
            accountID: "paper", changes: [AgentLimitChange(field: "max_order_usd", value: "abc")])
        try check(bad == "invalid_request", "A bad number was not refused: \(bad ?? "nil")")
        let unknownSetting = await model.applyAgentLimitChanges(
            accountID: "paper", changes: [AgentLimitChange(field: "api_key", value: "x")])
        try check(unknownSetting == "invalid_request", "An unknown setting was applied: \(unknownSetting ?? "nil")")

        model.syncSetupDraftWithSaved()
        model.setupDraft.accounts[0].policy.maxSymbolUSD = "999"
        let unsaved = await model.applyAgentLimitChanges(accountID: "paper", changes: change)
        try check(unsaved == "unsaved_changes", "Unsaved edits were not protected: \(unsaved ?? "nil")")
        try check(model.setupDraft.accounts[0].policy.maxSymbolUSD == "999", "The owner's edit was lost")

        model.isTradingUnlocked = false
        let locked = await model.applyAgentLimitChanges(accountID: "paper", changes: change)
        try check(locked == "unavailable", "A locked app changed its setup: \(locked ?? "nil")")

        try check(model.savedTradingConfiguration == original, "A refused request changed the saved setup")
        let events = await starter.events()
        try check(!events.contains("update_limits"), "Copying was handed limits for a refused request")
        print("CopyTradingContractTests: refused limit requests changed nothing")
    }

    /// A crash is not the owner pausing: copying that was running starts again once the restarted
    /// engine reports paused, even when the owner never asked for copying at launch.
    private static func checkEngineRestartStartsCopyingAgain() async throws {
        let (model, starter, directory) = try await launchStartFixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        model.setStartsCopying(false)
        await starter.setValidationActivatable(true)
        model.tradingStatus = try status(.running)
        model.handle(.childExited(child: .engine, status: 9, restarting: true))
        try check(
            model.message == "The engine stopped and is restarting. Copying starts again when it's back.",
            "The restart did not say copying comes back: \(model.message ?? "no message")")
        model.tradingStatus = try status(.paused)
        await model.startCopyingOnLaunchIfWanted()
        try check(model.tradingStatus?.state == .running, "Copying stayed paused after the engine restarted")
        print("CopyTradingContractTests: an engine restart started copying again")
    }

    /// Oct 20 2026: an install relaunched the app while nobody was at the Mac, and copying stayed
    /// paused behind Touch ID for 1h40m while Zhao posted. A launch start the owner chose runs on
    /// the engine's status alone: no unlocked window, and no window at all.
    /// A setup the last version saved, copying set to start on launch: nothing starts until the
    /// upgrade has saved it, and the account copies on with its recorded "automatic".
    private static func checkLaunchStartWaitsForTheSetupUpgrade() async throws {
        let (model, starter, directory) = try await launchStartFixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        guard let store = model.tradingConfigurationStore,
            var saved = try JSONSerialization.jsonObject(with: Data(contentsOf: store.url)) as? [String: Any],
            var raw = saved["configuration"] as? [String: Any]
        else { return try check(false, "The launch fixture saved no setup") }
        raw["version"] = 9
        raw["accounts"] = (raw["accounts"] as? [[String: Any]] ?? []).map { account in
            var account = account
            var policy = account["policy"] as? [String: Any] ?? [:]
            policy.removeValue(forKey: "recovery_preference")
            account["policy"] = policy
            return account
        }
        saved["configuration"] = raw
        try JSONSerialization.data(withJSONObject: saved).write(to: store.url)
        model.savedTradingConfiguration = nil
        model.setupAwaitsUpgrade = true
        await starter.setValidationActivatable(true)

        model.tradingStatus = try status(.paused)
        await model.startCopyingOnLaunchIfWanted()
        try await Task.sleep(for: .milliseconds(100))
        let early = await starter.startedConfiguration()
        try check(early == nil, "Copying started on a setup the upgrade hadn't saved yet")

        await model.upgradeSavedSetup(
            in: store, recordedRecovery: { ["paper": .automatic] }, revision: { fakeEngineRevision($0) })
        for _ in 0..<100 where model.tradingStatus?.state != .running { try await Task.sleep(for: .milliseconds(20)) }
        let started = await starter.startedConfiguration()
        try check(model.tradingStatus?.state == .running, "The launch start didn't follow the upgrade")
        try check(
            started?.version == TradingConfiguration.currentVersion
                && started?.accounts.first?.policy.recoveryPreference == .automatic,
            "The resumed account lost its recorded automatic recovery")
        print("CopyTradingContractTests: a launch start waits for the setup upgrade and keeps automatic recovery")
    }

    private static func checkLaunchStartNeedsNoWindow() async throws {
        let (model, starter, directory) = try await launchStartFixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        model.isTradingUnlocked = false
        await starter.setValidationActivatable(true)
        model.tradingStatus = try status(.paused)
        for _ in 0..<100 where model.tradingStatus?.state != .running { try await Task.sleep(for: .milliseconds(20)) }
        try check(model.tradingStatus?.state == .running, "A launch start waited for the window to unlock")
        print("CopyTradingContractTests: a launch start copies without the window")
    }

    private static func checkEngineRestartKeepsAPausedSetupPaused() async throws {
        let (model, starter, directory) = try await launchStartFixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        model.setStartsCopying(false)
        await starter.setValidationActivatable(true)
        model.handle(.childExited(child: .engine, status: 9, restarting: true))
        model.tradingStatus = try status(.paused)
        await model.startCopyingOnLaunchIfWanted()
        try check(model.tradingStatus?.state == .paused, "An engine restart started copying the owner had paused")
        let validations = await starter.validationCallCount()
        try check(validations == 0, "A paused setup ran checks after the restart")
        print("CopyTradingContractTests: an engine restart kept a paused setup paused")
    }

    private static func checkPauseEndsLaunchStartRetries() async throws {
        let (model, starter, directory) = try await launchStartFixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        model.launchStartRetryDelays = [.milliseconds(150)]
        await model.startCopyingOnLaunchIfWanted()
        await model.pauseTrading()
        await starter.setValidationActivatable(true)
        try await Task.sleep(for: .milliseconds(500))
        try check([.pausing, .paused].contains(model.tradingStatus?.state), "A retry restarted copying after the owner paused")
        let validations = await starter.validationCallCount()
        try check(validations == 1, "A pause must end the launch retries, saw \(validations) checks")
        print("CopyTradingContractTests: pausing ended the launch start retries")
    }

    private static func checkAcceptedActivationWithLostResponseRemainsPending() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "app-model-ambiguous-activation-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let revisions = TestSecretRevisions()
        let store = TradingConfigurationStore(
            url: directory.appending(path: "configuration.json"), secrets: revisions
        )
        let profile = try TradingProfileBuilder().build(
            TradingProfileDraft(
                guruID: GuruIdentity.id(channelID: "123"), displayName: "Resume Guru"
            ))
        let prior = TradingConfiguration(
            source: TradingSourceConfiguration(channelIDs: ["123"]),
            provider: TradingProviderConfiguration(name: .anthropic, model: "prior-model"),
            accounts: [TradingAccountConfiguration(id: "paper", environment: .paper)],
            profiles: [profile],
            routes: [
                TradingRouteConfiguration(
                    channelID: "123", authorID: nil, guruID: profile.guruID,
                    profileRevision: profile.profileRevision,
                    connections: [
                        TradingRouteConnection(
                            accountID: "paper", fullPositionUSD: "600"
                        )
                    ]
                )
            ]
        )
        let priorSecrets = TradingSecrets(
            discordToken: "prior-source", providerAPIKey: "prior-provider",
            brokers: [TradingBrokerCredentials(accountID: "paper", key: "prior-key", secret: "prior-secret")]
        )
        try store.save(configuration: prior, revision: fakeEngineRevision(prior), secrets: priorSecrets, when: .paused)
        let replacement = TradingConfiguration(
            source: prior.source,
            provider: TradingProviderConfiguration(name: .anthropic, model: "candidate-model"),
            accounts: prior.accounts,
            profiles: prior.profiles,
            routes: prior.routes
        )
        let candidateSecrets = TradingSecrets(
            discordToken: "candidate-source", providerAPIKey: "candidate-provider",
            brokers: [TradingBrokerCredentials(accountID: "paper", key: "candidate-key", secret: "candidate-secret")]
        )
        let starter = RecordingTradingStarter()
        await starter.setAcceptStartAndLoseResponse(true)
        let model = AppModel(tradingConfigurationStore: store, tradingStarter: starter)
        model.isTradingUnlocked = true
        model.tradingStatus = try status(.paused)
        model.savedTradingConfiguration = prior

        await model.validateTradingSettings(replacement, enteredSecrets: candidateSecrets)
        await model.activateValidatedTradingSettings()

        let saved = try store.load()
        try check(saved?.configuration == prior, "Pending Start displaced the prior stable config")
        try check(saved?.secrets == priorSecrets, "Pending Start displaced prior credentials")
        let pending = try store.pendingActivation()
        try check(pending != nil, "Ambiguous Start lost its durable activation journal")
        let acceptedConfiguration = await starter.startedConfiguration()
        try check(acceptedConfiguration == replacement, "Ambiguous Start was not accepted by the engine fake")
        try check(revisions.storedCount == 2, "Ambiguous Start discarded credentials needed for reconciliation")
        try check(
            model.message == AppModel.pendingSetupMessage,
            "Ambiguous Start was presented as a final failure")
        print("CopyTradingContractTests: accepted Start with lost response remains pending for reconciliation")
    }

    private static func checkSavedLiveResumeUsesConfirmedActivationPath(
        configuration: TradingConfiguration, secrets credentials: TradingSecrets
    ) async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "app-model-saved-live-resume-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        var liveConfiguration = configuration
        liveConfiguration.accounts[0].environment = .live
        let store = TradingConfigurationStore(
            url: directory.appending(path: "configuration.json"), secrets: TestSecretRevisions()
        )
        try store.save(
            configuration: liveConfiguration, revision: fakeEngineRevision(liveConfiguration), secrets: credentials, when: .paused)
        let starter = RecordingTradingStarter()
        let owner = OwnerAnswers(confirms: true)
        let model = AppModel(tradingConfigurationStore: store, tradingStarter: starter, appUnlock: try await unlocked(by: owner))
        model.isTradingUnlocked = true
        model.tradingStatus = try status(.paused)
        model.savedTradingConfiguration = liveConfiguration

        await model.confirmLiveProcessing()
        let confirmations = await owner.confirmations
        try check(confirmations == 1, "Starting a live account did not ask for Touch ID")

        let validatedConfiguration = await starter.validatedConfiguration()
        try check(
            validatedConfiguration == liveConfiguration,
            "Live resume did not revalidate the saved revision")
        let startedConfiguration = await starter.startedConfiguration()
        try check(
            startedConfiguration == liveConfiguration,
            "Confirmed live resume required an unrelated pending draft")
        let pending = try store.pendingActivation()
        try check(pending == nil, "Acknowledged live resume left an unresolved journal")
        try check(
            model.tradingStatus?.state == .running,
            "Confirmed live resume did not publish the engine status")
        print("CopyTradingContractTests: saved live resume used explicit confirmation and fresh probes")
    }

    /// Copying into a live account places real orders by itself, so a refused Touch ID stops the
    /// start before anything is checked or sent; paper never asks.
    private static func checkLiveStartNeedsTheOwnerAndPaperDoesNot(
        configuration: TradingConfiguration, secrets credentials: TradingSecrets
    ) async throws {
        for environment in [TradingEnvironment.live, .paper] {
            let directory = FileManager.default.temporaryDirectory.appending(
                path: "app-model-live-start-owner-\(UUID().uuidString)", directoryHint: .isDirectory
            )
            defer { try? FileManager.default.removeItem(at: directory) }
            var saved = configuration
            saved.accounts[0].environment = environment
            let store = TradingConfigurationStore(
                url: directory.appending(path: "configuration.json"), secrets: TestSecretRevisions()
            )
            try store.save(configuration: saved, revision: fakeEngineRevision(saved), secrets: credentials, when: .paused)
            let starter = RecordingTradingStarter()
            let owner = OwnerAnswers(confirms: false)
            let model = AppModel(tradingConfigurationStore: store, tradingStarter: starter, appUnlock: try await unlocked(by: owner))
            model.isTradingUnlocked = true
            model.tradingStatus = try status(.paused)
            model.savedTradingConfiguration = saved

            await model.startTrading()

            let validated = await starter.validatedConfiguration()
            let confirmations = await owner.confirmations
            if environment == .live {
                try check(confirmations == 1, "A live start did not ask for Touch ID")
                try check(validated == nil, "A live start went ahead after Touch ID was refused")
                try check(
                    model.message?.contains("Touch ID") == true, "A refused live start did not say why: \(model.message ?? "nil")")
            } else {
                try check(confirmations == 0, "A paper start asked for Touch ID")
                try check(validated == saved, "A paper start did not go ahead")
            }
        }
        print("CopyTradingContractTests: a live start needs Touch ID and a refusal stops it; paper never asks")
    }

    /// Setup Check's grant ends two minutes after the check, and looking it over can take longer:
    /// Start Copying then checks the connections again instead of failing the start.
    private static func checkStartAfterALongLookChecksAgain(
        configuration: TradingConfiguration, secrets credentials: TradingSecrets
    ) async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "app-model-long-look-\(UUID().uuidString)", directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TradingConfigurationStore(
            url: directory.appending(path: "configuration.json"), secrets: TestSecretRevisions()
        )
        let starter = RecordingTradingStarter()
        let model = AppModel(tradingConfigurationStore: store, tradingStarter: starter)
        model.isTradingUnlocked = true
        model.tradingStatus = try status(.paused)
        let checkedAt = ContinuousClock.now
        model.now = { checkedAt }

        await model.validateTradingSettings(configuration, enteredSecrets: credentials)
        await starter.expireGrant()
        model.now = { checkedAt + .seconds(150) }
        await model.activateValidatedTradingSettings()

        let validations = await starter.validationCallCount()
        try check(validations == 2, "A start after the grant ran out did not check again, saw \(validations) checks")
        try check(
            model.savedTradingConfiguration == configuration,
            "A start after a long look at Setup Check failed: \(model.message ?? "nil")")
        print("CopyTradingContractTests: Start Copying after a long look at Setup Check checks again and starts")
    }

    /// Oct 22 2026: a setup that passed its check while copying ran read "Saving and starting…" with
    /// a spinner, and Discard Changes, Review and Start Copying beside it, though nothing was
    /// starting. Only a start under way is "Saving and starting…".
    private static func checkACheckedSetupIsNotStarting(
        configuration: TradingConfiguration, secrets credentials: TradingSecrets
    ) async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "app-model-checked-setup-\(UUID().uuidString)", directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TradingConfigurationStore(
            url: directory.appending(path: "configuration.json"), secrets: TestSecretRevisions()
        )
        let starter = RecordingTradingStarter()
        let model = AppModel(tradingConfigurationStore: store, tradingStarter: starter)
        model.isTradingUnlocked = true
        model.tradingStatus = try status(.paused)
        await model.validateTradingSettings(configuration, enteredSecrets: credentials)
        try check(model.validatedConfiguration != nil, "The setup did not pass its check")
        model.tradingStatus = try status(.running)

        let waiting = SetupChangesStatus(model)
        try check(
            !waiting.isWorking && waiting.text != L10n.string("Saving and starting…"),
            "A checked setup waiting for Start Copying read \(waiting.text)")

        model.isConfirmingActivation = true
        try check(SetupChangesStatus(model).isWorking, "A start waiting for the engine did not read as starting")
        print("CopyTradingContractTests: only a start under way reads Saving and starting")
    }

    private static func checkPlaybookLearningUsesSavedKeysAndExplainsFailures(
        configuration: TradingConfiguration, secrets: TradingSecrets
    ) async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "app-model-playbook-learning-\(UUID().uuidString)", directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TradingConfigurationStore(
            url: directory.appending(path: "configuration.json"), secrets: TestSecretRevisions()
        )
        try store.save(configuration: configuration, revision: fakeEngineRevision(configuration), secrets: secrets, when: .paused)
        let starter = RecordingTradingStarter()
        let model = AppModel(tradingConfigurationStore: store, tradingStarter: starter)
        var draft = ConnectionsDraft()
        draft.load(configuration)
        let route = draft.routes[0]

        do {
            _ = try await model.learnPlaybook(for: route, in: draft)
            throw ContractFailure("Learning ran while CopyTrading was locked")
        } catch TradingSettingsError.invalidConfiguration {}
        model.isTradingUnlocked = true

        let learned = try await model.learnPlaybook(for: route, in: draft)
        let request = await starter.learningRequest()
        try check(learned.playbook == "加了 means buy", "The learned draft was not returned")
        try check(
            request?.discordToken == secrets.discordToken && request?.providerAPIKey == secrets.providerAPIKey,
            "Blank Setup keys did not fall back to the saved keys")
        try check(
            request?.channelID == route.channelID && request?.authorID == route.authorID.nilIfEmpty,
            "Learning read a different channel or author than the route")
        let savedAfterLearning = try store.load()?.configuration
        try check(savedAfterLearning == configuration, "Learning changed the saved setup")

        await starter.setLearningFailure("Discord refused to show this channel's history.")
        do {
            _ = try await model.learnPlaybook(for: route, in: draft)
            throw ContractFailure("A failed learning run returned a draft")
        } catch let error as TradingSettingsError {
            try check(
                error.localizedDescription == "Discord refused to show this channel's history.",
                "The engine's reason for a failed learning run was not shown")
        }
        print("CopyTradingContractTests: playbook learning used saved keys, saved nothing, and explained failures")
    }

    private static func checkPendingActivationReconcilesAfterAppReopen(
        configuration: TradingConfiguration, secrets candidateSecrets: TradingSecrets
    ) async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "app-model-activation-reopen-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let revisions = TestSecretRevisions()
        let file = directory.appending(path: "configuration.json")
        let store = TradingConfigurationStore(url: file, secrets: revisions)
        let priorSecrets = TradingSecrets(
            discordToken: "prior-source", providerAPIKey: "prior-provider",
            brokers: [TradingBrokerCredentials(accountID: "paper", key: "prior-key", secret: "prior-secret")]
        )
        try store.save(configuration: configuration, revision: fakeEngineRevision(configuration), secrets: priorSecrets, when: .paused)
        let priorSecretRevision = try secretRevision(in: Data(contentsOf: file))
        var candidate = configuration
        candidate.provider.model = "reopened-candidate-model"
        let activationID = UUID().uuidString.lowercased()
        try store.stageValidatedActivation(
            configuration: candidate,
            revision: fakeEngineRevision(candidate),
            secrets: candidateSecrets,
            activationID: activationID,
            when: .paused
        )
        let candidateSecretRevision = try secretRevision(in: Data(contentsOf: file))
        let reopenedStore = TradingConfigurationStore(url: file, secrets: revisions)
        let starter = RecordingTradingStarter()
        let candidateRevision = fakeEngineRevision(candidate)
        try await starter.setActivationStatus(
            TradingActivationStatus(
                requestedActivationID: activationID,
                activationID: activationID,
                candidateRevision: candidateRevision,
                committedRevision: nil,
                phase: .starting,
                runtimeState: .starting,
                errorCode: nil
            ), state: .starting, activeAccounts: 0)
        let reopenedModel = AppModel(tradingConfigurationStore: reopenedStore, tradingStarter: starter)

        await reopenedModel.reconcilePendingTradingActivation(using: starter)
        let inProgress = try reopenedStore.pendingActivation()
        try check(
            inProgress?.activationID == activationID,
            "Process reopen discarded an engine activation still in progress")
        let stableAfterReopen = try reopenedStore.load()
        try check(
            stableAfterReopen?.configuration == configuration,
            "Process reopen published a candidate before engine acknowledgement")
        try check(revisions.storedCount == 2, "Process reopen discarded rollback credentials")

        // Seconds into a normal start an account is already running while the engine is still
        // committing; that is progress, and must not read as a stuck activation.
        try await starter.setActivationStatus(
            TradingActivationStatus(
                requestedActivationID: activationID,
                activationID: activationID,
                candidateRevision: candidateRevision,
                committedRevision: nil,
                phase: .starting,
                runtimeState: .starting,
                errorCode: nil
            ), state: .degraded, activeAccounts: 1)
        await reopenedModel.reconcilePendingTradingActivation(using: starter)
        try check(
            reopenedModel.message == AppModel.pendingSetupMessage,
            "A start still committing with an account running was reported as unresolved: \(reopenedModel.message ?? "nil")")

        try await starter.setActivationStatus(
            TradingActivationStatus(
                requestedActivationID: activationID,
                activationID: activationID,
                candidateRevision: candidateRevision,
                committedRevision: candidateRevision,
                phase: .ready,
                runtimeState: .running,
                errorCode: nil,
                committedActivationID: activationID
            ), state: .running, activeAccounts: 1)
        await reopenedModel.reconcilePendingTradingActivation(using: starter)
        let finalJournal = try reopenedStore.pendingActivation()
        try check(
            finalJournal == nil,
            "Reopened app did not clear the acknowledged activation journal")
        let committed = try reopenedStore.load()
        try check(
            committed?.configuration == candidate,
            "Reopened app did not publish the committed candidate")
        try check(
            committed?.secrets == candidateSecrets,
            "Reopened app did not publish the committed candidate credentials")
        let priorCredential = try revisions.load(revision: priorSecretRevision)
        try check(
            priorCredential == nil,
            "Reopened app retained superseded credentials after acknowledgement")
        let candidateCredential = try revisions.load(revision: candidateSecretRevision)
        try check(
            candidateCredential == candidateSecrets,
            "Reopened app lost the committed credential reference")
        print("CopyTradingContractTests: app reopen retained pending activation until engine readiness")
    }

    private static func checkFailedSameRevisionActivationRetainsPreviousSecrets(
        configuration: TradingConfiguration
    ) async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "app-model-same-revision-failure-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let revisions = TestSecretRevisions()
        let file = directory.appending(path: "configuration.json")
        let store = TradingConfigurationStore(url: file, secrets: revisions)
        let previousSecrets = TradingSecrets(
            discordToken: "working-source", providerAPIKey: "working-provider",
            brokers: [
                TradingBrokerCredentials(
                    accountID: "paper", key: "working-key", secret: "working-secret"
                )
            ]
        )
        let rotatedSecrets = TradingSecrets(
            discordToken: "rotated-source", providerAPIKey: "rotated-provider",
            brokers: [
                TradingBrokerCredentials(
                    accountID: "paper", key: "rotated-key", secret: "rotated-secret"
                )
            ]
        )
        try store.save(configuration: configuration, revision: fakeEngineRevision(configuration), secrets: previousSecrets, when: .paused)
        let previousSecretRevision = try secretRevision(in: Data(contentsOf: file))
        let activationID = UUID().uuidString.lowercased()
        try store.stageValidatedActivation(
            configuration: configuration,
            revision: fakeEngineRevision(configuration),
            secrets: rotatedSecrets,
            activationID: activationID,
            when: .paused
        )
        let candidateSecretRevision = try secretRevision(in: Data(contentsOf: file))
        let revision = fakeEngineRevision(configuration)
        let previousActivationID = UUID().uuidString.lowercased()
        let starter = RecordingTradingStarter()
        try await starter.setActivationStatus(
            TradingActivationStatus(
                requestedActivationID: activationID,
                activationID: activationID,
                candidateRevision: revision,
                committedRevision: revision,
                phase: .failed,
                runtimeState: .paused,
                errorCode: "source_unavailable",
                committedActivationID: previousActivationID
            ), state: .paused, activeAccounts: 0)

        let model = AppModel(tradingConfigurationStore: store, tradingStarter: starter)
        await model.reconcilePendingTradingActivation(using: starter)

        let pending = try store.pendingActivation()
        try check(
            pending == nil,
            "Confirmed failed same-revision Start did not roll back after reaching paused state")
        let retained = try store.load()
        try check(
            retained?.secrets == previousSecrets,
            "Failed same-revision Start replaced working credentials")
        let retainedPriorSecret = try revisions.load(revision: previousSecretRevision)
        try check(
            retainedPriorSecret == previousSecrets,
            "Failed same-revision Start deleted the prior credential reference")
        let discardedCandidateSecret = try revisions.load(revision: candidateSecretRevision)
        try check(
            discardedCandidateSecret == nil,
            "Failed same-revision Start retained the uncommitted candidate credential")
        print("CopyTradingContractTests: failed same-revision Start preserved prior credentials")
    }

    /// The owner's case: Alpaca keys for one account under a name another Alpaca account's record
    /// already has. The banner names the account, says what happened and what to do, and Start
    /// Copying works again straight away, with no pause first.
    private static func checkAFailedStartNamesTheAccountAndCanBeTriedAgain(
        configuration: TradingConfiguration, secrets: TradingSecrets
    ) async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "app-model-failed-start-\(UUID().uuidString)", directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TradingConfigurationStore(
            url: directory.appending(path: "configuration.json"), secrets: TestSecretRevisions()
        )
        let revision = fakeEngineRevision(configuration)
        let activationID = UUID().uuidString.lowercased()
        try store.stageValidatedActivation(
            configuration: configuration, revision: revision, secrets: secrets, activationID: activationID,
            when: .paused
        )
        let starter = RecordingTradingStarter()
        try await starter.setActivationStatus(
            TradingActivationStatus(
                requestedActivationID: activationID, activationID: activationID, candidateRevision: revision,
                committedRevision: nil, phase: .failed, runtimeState: .failed,
                errorCode: "broker_keys_rejected"
            ), state: .failed, activeAccounts: 0)
        await starter.setTradingStatus(
            try TradingStatusBuilder(.failed).error("broker_keys_rejected")
                .account("paper", "failed", error: "broker_keys_rejected").build())

        let model = AppModel(tradingConfigurationStore: store, tradingStarter: starter)
        model.isTradingUnlocked = true
        await model.reconcilePendingTradingActivation(using: starter)
        let message = model.message ?? ""
        try check(
            message
                == "Copying didn't start. paper didn't open: Alpaca didn't accept its API keys. Paste them again from your Alpaca dashboard.",
            "A failed start must name the account, what happened, and what to do: \(message)")

        model.setupDraft.load(configuration)
        model.setupDraft.discordToken = secrets.discordToken
        model.setupDraft.providerAPIKey = secrets.providerAPIKey
        model.setupDraft.accounts[0].key = secrets.brokers[0].key
        model.setupDraft.accounts[0].secret = secrets.brokers[0].secret
        try check(model.tradingStatus?.state == .failed, "The engine reports the failed start")
        try check(model.canCheckAndStart, "Start Copying stayed off after a failed start, with no way to try again")
        let card = SetupChangesStatus(model)
        try check(
            card.text == "Ready to start",
            "After a failed start the card must offer a new start, not say the setup changed: \(card.text)")
        print("CopyTradingContractTests: a failed start names the account, what happened, and what to do, and can be tried again")
    }

    /// Each reason a start can fail reads as its own sentence or two, never a bare code.
    private static func checkEveryStartFailureSaysWhatToDo() throws {
        let accountCases: [(String, String)] = [
            ("alpaca_account_shared", "another account in this setup uses keys for the same Alpaca account."),
            ("record_unreadable", "its record on this Mac couldn't be read, so nothing was changed."),
            ("broker_keys_rejected", "Alpaca didn't accept its API keys."),
            ("broker_unreachable", "Alpaca couldn't be reached."),
            ("account_in_use", "another CopyTrading on this Mac is copying into it."),
            ("outside_open_orders", "Cancel them at Alpaca, then start again."),
            ("broker_account_inactive", "Alpaca hasn't activated this account yet."),
            ("account_unavailable", "Diagnostics at the bottom of the sidebar has the details."),
        ]
        for (code, words) in accountCases {
            let account = try JSONDecoder().decode(
                TradingAccountStatus.self,
                from: Data(#"{"id":"zhap-account-2","state":"failed","error_code":"\#(code)"}"#.utf8))
            let text = StartFailure.text(errorCode: code, accounts: [account], modelService: "DeepSeek")
            try check(text.hasPrefix("zhap-account-2 didn't open"), "\(code) must name the account: \(text)")
            try check(text.contains(words), "\(code) must say what happened and what to do: \(text)")
        }
        // Two names for one Alpaca account are said together, so the owner sees which two.
        let sharing = try TradingStatusBuilder(.failed).error("alpaca_account_shared")
            .account("main", "failed", error: "alpaca_account_shared")
            .account("spare", "failed", error: "alpaca_account_shared").build()
        let shared = StartFailure.text(
            errorCode: sharing.errorCode, accounts: sharing.accounts, modelService: "DeepSeek")
        try check(
            shared
                == "main and spare use keys for the same Alpaca account. Each account needs its own Alpaca account: remove one, or give it the keys of another.",
            "Two accounts with one Alpaca account's keys must be named together: \(shared)")
        let two = try TradingStatusBuilder(.failed).error("accounts_unavailable")
            .account("first", "failed", error: "broker_keys_rejected")
            .account("second", "failed", error: "account_in_use").build()
        let both = StartFailure.text(errorCode: two.errorCode, accounts: two.accounts, modelService: "DeepSeek")
        try check(
            both.hasPrefix("first didn't open: Alpaca didn't accept") && both.contains(" second didn't open: another"),
            "Each failed account is named with its own reason: \(both)")

        let serviceCases: [(String?, String)] = [
            ("source_unauthorized", "Discord didn't accept your token."),
            ("source_unavailable", "Discord couldn't be reached."),
            ("provider_unavailable", "DeepSeek couldn't be reached."),
            ("routing_change_pending", "Wait a minute, then start again."),
            ("storage_unavailable", "CopyTrading couldn't open its data on this Mac. Quit and reopen CopyTrading."),
            ("processing_unavailable", "CopyTrading stopped while starting."),
            (nil, "CopyTrading stopped while starting."),
        ]
        for (code, words) in serviceCases {
            let text = StartFailure.text(errorCode: code, accounts: [], modelService: "DeepSeek")
            try check(text.contains(words), "\(code ?? "nil") must say what happened: \(text)")
            try check(!text.contains("_"), "\(code ?? "nil") must not show a raw code: \(text)")
        }
        try check(TradingRunState.failed.isStopped && TradingRunState.paused.isStopped, "Failed and paused take a start")
        try check(!TradingRunState.running.isStopped && !TradingRunState.starting.isStopped, "A running engine is not stopped")
        print("CopyTradingContractTests: every reason a start fails names what happened and what to do")
    }

    private static func checkInterruptedSameRevisionActivationRollsBackAfterReopen(
        configuration: TradingConfiguration
    ) async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "app-model-same-revision-interrupted-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let revisions = TestSecretRevisions()
        let file = directory.appending(path: "configuration.json")
        let store = TradingConfigurationStore(url: file, secrets: revisions)
        let previousSecrets = TradingSecrets(
            discordToken: "prior-source", providerAPIKey: "prior-provider",
            brokers: [TradingBrokerCredentials(accountID: "paper", key: "prior-key", secret: "prior-secret")]
        )
        let rotatedSecrets = TradingSecrets(
            discordToken: "candidate-source", providerAPIKey: "candidate-provider",
            brokers: [TradingBrokerCredentials(accountID: "paper", key: "candidate-key", secret: "candidate-secret")]
        )
        try store.save(configuration: configuration, revision: fakeEngineRevision(configuration), secrets: previousSecrets, when: .paused)
        let previousSecretRevision = try secretRevision(in: Data(contentsOf: file))
        let activationID = UUID().uuidString.lowercased()
        try store.stageValidatedActivation(
            configuration: configuration,
            revision: fakeEngineRevision(configuration),
            secrets: rotatedSecrets,
            activationID: activationID,
            when: .paused
        )
        let candidateSecretRevision = try secretRevision(in: Data(contentsOf: file))
        let revision = fakeEngineRevision(configuration)
        let previousActivationID = UUID().uuidString.lowercased()
        let starter = RecordingTradingStarter()
        try await starter.setActivationStatus(
            TradingActivationStatus(
                requestedActivationID: activationID,
                activationID: activationID,
                candidateRevision: revision,
                committedRevision: revision,
                phase: .interrupted,
                runtimeState: .paused,
                errorCode: nil,
                committedActivationID: previousActivationID
            ), state: .paused, activeAccounts: 0)

        let reopenedStore = TradingConfigurationStore(url: file, secrets: revisions)
        let reopenedModel = AppModel(tradingConfigurationStore: reopenedStore, tradingStarter: starter)
        await reopenedModel.reconcilePendingTradingActivation(using: starter)

        let pending = try reopenedStore.pendingActivation()
        try check(pending == nil, "Confirmed interrupted same-revision Start remained pending")
        let restored = try reopenedStore.load()
        try check(
            restored?.secrets == previousSecrets,
            "Interrupted same-revision Start did not restore the prior credentials")
        let retainedPriorSecret = try revisions.load(revision: previousSecretRevision)
        try check(
            retainedPriorSecret == previousSecrets,
            "Interrupted same-revision Start deleted the prior credential reference")
        let discardedCandidateSecret = try revisions.load(revision: candidateSecretRevision)
        try check(
            discardedCandidateSecret == nil,
            "Interrupted same-revision Start retained an uncommitted credential reference")
        print("CopyTradingContractTests: interrupted same-revision Start restored prior credentials after reopen")
    }

    /// A resume of the saved setup the engine marked failed (Discord dropped while starting) but
    /// kept copying with: the setup is in effect, so it is not left pending, and limits can still
    /// be changed at once.
    private static func checkResumeThatKeepsCopyingIsApplied(
        configuration: TradingConfiguration, secrets: TradingSecrets
    ) async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "app-model-resume-keeps-copying-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "configuration.json")
        let store = TradingConfigurationStore(url: file, secrets: TestSecretRevisions())
        let revision = fakeEngineRevision(configuration)
        try store.save(configuration: configuration, revision: revision, secrets: secrets, when: .paused)
        let activationID = UUID().uuidString.lowercased()
        try store.stageSavedResume(activationID: activationID, revision: revision, when: .paused)
        let starter = RecordingTradingStarter()
        try await starter.setActivationStatus(
            TradingActivationStatus(
                requestedActivationID: activationID,
                activationID: activationID,
                candidateRevision: revision,
                committedRevision: revision,
                phase: .failed,
                runtimeState: .degraded,
                errorCode: "source_unavailable",
                committedActivationID: UUID().uuidString.lowercased()
            ), state: .degraded, activeAccounts: 1)

        let model = AppModel(tradingConfigurationStore: store, tradingStarter: starter)
        await model.reconcilePendingTradingActivation(using: starter)

        let pending = try store.pendingActivation()
        try check(pending == nil, "A resume the engine keeps copying with stayed pending")
        let kept = try store.load()?.secrets
        try check(kept == secrets, "Settling a running resume changed the saved keys")
        try check(model.message == nil, "A running resume still said the setup can't be confirmed: \(model.message ?? "")")
        print("CopyTradingContractTests: a resume that keeps copying is applied, not left pending")
    }

    private static func checkReadySameRevisionActivationFinalizesAfterStoppedReopen(
        configuration: TradingConfiguration
    ) async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "app-model-same-revision-ready-stopped-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let revisions = TestSecretRevisions()
        let file = directory.appending(path: "configuration.json")
        let store = TradingConfigurationStore(url: file, secrets: revisions)
        let previousSecrets = TradingSecrets(
            discordToken: "prior-source", providerAPIKey: "prior-provider",
            brokers: [TradingBrokerCredentials(accountID: "paper", key: "prior-key", secret: "prior-secret")]
        )
        let rotatedSecrets = TradingSecrets(
            discordToken: "ready-source", providerAPIKey: "ready-provider",
            brokers: [TradingBrokerCredentials(accountID: "paper", key: "ready-key", secret: "ready-secret")]
        )
        try store.save(configuration: configuration, revision: fakeEngineRevision(configuration), secrets: previousSecrets, when: .paused)
        let previousSecretRevision = try secretRevision(in: Data(contentsOf: file))
        let activationID = UUID().uuidString.lowercased()
        try store.stageValidatedActivation(
            configuration: configuration,
            revision: fakeEngineRevision(configuration),
            secrets: rotatedSecrets,
            activationID: activationID,
            when: .paused
        )
        let candidateSecretRevision = try secretRevision(in: Data(contentsOf: file))
        let revision = fakeEngineRevision(configuration)
        let starter = RecordingTradingStarter()
        try await starter.setActivationStatus(
            TradingActivationStatus(
                requestedActivationID: activationID,
                activationID: activationID,
                candidateRevision: revision,
                committedRevision: revision,
                phase: .stopped,
                runtimeState: .paused,
                errorCode: nil,
                committedActivationID: activationID
            ), state: .paused, activeAccounts: 0)

        let reopenedStore = TradingConfigurationStore(url: file, secrets: revisions)
        let reopenedModel = AppModel(tradingConfigurationStore: reopenedStore, tradingStarter: starter)
        await reopenedModel.reconcilePendingTradingActivation(using: starter)

        let pending = try reopenedStore.pendingActivation()
        try check(pending == nil, "Ready activation was not finalized after stop and app reopen")
        let committed = try reopenedStore.load()
        try check(
            committed?.secrets == rotatedSecrets,
            "Ready activation did not retain its committed rotated credentials")
        let priorSecret = try revisions.load(revision: previousSecretRevision)
        try check(
            priorSecret == nil,
            "Ready activation retained the superseded credential after durable commit")
        let candidateSecret = try revisions.load(revision: candidateSecretRevision)
        try check(
            candidateSecret == rotatedSecrets,
            "Ready activation lost its committed credential after stop and app reopen")
        print("CopyTradingContractTests: ready activation finalized after stop and app reopen")
    }

    private static func checkRejectedValidationDoesNotPersist(
        configuration: TradingConfiguration, secrets: TradingSecrets
    ) async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "app-model-rejected-validation-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TradingConfigurationStore(
            url: directory.appending(path: "configuration.json"), secrets: TestSecretRevisions()
        )
        let starter = RecordingTradingStarter()
        await starter.setValidationActivatable(false)
        let model = AppModel(tradingConfigurationStore: store, tradingStarter: starter)
        model.isTradingUnlocked = true
        model.tradingStatus = try status(.paused)

        await model.validateTradingSettings(configuration, enteredSecrets: secrets)
        let rejected = try store.load()
        try check(rejected == nil, "Failed capability validation persisted a draft")
        try check(model.tradingValidation?.report.activatable == false, "Failed capability was hidden")
        await model.activateValidatedTradingSettings()
        let stillEmpty = try store.load()
        try check(stillEmpty == nil, "Rejected capability report allowed activation")
        let rejectedStart = await starter.startedConfiguration()
        try check(rejectedStart == nil, "Rejected validation called Start")
        print("CopyTradingContractTests: failed capability validation left storage unchanged")
    }

    private static func checkValidationCancellationDoesNotPersist(
        configuration: TradingConfiguration, secrets: TradingSecrets
    ) async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "app-model-cancelled-validation-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TradingConfigurationStore(
            url: directory.appending(path: "configuration.json"), secrets: TestSecretRevisions()
        )
        let starter = RecordingTradingStarter()
        await starter.setValidationSuspended(true)
        let model = AppModel(tradingConfigurationStore: store, tradingStarter: starter)
        model.isTradingUnlocked = true
        model.tradingStatus = try status(.paused)

        model.beginTradingValidation(configuration, enteredSecrets: secrets)
        for _ in 0..<1_000 {
            if await starter.validationCallCount() > 0 { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        model.cancelTradingActivation()
        for _ in 0..<1_000 {
            if !model.isValidatingTrading { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        let cancelled = try store.load()
        try check(cancelled == nil, "Cancelled validation wrote config or secrets")
        try check(!model.isValidatingTrading, "Cancelled validation stayed pending")
        try check(model.tradingValidation == nil, "Cancelled validation retained a capability grant")
        try check(model.message?.contains("cancelled") == true, "Cancellation was not shown to the operator")
        print("CopyTradingContractTests: cancelled validation cleared pending grant and left storage unchanged")
    }

    /// Start Copying checks the draft first: a failed check keeps the typed keys, opens the
    /// results, and saves nothing; a later edit discards it; a passing check saves and starts.
    /// One service's check goes over the pipe as `check_connection`, carrying only that service
    /// and its key, and comes back as a single capability check.
    private static func checkConnectionClientRequest(provider: TradingProviderConfiguration) async throws {
        let wire = Data(
            """
            {"version":1,"request_id":"check-request","ok":{"type":"connection_check",
             "check":{"name":"model","state":"failed","subject":null,"environment":null,"identity":null,
              "adapter":"deepseek","reason_code":"model_not_found","suggestion":"deepseek-flash","symbols":[]}}}
            """.utf8)
        let transport = AccountPageTransport(responseFixture: wire)
        let result = try await EngineClient(transport: transport).checkConnection(
            .model(provider, apiKey: "typed-model-key"))
        guard
            let sent = try JSONSerialization.jsonObject(with: await transport.sentRequest() ?? Data()) as? [String: Any],
            let connection = sent["connection"] as? [String: Any]
        else { throw ContractFailure("Connection check request was not JSON") }
        try check(sent["operation"] as? String == "check_connection", "Wrong connection check IPC operation")
        try check(connection["kind"] as? String == "model", "The check did not name its service")
        try check(connection["api_key"] as? String == "typed-model-key", "The check did not carry the typed key")
        try check(sent["secrets"] == nil && sent["configuration"] == nil, "A single check sent the whole setup")
        try check(
            result.state == .failed && result.reasonCode == "model_not_found" && result.suggestion == "deepseek-flash",
            "The connection check result was not decoded")
        print("CopyTradingContractTests: one connection is checked alone over the pipe")
    }

    /// Connect checks a service with the key typed for it, or the saved one when the field is
    /// blank; the answer shows until something it checked is edited.
    private static func checkOneConnectionUsesSavedKeysAndFollowsEdits(
        configuration: TradingConfiguration, secrets: TradingSecrets
    ) async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "app-model-connection-check-\(UUID().uuidString)", directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TradingConfigurationStore(
            url: directory.appending(path: "configuration.json"), secrets: TestSecretRevisions()
        )
        try store.save(
            configuration: configuration, revision: fakeEngineRevision(configuration), secrets: secrets, when: .paused)
        let starter = RecordingTradingStarter()
        let model = AppModel(tradingConfigurationStore: store, tradingStarter: starter)
        model.isTradingUnlocked = true
        model.setupDraft.load(configuration)

        let interpreter = await model.checkConnection(.interpreter)
        guard case .model(_, let apiKey)? = await starter.checkedConnections().last else {
            throw ContractFailure("Connect did not check the interpreter")
        }
        try check(apiKey == secrets.providerAPIKey, "A blank key field did not fall back to the saved key")
        try check(interpreter?.state == .ready, "A passing check was not returned")
        try check(
            ConnectionStatus.interpreter(model)?.text == L10n.string("Connected"),
            "A passing check did not show the interpreter as connected")

        model.setupDraft.modelName += "-typo"
        try check(model.connectionCheckResult(.interpreter) == nil, "Editing the model kept the old check")

        await starter.setConnectionCheckFails(true)
        model.setupDraft.discordToken = "typed-discord-token"
        let discord = await model.checkConnection(.discord)
        guard case .source(_, let token)? = await starter.checkedConnections().last else {
            throw ContractFailure("Connect did not check Discord")
        }
        try check(token == "typed-discord-token", "A typed token was not the one checked")
        try check(discord?.state == .failed, "A failing check was not returned")
        try check(
            ConnectionStatus.discord(model)?.text == L10n.string("Couldn't connect"),
            "A failing check did not show on the Discord row")
        try check(!model.setupProgress.isDone(.discord), "A failed check still ticked the Discord step")

        // While copying runs the saved setup, an edited token's failed check still speaks for its
        // row, and an edit elsewhere leaves the guru saved.
        model.savedTradingConfiguration = configuration
        model.tradingStatus = try TradingStatusBuilder(.running).connected().build()
        try check(
            ConnectionStatus.discord(model)?.text == L10n.string("Couldn't connect"),
            "A failed check of an edited token showed the running setup's Connected")
        model.setupDraft.load(configuration)
        model.setupDraft.clearSecrets()
        try check(
            ConnectionStatus.discord(model)?.text == L10n.string("Connected"),
            "An unedited Discord row did not show the running engine's reading")
        let route = model.setupDraft.routes[0]
        try check(ConnectionStatus.guru(route, in: model).text == L10n.string("Copying"), "A saved guru did not read Copying")
        model.setupDraft.accounts[0].policy.maxOrderUSD = "987"
        try check(
            ConnectionStatus.guru(route, in: model).text == L10n.string("Copying"),
            "Changing an account's limit marked an unchanged guru as not saved")
        model.setupDraft.routes[0].playbook += " Edited."
        try check(
            ConnectionStatus.guru(model.setupDraft.routes[0], in: model).text == L10n.string("Not saved yet"),
            "Editing a guru's playbook did not mark that guru as not saved")
        model.tradingStatus = try status(.paused)

        model.isTradingUnlocked = false
        let locked = await model.checkConnection(.discord)
        try check(locked == nil, "A locked app checked a connection")
        print("CopyTradingContractTests: Connect checks one service with typed or saved keys and follows edits")
    }

    /// A setup saved while the chat filter existed loads with the filter dropped, its key in the
    /// Keychain item is ignored, and Start stages the revision the engine reports for the setup
    /// as it is now, not the one saved with the filter in it.
    private static func checkSetupSavedWithTheRetiredChatFilterLoadsAndStartsOnTheEnginesRevision(
        configuration: TradingConfiguration, secrets: TradingSecrets
    ) async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "app-model-retired-chat-filter-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "configuration.json")
        let store = TradingConfigurationStore(url: file, secrets: TestSecretRevisions())
        let staleRevision = String(repeating: "a", count: 64)
        try store.save(configuration: configuration, revision: staleRevision, secrets: secrets, when: .paused)
        guard var saved = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any],
            var inner = saved["configuration"] as? [String: Any]
        else { throw ContractFailure("The saved setup was not a JSON object") }
        inner["triage"] = ["provider": "openai-decisions", "model": "gpt-6-luna", "route_threshold": 0.9]
        saved["configuration"] = inner
        try JSONSerialization.data(withJSONObject: saved).write(to: file)

        let loaded = try store.load()
        try check(
            loaded?.configuration == configuration, "A setup saved with the retired chat filter did not load without it")
        let oldSecrets = Data(
            #"{"discord_token":"d","provider_api_key":"p","brokers":[],"triage_api_key":"old-openai-key"}"#.utf8)
        try check(
            (try? JSONDecoder().decode(TradingSecrets.self, from: oldSecrets))?.providerAPIKey == "p",
            "Saved keys with the retired chat-filter key did not load")

        let engineRevision = fakeEngineRevision(configuration)
        try store.stageSavedResume(
            activationID: UUID().uuidString.lowercased(), revision: engineRevision, when: .paused)
        let pending = try store.pendingActivation()
        try check(
            pending?.candidateRevision == engineRevision,
            "Start staged the revision saved with the retired chat filter")
        print("CopyTradingContractTests: a setup saved with the retired chat filter loads and starts on the engine's revision")
    }

    private static func checkSetupCheckKeepsKeysAndFollowsEdits(
        configuration: TradingConfiguration, secrets: TradingSecrets
    ) async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "app-model-setup-check-\(UUID().uuidString)", directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TradingConfigurationStore(
            url: directory.appending(path: "configuration.json"), secrets: TestSecretRevisions()
        )
        let starter = RecordingTradingStarter()
        await starter.setValidationActivatable(false)
        let model = AppModel(tradingConfigurationStore: store, tradingStarter: starter)
        model.isTradingUnlocked = true
        model.tradingStatus = try status(.paused)

        model.setupDraft.load(configuration)
        model.setupDraft.discordToken = secrets.discordToken
        model.setupDraft.providerAPIKey = secrets.providerAPIKey
        model.setupDraft.accounts[0].key = secrets.brokers[0].key
        model.setupDraft.accounts[0].secret = secrets.brokers[0].secret
        try check(model.hasUnsavedSetupChanges, "A first setup with typed keys did not count as unsaved")
        try check(model.setupProgress.isReadyToCheck, "A complete draft did not read as ready to check")

        model.checkAndStartCopying()
        for _ in 0..<1_000 where model.isValidatingTrading || model.tradingValidation == nil {
            try await Task.sleep(for: .milliseconds(1))
        }
        try check(model.tradingValidation?.report.activatable == false, "The failing check did not report its failure")
        try check(model.isShowingSetupCheck, "A failed check did not open its results")
        try check(
            model.setupDraft.discordToken == secrets.discordToken && model.setupDraft.accounts[0].key == secrets.brokers[0].key,
            "A failed check wiped the keys the owner typed")
        try check(!model.canStartCopyingFromCheck, "A failed check allowed Start Copying")

        let afterFailure = try store.load()
        try check(afterFailure == nil, "A failed check saved the setup")

        model.setupDraft.providerAPIKey = "a-different-key"
        model.setupDraftDidChange()
        try check(model.tradingValidation == nil, "Changing a typed key after the check kept the check")
        try check(model.message == AppModel.changedAfterCheckMessage, "A discarded check did not explain itself")

        await starter.setValidationActivatable(true)
        model.checkAndStartCopying()
        for _ in 0..<2_000 where model.savedTradingConfiguration == nil {
            try await Task.sleep(for: .milliseconds(1))
        }
        try check(model.savedTradingConfiguration != nil, "A passing check did not save and start the setup")
        let afterPass = try store.load()
        try check(afterPass != nil, "A passing check did not write the setup")
        print("CopyTradingContractTests: Start Copying checks first, keeps typed keys, and starts once the check passes")
    }

    /// New keys typed for an account wait in the draft; that account's own Start Copying checks
    /// and saves them, as Connections' does, instead of starting the saved setup with the old keys.
    private static func checkAccountStartUsesTheEdits(
        configuration: TradingConfiguration, secrets: TradingSecrets
    ) async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "app-model-account-start-edits-\(UUID().uuidString)", directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TradingConfigurationStore(
            url: directory.appending(path: "configuration.json"), secrets: TestSecretRevisions()
        )
        try store.save(
            configuration: configuration, revision: fakeEngineRevision(configuration), secrets: secrets, when: .paused)
        let starter = RecordingTradingStarter()
        let model = AppModel(tradingConfigurationStore: store, tradingStarter: starter)
        model.isTradingUnlocked = true
        model.tradingStatus = try status(.paused)
        model.savedTradingConfiguration = configuration
        model.hasTradingSecrets = true

        model.setupDraft.load(configuration)
        model.setupDraft.discordToken = secrets.discordToken
        model.setupDraft.providerAPIKey = secrets.providerAPIKey
        model.setupDraft.accounts[0].key = "replacement-broker-key"
        model.setupDraft.accounts[0].secret = "replacement-broker-secret"
        try check(model.hasUnsavedSetupChanges, "New broker keys did not count as unsaved")

        await model.startCopying(
            into: "paper", environment: .paper, feature: AccountFeatureModel(), using: RecordingAccountActions())
        for _ in 0..<2_000 where (try? store.load())??.secrets.brokers.first?.key != "replacement-broker-key" {
            try await Task.sleep(for: .milliseconds(1))
        }
        let saved = try store.load()
        try check(
            saved?.secrets.brokers.first?.key == "replacement-broker-key",
            "An account's Start Copying started the saved setup instead of the new keys: \(model.message ?? "nil")")
        print("CopyTradingContractTests: an account's Start Copying checks and saves the edits waiting in Connections")
    }

    /// A limit changed while copying runs is applied in one press: copying pauses, the new setup
    /// is checked and starts. A change whose check fails leaves the saved setup copying again.
    /// Limits alone go straight to the running engine: no check, no pause, no Apply Changes, and
    /// the saved revision is the engine's, so the next Start matches it.
    private static func checkLimitOnlyChangesApplyWithoutAPause(
        configuration: TradingConfiguration, secrets: TradingSecrets
    ) async throws {
        print("CopyTradingContractTests: limits alone apply to running copying with no pause and no Apply Changes")
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "app-model-live-limits-\(UUID().uuidString)", directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TradingConfigurationStore(
            url: directory.appending(path: "configuration.json"), secrets: TestSecretRevisions()
        )
        let starter = RecordingTradingStarter()
        let model = AppModel(tradingConfigurationStore: store, tradingStarter: starter)
        model.isTradingUnlocked = true
        model.tradingStatus = try status(.paused)
        await model.validateTradingSettings(configuration, enteredSecrets: secrets)
        await model.activateValidatedTradingSettings()
        try check(model.tradingStatus?.state == .running, model.message ?? "The first setup did not start")
        model.syncSetupDraftWithSaved()

        model.setupDraft.accounts[0].policy.maxOrderUSD = "500"
        try check(model.hasOnlyLimitChanges, "A limit edit did not read as limits only")
        try check(!model.hasSetupToStart, "A limit edit still asked for Apply Changes")
        let before = await starter.events().count
        let saved = await model.saveLimitOnlyChanges()
        try check(saved == true, model.message ?? "The new limit was not saved")
        let during = Array(await starter.events().dropFirst(before))
        try check(during == ["update_limits"], "Saving limits did more than hand them over: \(during)")
        try check(model.savedTradingConfiguration?.accounts[0].policy.maxOrderUSD == "500", "The saved setup kept the old limit")
        try check(!model.hasUnsavedSetupChanges, "The saved limit still read as a change, with its pill")
        try check(model.limitsSavedAccountIDs == ["paper"], "The account didn't say its limits were saved")
        try check(model.tradingStatus?.state == .running, "Saving limits stopped copying")
        guard let loaded = try store.load() else { throw ContractFailure("The saved setup is missing") }
        try check(loaded.configuration.accounts[0].policy.maxOrderUSD == "500", "The limit was not written to disk")
        try check(loaded.secrets == secrets, "Saving limits changed the saved keys")

        // The engine and the app agree on the revision: pausing and resuming the saved setup
        // commits it rather than rolling it back.
        await model.pauseTrading()
        model.tradingStatus = try status(.paused)
        await model.startTrading(resumingSavedSetup: true)
        try check(model.tradingStatus?.state == .running, model.message ?? "The saved setup didn't resume")
        let unconfirmed = try store.pendingActivation()
        try check(unconfirmed == nil, "Resuming left the activation unconfirmed")
        try check(model.savedTradingConfiguration?.accounts[0].policy.maxOrderUSD == "500", "Resuming rolled the limit back")

        // Anything beyond limits still waits for the full check.
        model.setupDraft.modelName = "other-model"
        model.setupDraft.accounts[0].policy.maxOrderUSD = "600"
        let afterResume = await starter.events().count
        let beyond = await model.saveLimitOnlyChanges()
        try check(beyond == nil, "A change beyond limits skipped the check")
        let afterBeyond = await starter.events().count
        try check(afterBeyond == afterResume, "A change beyond limits reached the engine")
        try check(model.hasSetupToStart && !model.hasOnlyLimitChanges, "A change beyond limits hid Apply Changes")
    }

    private static func checkApplyChangesWhileCopying(
        configuration: TradingConfiguration, secrets: TradingSecrets
    ) async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "app-model-apply-changes-\(UUID().uuidString)", directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TradingConfigurationStore(
            url: directory.appending(path: "configuration.json"), secrets: TestSecretRevisions()
        )
        let starter = RecordingTradingStarter()
        let model = AppModel(tradingConfigurationStore: store, tradingStarter: starter)
        model.isTradingUnlocked = true
        model.tradingStatus = try status(.paused)
        model.setupDraft.load(configuration)
        model.setupDraft.discordToken = secrets.discordToken
        model.setupDraft.providerAPIKey = secrets.providerAPIKey
        model.setupDraft.accounts[0].key = secrets.brokers[0].key
        model.setupDraft.accounts[0].secret = secrets.brokers[0].secret
        model.checkAndStartCopying()
        for _ in 0..<2_000 where model.savedTradingConfiguration == nil || model.isActivatingTrading {
            try await Task.sleep(for: .milliseconds(1))
        }
        if model.isShowingSetupCheck {
            model.checkAndStartCopying()
            for _ in 0..<2_000 where model.tradingStatus?.state != .running || model.isActivatingTrading {
                try await Task.sleep(for: .milliseconds(1))
            }
        }
        try check(model.tradingStatus?.state == .running, model.message ?? "The first setup did not start")
        try check(model.savedTradingConfiguration != nil, "The first setup was not saved")

        // A higher maximum per order, applied while copying runs.
        model.setupDraft.accounts[0].policy.maxOrderUSD = "200"
        model.selectedScreen = .account("primary")
        try check(model.isCopyingSavedSetup && model.canCheckAndStart, "A change while copying could not be applied")
        let beforeApply = await starter.events().count
        model.checkAndStartCopying()
        // A second press while the first apply runs must not cancel it or start a second one.
        try check(model.isApplyingChanges && !model.canCheckAndStart, "Start Copying stayed pressable during an apply")
        model.checkAndStartCopying()
        for _ in 0..<4_000 where model.savedTradingConfiguration?.accounts[0].policy.maxOrderUSD != "200" {
            try await Task.sleep(for: .milliseconds(1))
        }
        let duringApply = Array(await starter.events().dropFirst(beforeApply))
        try check(
            duringApply.filter { $0 == "start" }.count == 1 && duringApply.filter { $0 == "pause" }.count == 1,
            "A second press during an apply paused or started twice: \(duringApply)")
        try check(
            model.savedTradingConfiguration?.accounts[0].policy.maxOrderUSD == "200",
            "The new limit was not saved: applying \(model.isApplyingChanges) sheet \(model.isShowingSetupCheck) state \(String(describing: model.tradingStatus?.state)) message \(model.message ?? "nil") events \(await starter.events().suffix(6))"
        )
        try check(model.tradingStatus?.state == .running, "Copying did not run again with the new limit")
        let applied = await starter.events()
        guard let pause = applied.lastIndex(of: "pause") else { throw ContractFailure("Applying did not pause copying first") }
        try check(
            Array(applied[pause...]).contains("validate") && applied.last == "start", "Applying did not check and start after the pause")
        try check(!model.isPausedToApplyChanges, "A started change still counted as paused for it")
        try check(model.selectedScreen == .account("primary"), "Applying changes moved the owner off the screen they used")
        try check(model.message == "Your changes are saved, and copying uses them now.", "Applying changes did not say they took effect")
        try check(
            !model.hasUnsavedSetupChanges && !model.hasSetupToStart,
            "The changes bar stayed after a successful apply: unsaved \(model.hasUnsavedSetupChanges) typed \(model.setupDraft.hasTypedSecrets) validation \(model.tradingValidation != nil)"
        )

        // A new key alone changes nothing in the saved setup, yet it is a change to apply; once
        // applied it is in the Keychain and the draft holds no more of it.
        model.setupDraft.providerAPIKey = "a-new-model-key"
        try check(model.hasUnsavedSetupChanges && model.hasSetupToStart, "A typed key did not offer Apply Changes")
        model.checkAndStartCopying()
        for _ in 0..<4_000 where model.setupDraft.hasTypedSecrets || model.isApplyingChanges {
            try await Task.sleep(for: .milliseconds(1))
        }
        try check(
            !model.hasUnsavedSetupChanges && !model.hasSetupToStart,
            "The changes bar stayed after a new key was applied: typed \(model.setupDraft.hasTypedSecrets) applying \(model.isApplyingChanges) message \(model.message ?? "nil")"
        )
        try check(model.tradingStatus?.state == .running, "Copying did not run again with the new key")

        // A change whose check fails: the saved setup copies again at once, and the results stay
        // readable in Setup Check.
        model.setupDraft.accounts[0].policy.maxOrderUSD = "300"
        let failing = try model.setupDraft.submission().0
        await starter.setFailingConfiguration(failing)
        model.checkAndStartCopying()
        for _ in 0..<4_000 where model.message != "Your changes weren't saved, so copying continues with the saved setup." {
            try await Task.sleep(for: .milliseconds(1))
        }
        try check(model.tradingStatus?.state == .running, model.message ?? "The saved setup did not copy again")
        try check(
            model.isShowingSetupCheck && model.tradingValidation?.report.activatable == false, "The failed check's results were not shown")
        try check(model.savedTradingConfiguration?.accounts[0].policy.maxOrderUSD == "200", "A failed change replaced the saved setup")
        try check(!model.isPausedToApplyChanges, "A resumed setup still counted as paused for changes")
        await starter.setFailingConfiguration(nil)
        model.isShowingSetupCheck = false

        // A change that cannot start, such as a new account with no keys, is caught before the
        // pause: copying keeps running and nothing reaches the engine.
        model.setupDraft.accounts.append(TradingAccountDraft(name: "spare"))
        let beforeMissingKeys = await starter.events().count
        model.checkAndStartCopying()
        for _ in 0..<4_000 where model.isApplyingChanges {
            try await Task.sleep(for: .milliseconds(1))
        }
        let missingKeys = Array(await starter.events()[beforeMissingKeys...])
        try check(missingKeys.isEmpty, "A change missing its keys reached the engine: \(missingKeys)")
        try check(
            model.tradingStatus?.state == .running && !model.isPausedToApplyChanges, "A change missing its keys paused copying")
        model.setupDraft.accounts.removeLast()
        model.cancelTradingActivation()

        // Locking while the check runs: the apply stops and the saved setup copies again.
        let savedBeforeLock = model.savedTradingConfiguration?.accounts[0].policy.maxOrderUSD
        model.setupDraft.accounts[0].policy.maxOrderUSD = "250"
        await starter.setValidationSuspended(true)
        model.checkAndStartCopying()
        for _ in 0..<4_000 where !(model.isValidatingTrading && model.tradingStatus?.state == .paused) {
            try await Task.sleep(for: .milliseconds(1))
        }
        try check(model.isPausedToApplyChanges, "The apply did not pause before its check")
        await starter.setValidationSuspended(false)
        await model.lockAccess()
        try check(model.tradingStatus?.state == .running, model.message ?? "Locking mid-apply left copying paused")
        try check(
            model.savedTradingConfiguration?.accounts[0].policy.maxOrderUSD == savedBeforeLock, "Locking mid-apply saved the change")
        try check(!model.isPausedToApplyChanges, "Locking mid-apply left the apply pending")
        print("CopyTradingContractTests: Apply Changes while copying pauses, checks, and starts; a failed check resumes the saved setup")
        try await checkLiveResumeAfterApplyAsksOnce(configuration: configuration, secrets: secrets)
    }

    /// A live account's new setup asks for Touch ID once; refusing it puts the saved setup back
    /// without asking again.
    private static func checkLiveResumeAfterApplyAsksOnce(
        configuration: TradingConfiguration, secrets: TradingSecrets
    ) async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "app-model-apply-live-\(UUID().uuidString)", directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        var saved = configuration
        saved.accounts[0].environment = .live
        let store = TradingConfigurationStore(
            url: directory.appending(path: "configuration.json"), secrets: TestSecretRevisions()
        )
        try store.save(configuration: saved, revision: fakeEngineRevision(saved), secrets: secrets, when: .paused)
        let starter = RecordingTradingStarter()
        let owner = OwnerAnswers(confirms: false)
        let model = AppModel(tradingConfigurationStore: store, tradingStarter: starter, appUnlock: try await unlocked(by: owner))
        model.isTradingUnlocked = true
        model.savedTradingConfiguration = saved
        model.hasTradingSecrets = true
        model.tradingStatus = try status(.running)
        model.setupDraft.load(saved)
        model.setupDraft.accounts[0].policy.maxOrderUSD = "150"
        try check(model.isCopyingSavedSetup && model.canCheckAndStart, "A live change while copying could not be applied")

        model.checkAndStartCopying()
        for _ in 0..<4_000 where await !starter.events().contains("pause") {
            try await Task.sleep(for: .milliseconds(1))
        }
        for _ in 0..<4_000 where model.tradingStatus?.state != .running || model.isPausedToApplyChanges {
            try await Task.sleep(for: .milliseconds(1))
        }
        let confirmations = await owner.confirmations
        try check(confirmations == 1, "Applying a live change asked for Touch ID \(confirmations) times")
        try check(model.tradingStatus?.state == .running, model.message ?? "Refusing Touch ID left copying paused")
        try check(
            model.savedTradingConfiguration?.accounts[0].policy.maxOrderUSD == saved.accounts[0].policy.maxOrderUSD,
            "A refused live change was saved")
        print("CopyTradingContractTests: a refused live change asks once and puts the saved setup back")
    }

    /// A discarded check must not leave its "validated" banner behind, and locking must drop
    /// everything typed into Setup, secrets included.
    private static func checkDiscardedCheckAndLockedDraft(
        configuration: TradingConfiguration, secrets: TradingSecrets
    ) async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "app-model-discarded-check-\(UUID().uuidString)", directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TradingConfigurationStore(
            url: directory.appending(path: "configuration.json"), secrets: TestSecretRevisions()
        )
        let model = AppModel(tradingConfigurationStore: store, tradingStarter: RecordingTradingStarter())
        model.isTradingUnlocked = true
        model.tradingStatus = try status(.paused)

        await model.validateTradingSettings(configuration, enteredSecrets: secrets)
        try check(
            model.tradingValidation?.report.activatable == true && model.message == nil,
            "A passing check left a stale banner instead of letting the changes bar say it passed")
        try check(model.validatedConfiguration == configuration, "The check did not remember what it covered")

        model.cancelTradingActivation()
        try check(model.tradingValidation == nil && model.validatedConfiguration == nil, "Discard kept the check")
        try check(model.message == nil, "Discarding a check left its validated banner on screen")

        await model.validateTradingSettings(configuration, enteredSecrets: secrets)
        model.cancelTradingActivation(message: "The setup changed after it was checked. Check it again.")
        try check(
            model.message == "The setup changed after it was checked. Check it again.",
            "An invalidated check did not explain itself"
        )

        model.setupDraft.channels = "123"
        model.setupDraft.discordToken = "typed-secret"
        model.setupDraft.accounts = [TradingAccountDraft(name: "primary")]
        model.setupDraft.accounts[0].key = "typed-broker-key"
        model.setupDraftSource = configuration
        await model.lockAccess()
        try check(model.setupDraft.channels.isEmpty, "Locking kept the typed setup")
        try check(
            model.setupDraft.discordToken.isEmpty && model.setupDraft.accounts.allSatisfy { $0.key.isEmpty },
            "Locking kept a typed secret in memory"
        )
        try check(model.setupDraftSource == nil, "Locking kept the saved-copy marker")
        print("CopyTradingContractTests: discarded checks clear their banner and locking drops the typed setup")
    }

    private static func checkConfigurationWriteFailureDoesNotStart() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "app-model-config-write-failure-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = ToggleConfigurationWriter()
        let store = TradingConfigurationStore(
            url: directory.appending(path: "configuration.json"),
            secrets: TestSecretRevisions(), writer: writer
        )
        let profile = try TradingProfileBuilder().build(
            TradingProfileDraft(
                guruID: GuruIdentity.id(channelID: "123"), displayName: "Prior Guru"
            ))
        let original = TradingConfiguration(
            source: TradingSourceConfiguration(channelIDs: ["123"], authorIDs: ["456"]),
            provider: TradingProviderConfiguration(name: .anthropic, model: "prior-model"),
            accounts: [TradingAccountConfiguration(id: "paper", environment: .paper)],
            profiles: [profile],
            routes: [
                TradingRouteConfiguration(
                    channelID: "123", authorID: "456", guruID: profile.guruID,
                    profileRevision: profile.profileRevision,
                    connections: [TradingRouteConnection(accountID: "paper", fullPositionUSD: "600")]
                )
            ]
        )
        let originalSecrets = TradingSecrets(
            discordToken: "prior-source", providerAPIKey: "prior-provider",
            brokers: [TradingBrokerCredentials(accountID: "paper", key: "prior-key", secret: "prior-secret")]
        )
        try store.save(configuration: original, revision: fakeEngineRevision(original), secrets: originalSecrets, when: .paused)
        writer.failNextWrite()
        let starter = RecordingTradingStarter()
        let model = AppModel(tradingConfigurationStore: store, tradingStarter: starter)
        model.isTradingUnlocked = true
        model.tradingStatus = try status(.paused)
        model.savedTradingConfiguration = original
        var replacement = original
        replacement.provider.model = "replacement-model"
        let replacementSecrets = TradingSecrets(
            discordToken: "new-source", providerAPIKey: "new-provider",
            brokers: [TradingBrokerCredentials(accountID: "paper", key: "new-key", secret: "new-secret")]
        )

        await model.validateTradingSettings(replacement, enteredSecrets: replacementSecrets)
        await model.activateValidatedTradingSettings()
        let active = try store.load()
        try check(active?.configuration == original, "Config write failure replaced the previous file revision")
        try check(active?.secrets == originalSecrets, "Config write failure replaced prior credentials")
        let failedStart = await starter.startedConfiguration()
        try check(failedStart == nil, "Engine Start ran after the config write failed")
        try check(model.savedTradingConfiguration == original, "Config write failure updated the UI snapshot")
        print("CopyTradingContractTests: config write failure preserved prior revision and skipped Start")
    }

    private static func checkOperatorWireFixtures() throws {
        let contracts = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "Resources/Contracts")
        let request = try Data(contentsOf: contracts.appending(path: "account-control-request.json"))
        let requestJSON = try JSONSerialization.jsonObject(with: request) as? [String: Any]
        let command = AccountControlCommand(
            commandID: "control-1", accountID: "paper", action: .pause
        )
        let encodedCommand = try JSONSerialization.jsonObject(with: JSONEncoder().encode(command))
        try check(
            NSDictionary(dictionary: requestJSON?["command"] as? [String: Any] ?? [:])
                .isEqual(to: encodedCommand as? [String: Any] ?? [:]),
            "Account control command wire keys differ"
        )
        let control = try JSONDecoder().decode(
            EngineResponse.self,
            from: Data(contentsOf: contracts.appending(path: "account-control-response.json"))
        )
        guard case .accountControl(let result) = try control.successValue() else {
            throw ContractFailure("Account control response did not decode")
        }
        try check(result.command.commandID == "control-1", "Account command identity drifted")
        try check(result.entryPermission == "paused", "Account permission drifted")
        let resolutionRequest = OwnershipResolutionRequest(
            resolutionID: "resolve-1", incidentID: "incident-1", accountID: "broker-123",
            symbol: "AAPL", actor: "operator", reason: "Reviewed broker inventory",
            brokerQty: "3", externalQty: "1", lotRemaining: ["lot-1": "2"]
        )
        let resolutionFixture = try Data(contentsOf: contracts.appending(path: "ownership-resolution-request.json"))
        let resolutionJSON = try JSONSerialization.jsonObject(with: resolutionFixture) as? [String: Any]
        let encodedResolution = try JSONSerialization.jsonObject(with: JSONEncoder().encode(resolutionRequest))
        try check(
            NSDictionary(dictionary: resolutionJSON?["resolution"] as? [String: Any] ?? [:])
                .isEqual(to: encodedResolution as? [String: Any] ?? [:]),
            "Ownership resolution wire keys differ"
        )
        let resolved = try JSONDecoder().decode(
            EngineResponse.self,
            from: Data(contentsOf: contracts.appending(path: "ownership-resolution-response.json"))
        )
        guard case .ownershipResolution(let ownership) = try resolved.successValue() else {
            throw ContractFailure("Ownership resolution response did not decode")
        }
        try check(ownership.allocationRevision == 2, "Ownership allocation revision drifted")
        let accounts = try JSONDecoder().decode(
            EngineResponse.self,
            from: Data(contentsOf: contracts.appending(path: "account-overviews-response.json"))
        )
        guard case .accounts(let overviews) = try accounts.successValue() else {
            throw ContractFailure("Account overview response did not decode")
        }
        try check(overviews.items[0].accountID == "paper", "Local account identity drifted")
        try check(overviews.items[0].brokerIdentity == "broker-123", "Broker identity drifted")
        try check(overviews.items[0].totalExposureUSD == "125.50", "Decimal exposure drifted")
        try check(overviews.nextBeforeAccountID == "paper", "Account cursor drifted")
        let activity = try JSONDecoder().decode(
            EngineResponse.self,
            from: Data(contentsOf: contracts.appending(path: "source-activity-response.json"))
        )
        guard case .sourceActivity(let page) = try activity.successValue() else {
            throw ContractFailure("Source activity response did not decode")
        }
        try check(page.items[0].sourceAt == "2026-09-26T14:58:00Z", "Source time drifted")
        try check(page.items[0].sourceRevision == 1, "Source revision drifted")
        try check(
            page.items[0].sourceEvent.embeds[0].title == "Trade",
            "Original embed evidence drifted"
        )
        try check(page.items[0].destinations[0].instructionOutcomes == ["account_paused"], "Destination outcome drifted")
        guard let rejected = page.rejectedItems.first else {
            throw ContractFailure("Rejected source evidence did not decode")
        }
        try check(rejected.reason == "author_not_configured", "Rejected source reason drifted")
        try check(
            page.unavailableAccounts.map(\.accountID) == ["archive"]
                && page.unavailableAccounts.first?.reason == "timeout",
            "Unavailable account evidence did not decode"
        )
        try check(
            rejected.sourceEvent.attachments[0].status == "skipped_rejected",
            "Rejected attachment evidence status drifted"
        )
        let reviewedSource = try JSONDecoder().decode(
            EngineResponse.self,
            from: Data(contentsOf: contracts.appending(path: "manual-source-activity-response.json"))
        )
        guard case .sourceActivity(let reviewedPage) = try reviewedSource.successValue() else {
            throw ContractFailure("Reviewed source evidence did not decode")
        }
        try check(
            reviewedPage.items[0].sourceEvent.attachments[0].status == "origin_rejected",
            "Attachment evidence status drifted"
        )
        let feedResponse = try JSONDecoder().decode(
            EngineResponse.self,
            from: Data(contentsOf: contracts.appending(path: "account-feed-response.json"))
        )
        guard case .accountFeed(let feed) = try feedResponse.successValue() else {
            throw ContractFailure("Account feed response did not decode")
        }
        let sale = feed.items[0]
        try check(
            sale.kind == "sold" && sale.source == "you" && sale.side == "sell" && sale.symbol == "PM"
                && sale.shares == "1" && sale.price == "201.70" && sale.amount == "201.70"
                && sale.orderID == "lotsale-04ddab63a704",
            "The owner's sale lost what it sold"
        )
        try check(
            feed.items[3].kind == "cancelled" && feed.items[3].side == "buy" && feed.items[3].guruID == "tradez",
            "A cancelled copy lost its side or guru"
        )
        try check(
            feed.items[1].kind == "limits_changed" && feed.items[1].source == "you"
                && feed.items[1].changes == [AccountLimitChange(setting: "max_order_usd", before: "200", after: "500")],
            "A limit change lost what changed"
        )
        try check(feed.items[2].kind == "resumed" && feed.items[2].symbol == nil, "A control row drifted")
        try check(feed.nextBeforeSeq == 26, "The feed's next page drifted")
        print("CopyTradingContractTests: account command and operator read wire fixtures decoded")
    }

    private static func checkAccountPageClientRequest() async throws {
        let contracts = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "Resources/Contracts")
        let expectedRequest =
            try JSONSerialization.jsonObject(
                with: Data(contentsOf: contracts.appending(path: "get-accounts-page-request.json"))
            ) as? [String: Any]
        let response = try Data(contentsOf: contracts.appending(path: "account-overviews-response.json"))
        let transport = AccountPageTransport(responseFixture: response)
        let page = try await EngineClient(transport: transport).accounts(
            beforeAccountID: "gamma", limit: 12
        )
        guard let requestLine = await transport.sentRequest(),
            var sentRequest = try JSONSerialization.jsonObject(
                with: requestLine
            ) as? [String: Any]
        else {
            throw ContractFailure("Account page client sent no JSON request")
        }
        sentRequest["request_id"] = "req-accounts"
        try check(
            NSDictionary(dictionary: sentRequest).isEqual(to: expectedRequest ?? [:]),
            "Swift account page request differs from its shared fixture"
        )
        try check(page.items.first?.accountID == "paper", "EngineClient did not decode account page")
        try check(page.nextBeforeAccountID == "paper", "EngineClient did not decode account cursor")
        print("CopyTradingContractTests: account page request and cursor matched shared wire fixtures")

        let dayRequest =
            try JSONSerialization.jsonObject(
                with: Data(contentsOf: contracts.appending(path: "guru-day-stats-request.json"))
            ) as? [String: Any]
        let dayTransport = AccountPageTransport(
            responseFixture: try Data(contentsOf: contracts.appending(path: "guru-day-stats-response.json")))
        let day = try await EngineClient(transport: dayTransport).guruDayStats(
            dayStart: try Date("2026-10-14T07:00:00Z", strategy: .iso8601),
            dayEnd: try Date("2026-10-15T07:00:00Z", strategy: .iso8601))
        guard let dayLine = await dayTransport.sentRequest(),
            var sentDay = try JSONSerialization.jsonObject(with: dayLine) as? [String: Any]
        else {
            throw ContractFailure("Guru day client sent no JSON request")
        }
        sentDay["request_id"] = "req-guru-day"
        try check(
            NSDictionary(dictionary: sentDay).isEqual(to: dayRequest ?? [:]),
            "Swift guru day request differs from its shared fixture: \(sentDay)"
        )
        try check(
            day.gurus.map(\.guruID) == ["lee", "zhao"] && day.gurus[0].posts == 104
                && day.gurus[0].waiting.map(\.sourceID) == ["discord:1:1427"] && day.gurus[1].readSeconds == nil
                && day.unavailableAccounts.map(\.accountID) == ["archive"],
            "EngineClient did not decode the guru day"
        )

        let guruRequest =
            try JSONSerialization.jsonObject(
                with: Data(contentsOf: contracts.appending(path: "guru-activity-request.json"))
            ) as? [String: Any]
        let guruTransport = AccountPageTransport(
            responseFixture: try Data(contentsOf: contracts.appending(path: "source-activity-response.json")))
        let guruPage = try await EngineClient(transport: guruTransport).guruActivity(
            guruID: "guru-3909e2aa", beforeSeq: 1720, limit: 25)
        guard let guruLine = await guruTransport.sentRequest(),
            var sentGuru = try JSONSerialization.jsonObject(with: guruLine) as? [String: Any]
        else {
            throw ContractFailure("Guru activity client sent no JSON request")
        }
        sentGuru["request_id"] = "req-guru-activity"
        try check(
            NSDictionary(dictionary: sentGuru).isEqual(to: guruRequest ?? [:]),
            "Swift guru activity request differs from its shared fixture: \(sentGuru)"
        )
        try check(guruPage.items.first?.sequence == 7, "EngineClient did not decode a guru's posts")
    }

    /// A holdings question becomes one answer the owner confirms: copied shares the broker still
    /// holds stay copied, the rest are the owner's, and a shortfall sells the oldest buys first.
    private static func checkOwnershipResolution(configuration: TradingConfiguration) async throws {
        func incident(_ symbol: String, expected: String, actual: String) throws -> OwnershipIncidentView {
            let json =
                #"{"incident_id":"position-\#(symbol)","symbol":"\#(symbol)","expected_qty":"\#(expected)","actual_qty":"\#(actual)","observed_at":"2026-10-08T05:48:00Z","cause":"position_mismatch"}"#
            return try JSONDecoder().decode(OwnershipIncidentView.self, from: Data(json.utf8))
        }
        func position(_ symbol: String, broker: String?, lots: [(String, String)]) throws -> AccountPositionView {
            let lotJSON = lots.map {
                #"{"lot_id":"\#($0.0)","original_qty":"\#($0.1)","remaining_qty":"\#($0.1)","average_price":"10","buys":[]}"#
            }
            let brokerJSON = broker.map { #""\#($0)""# } ?? "null"
            let json =
                #"{"symbol":"\#(symbol)","owned_qty":"0","external_qty":"0","broker_qty":\#(brokerJSON),"lots":[\#(lotJSON.joined(separator: ","))]}"#
            return try JSONDecoder().decode(AccountPositionView.self, from: Data(json.utf8))
        }

        // The owner's own shares were sold outside, and nothing was copied: the old count clears.
        let sold = OwnershipFix(
            incident: try incident("F", expected: "1.54202", actual: "0"),
            position: try position("F", broker: nil, lots: []), accountID: "paper")
        try check(sold.action == "Update the Count", "A sold-off outside holding offered \(sold.action)")
        try check(
            sold.request.brokerQty == "0" && sold.request.externalQty == "0" && sold.request.lotRemaining.isEmpty,
            "Clearing an outside holding did not allocate the broker's zero")

        // More shares at the broker than were copied: the extra are the owner's.
        let extra = OwnershipFix(
            incident: try incident("ABC", expected: "5", actual: "7"),
            position: try position("ABC", broker: "7", lots: [("l1", "5")]), accountID: "paper")
        try check(extra.action == "They're Mine", "Extra broker shares offered \(extra.action)")
        try check(
            extra.headline == "2 shares of ABC that CopyTrading didn't buy", "Extra broker shares read \(extra.headline)")
        try check(extra.request.externalQty == "2" && extra.request.lotRemaining == ["l1": "5"], "Copied shares changed")

        // Fewer than were copied: the oldest buys count as sold first.
        let short = OwnershipFix(
            incident: try incident("XYZ", expected: "5", actual: "4"),
            position: try position("XYZ", broker: "4", lots: [("old", "3"), ("new", "2")]), accountID: "paper")
        try check(short.action == "They Were Sold", "A shortfall offered \(short.action)")
        try check(
            short.request.externalQty == "0" && short.request.lotRemaining == ["old": "2", "new": "2"],
            "A shortfall did not sell the oldest buy first: \(short.request.lotRemaining)")

        let actions = RecordingAccountActions()
        let feature = AccountFeatureModel()
        feature.authorizePrivateEvidence()
        await feature.refresh(using: actions)
        await feature.resolveOwnership(sold, using: actions)
        let sent = await actions.recordedResolutions()
        try check(sent == [sold.request], "The owner's answer did not reach the engine")
        try check(feature.errors["paper"] == nil, "A settled holding left an error")

        // An unreadable account the saved setup doesn't copy into is from an earlier setup.
        try check(feature.unavailable(in: nil).map(\.accountID) == ["archive"], "Unreadable accounts were dropped")
        let copiesInto = Set(configuration.accounts.map(\.id))
        try check(
            feature.unavailable(in: configuration).allSatisfy { copiesInto.contains($0.accountID) },
            "An earlier setup's unreadable account was still shown")
        print("CopyTradingContractTests: holdings questions settle with one confirmed answer")
    }

    /// Settings deletes the record of an account no longer in the setup; a refusal says why on
    /// its row, and the record stays.
    private static func checkAnEarlierAccountsRecordIsDeletedOnlyWhenAsked() async throws {
        let actions = RecordingAccountActions()
        let feature = AccountFeatureModel()
        feature.authorizePrivateEvidence()
        await feature.refresh(using: actions)
        try check(feature.accounts.contains { $0.accountID == "paper" }, "The record to delete was not read")

        await actions.refuseRecordDeletion("account_in_setup")
        await feature.deleteRecord("paper", using: actions)
        try check(feature.accounts.contains { $0.accountID == "paper" }, "A refused delete dropped the record")
        try check(
            feature.errors["paper"] == "It's in your setup again. Remove it in Connections first.",
            "A refused delete did not say why: \(feature.errors["paper"] ?? "nothing")")

        await actions.refuseRecordDeletion(nil)
        await feature.deleteRecord("paper", using: actions)
        try check(!feature.accounts.contains { $0.accountID == "paper" }, "A deleted record still showed")
        try check(feature.errors["paper"] == nil, "A deleted record kept its error")
        let deleted = await actions.deletedRecords
        try check(deleted == ["paper", "paper"], "The engine was not asked to delete the record: \(deleted)")
        print("CopyTradingContractTests: an earlier account's record is deleted only when the owner asks")
    }

    private static func checkAccountFeatureActions() async throws {
        let actions = RecordingAccountActions()
        let feature = AccountFeatureModel()
        feature.authorizePrivateEvidence()
        await feature.refresh(using: actions)
        try check(feature.accounts.first?.entryPermission == "disabled", "Fresh account status was not read")
        try check(
            feature.unavailableAccounts.map(\.accountID) == ["archive"],
            "An unreadable account was not surfaced after refresh"
        )
        let first = Task { await feature.control(accountID: "paper", action: .pause, using: actions) }
        for _ in 0..<100 {
            if await actions.firstIsWaiting() { break }
            await Task.yield()
        }
        try check(feature.pendingAccounts.contains("paper"), "Pause did not enter pending state")
        let firstReachedClient = await actions.firstIsWaiting()
        try check(firstReachedClient, "First pause did not reach the client")
        await actions.releaseFirstFailure()
        await first.value
        try check(!feature.pendingAccounts.contains("paper"), "Failed pause stayed pending")
        try check(feature.errors["paper"] != nil, "Failed pause did not show an error")
        await feature.control(accountID: "paper", action: .pause, using: actions)
        try check(feature.accounts.first?.entryPermission == "paused", "Pause did not refresh status")
        try check(feature.errors["paper"] == nil, "Successful retry did not clear the error")
        await feature.control(accountID: "paper", action: .resume, using: actions)
        try check(feature.accounts.first?.entryPermission == "enabled", "Resume did not refresh status")
        await feature.loadMoreAccounts(using: actions)
        try check(feature.accounts.map(\.accountID) == ["paper", "archive"], "Account page was not appended")
        try check(feature.nextAccountCursor == nil, "Final account page retained a cursor")
        let commands = await actions.recordedCommands()
        try check(commands.count == 3, "Account control action count drifted")
        try check(commands[0].commandID == commands[1].commandID, "Pause retry changed its identity")
        try check(commands[2].commandID != commands[1].commandID, "Resume reused pause identity")
        try check(feature.lastUpdatedAt != nil, "A successful refresh did not record its time")
        await feature.refreshHistories(using: actions)
        try check(feature.histories["paper"]?.points.count == 4, "The equity curve was not read")
        let friday = EquityHistoryWindow(range: .day, day: "2026-09-25")
        await feature.refreshHistories(window: friday, using: actions)
        try check(feature.historyWindow == friday, "Choosing a chart day was not kept")
        let askedWindow = await actions.recordedWindows().last
        try check(askedWindow == friday, "The chosen day was not asked of the engine")
        feature.clearPrivateEvidence()
        try check(feature.accounts.isEmpty && feature.errors.isEmpty, "Lock retained private account evidence")
        try check(
            feature.histories.isEmpty && feature.lastUpdatedAt == nil,
            "Lock retained the equity curve or its freshness"
        )
        print("CopyTradingContractTests: account pause failure, retry, resume, and status refresh passed")
        // An account's one switch: Stop Copying turns its buys off, Start Copying turns them back
        // on, and Start Copying on an account that already copies sends nothing.
        let model = AppModel()
        feature.authorizePrivateEvidence()
        let before = await actions.recordedCommands().count
        await model.stopCopying(into: "paper", feature: feature, using: actions)
        await model.startCopying(into: "paper", environment: .paper, feature: feature, using: actions)
        let switched = await actions.recordedCommands().dropFirst(before)
        try check(
            switched.map(\.action) == [.pause, .resume] && switched.allSatisfy { $0.accountID == "paper" },
            "Stop and Start Copying did not send pause then resume for paper: \(switched.map(\.action))")
        let copying = await actions.recordedCommands().count
        await model.startCopying(into: "paper", environment: .paper, feature: feature, using: actions)
        let again = await actions.recordedCommands().count
        try check(again == copying, "Start Copying on an account that already copies sent a command")
    }

    private static func checkAccountFeatureLockInterleavings() async throws {
        let refreshActions = SuspendedAccountActions(suspendedOperation: "accounts")
        let refreshFeature = AccountFeatureModel()
        refreshFeature.authorizePrivateEvidence()
        let refresh = Task { await refreshFeature.refresh(using: refreshActions) }
        try await waitForSuspension("accounts", from: refreshActions)
        refreshFeature.clearPrivateEvidence()
        await refreshActions.releaseSuspendedOperation()
        await refresh.value
        try check(
            refreshFeature.accounts.isEmpty && refreshFeature.activity.isEmpty,
            "A refresh completed after lock and repopulated private evidence"
        )
        refreshFeature.authorizePrivateEvidence()
        await refreshFeature.refresh(using: refreshActions)
        try check(
            refreshFeature.accounts.first?.accountID == "paper" && !refreshFeature.activity.isEmpty,
            "Unlock did not authorize a fresh private read"
        )
        await refreshActions.suspendNext("sourceActivity")
        let refreshActivity = Task { await refreshFeature.refresh(using: refreshActions) }
        try await waitForSuspension("sourceActivity", from: refreshActions)
        refreshFeature.clearPrivateEvidence()
        await refreshActions.releaseSuspendedOperation()
        await refreshActivity.value
        try check(
            refreshFeature.accounts.isEmpty && refreshFeature.activity.isEmpty,
            "A suspended second refresh read repopulated evidence after lock"
        )
        await refreshFeature.refresh(using: refreshActions)
        try check(refreshFeature.accounts.isEmpty, "A locked feature accepted a fresh read")
        refreshFeature.authorizePrivateEvidence()
        await refreshFeature.refresh(using: refreshActions)

        await refreshActions.suspendNext("accounts")
        let moreAccounts = Task { await refreshFeature.loadMoreAccounts(using: refreshActions) }
        try await waitForSuspension("accounts", from: refreshActions)
        refreshFeature.clearPrivateEvidence()
        await refreshActions.releaseSuspendedOperation()
        await moreAccounts.value
        try check(
            refreshFeature.accounts.isEmpty && !refreshFeature.isLoadingMoreAccounts,
            "A suspended account page repopulated evidence after lock"
        )
        refreshFeature.authorizePrivateEvidence()
        await refreshFeature.refresh(using: refreshActions)

        await refreshActions.suspendNext("sourceActivity")
        let moreActivity = Task { await refreshFeature.loadMore(using: refreshActions) }
        try await waitForSuspension("sourceActivity", from: refreshActions)
        refreshFeature.clearPrivateEvidence()
        await refreshActions.releaseSuspendedOperation()
        await moreActivity.value
        try check(
            refreshFeature.accounts.isEmpty && refreshFeature.activity.isEmpty,
            "A suspended activity page repopulated evidence after lock"
        )
        refreshFeature.authorizePrivateEvidence()
        await refreshFeature.refresh(using: refreshActions)

        await refreshActions.suspendNext("feed")
        let feedRead = Task {
            await refreshFeature.loadFeed(accountID: "paper", using: refreshActions)
        }
        try await waitForSuspension("feed", from: refreshActions)
        refreshFeature.clearPrivateEvidence()
        await refreshActions.releaseSuspendedOperation()
        await feedRead.value
        try check(
            refreshFeature.feeds.isEmpty && refreshFeature.errors.isEmpty,
            "A suspended feed page repopulated evidence after lock"
        )
        refreshFeature.authorizePrivateEvidence()
        await refreshFeature.refresh(using: refreshActions)
        await refreshFeature.loadFeed(accountID: "paper", using: refreshActions)
        try check(
            refreshFeature.ownerSales.map(\.item.orderID) == ["lotsale-04ddab63a704"],
            "Activity lost the owner's sale from the account feed"
        )

        let commandActions = SuspendedAccountActions(suspendedOperation: "control")
        let commandFeature = AccountFeatureModel()
        commandFeature.authorizePrivateEvidence()
        await commandFeature.refresh(using: commandActions)
        let command = Task {
            await commandFeature.control(accountID: "paper", action: .pause, using: commandActions)
        }
        try await waitForSuspension("control", from: commandActions)
        commandFeature.clearPrivateEvidence()
        await commandActions.releaseSuspendedOperation()
        await command.value
        try check(
            commandFeature.accounts.isEmpty && commandFeature.activity.isEmpty
                && commandFeature.feeds.isEmpty && commandFeature.errors.isEmpty
                && commandFeature.pendingAccounts.isEmpty,
            "An account command completed after lock and repopulated private evidence"
        )
        commandFeature.authorizePrivateEvidence()
        await commandFeature.refresh(using: commandActions)
        try check(
            commandFeature.accounts.first?.accountID == "paper",
            "Unlock after a suspended command did not permit a fresh read"
        )
        print("CopyTradingContractTests: lock invalidated suspended reads and commands; unlock reloaded")
    }

    private static func checkManualReviewActionPath() async throws {
        let contracts = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "Resources/Contracts")
        let sourceResponse = try JSONDecoder().decode(
            EngineResponse.self,
            from: Data(contentsOf: contracts.appending(path: "manual-source-activity-response.json"))
        )
        guard case .sourceActivity(let sourcePage) = try sourceResponse.successValue(),
            let source = sourcePage.items.first
        else {
            throw ContractFailure("Manual review source fixture did not decode")
        }
        try check(
            source.destinations.first(where: { $0.accountID == "archive" })?.instructionOutcomes
                == ["ambiguous_trade_details"],
            "Manual review source lost prior per-account explanation"
        )
        try check(
            source.destinations.first(where: { $0.accountID == "paper" })?.orders.first?.brokerID
                == "broker-prior-order",
            "Manual review source lost prior destination order evidence"
        )

        let transport = ManualContractTransport(contracts: contracts)
        let client = EngineClient(transport: transport)
        let feature = ManualReviewFeatureModel()
        feature.authorizePrivateEvidence()
        let instruction = ManualInstruction(
            action: .buy, symbol: "ABC", price: "25.00", fraction: "0.25"
        )
        let correctionRequest = ManualCorrectionRequest(
            correctionID: "correction-native-1", sourceID: source.sourceID,
            selectedAccountIDs: ["archive", "paper"], actor: "operator",
            reason: "Reviewed source and corrected the symbol", instructions: [instruction]
        )
        await feature.saveCorrection(source: source, request: correctionRequest, using: client)
        try check(
            feature.corrections[correctionRequest.correctionID]?.correction.revision == 1,
            "Manual correction action did not save a reviewed correction"
        )
        try check(
            feature.corrections[correctionRequest.correctionID]?.correction.selectedAccountIDs
                == ["archive", "paper"],
            "Correction action lost its selected account set"
        )

        let previewRequest = ManualPreviewRequest(
            previewID: "preview-native-paper", accountID: "paper",
            correctionID: correctionRequest.correctionID, instructionIndex: 0
        )
        await feature.preview(previewRequest, using: client)
        try check(
            feature.previews[previewRequest.previewID]?.plan?.symbol == "ABC",
            "Manual preview action did not return the server plan"
        )
        let archivePreviewRequest = ManualPreviewRequest(
            previewID: "preview-native-archive", accountID: "archive",
            correctionID: correctionRequest.correctionID, instructionIndex: 0
        )
        await feature.preview(archivePreviewRequest, using: client)
        try check(
            feature.previews[archivePreviewRequest.previewID]?.plan?.symbol == "ABC",
            "Manual preview action did not support the second selected account"
        )

        let confirmation = ManualConfirmationRequest(
            commandID: "command-native-paper", previewID: previewRequest.previewID,
            accountID: "paper", actor: "operator"
        )
        let archiveConfirmation = ManualConfirmationRequest(
            commandID: "command-native-archive", previewID: archivePreviewRequest.previewID,
            accountID: "archive", actor: "operator"
        )
        await feature.confirm([confirmation, archiveConfirmation], using: client)
        try check(
            feature.commandResults[confirmation.commandID]?.command.request.commandID
                == confirmation.commandID,
            "Manual confirmation action did not retain the durable command result"
        )
        try check(
            feature.commandOutcomes[archiveConfirmation.commandID]?.error == "account_unavailable",
            "One account failure hid another account's command result"
        )
        await feature.commandResult(accountID: "paper", commandID: confirmation.commandID, using: client)
        try check(
            feature.commandResults[confirmation.commandID]?.status == "accepted",
            "Manual command result action did not refresh the durable result"
        )

        let requests = try await transport.sentRequests().map {
            try JSONSerialization.jsonObject(with: $0) as? [String: Any] ?? [:]
        }
        let operationNames = requests.compactMap { $0["operation"] as? String }
        try check(
            requests.map { $0["operation"] as? String } == [
                "save_manual_correction", "preview_manual_order", "preview_manual_order",
                "confirm_manual_orders", "confirm_manual_orders", "get_manual_command",
            ],
            "Manual review feature did not use the typed private IPC actions: \(operationNames)"
        )
        let encodedCorrection = requests[0]["correction"] as? [String: Any] ?? [:]
        try check(
            encodedCorrection["selected_account_ids"] as? [String] == ["archive", "paper"],
            "Manual correction wire request was not canonicalized"
        )
        let encodedCommands = requests[4]["commands"] as? [[String: Any]] ?? []
        try check(
            encodedCommands.first?["command_id"] as? String == confirmation.commandID,
            "Manual confirmation wire request lost its stable identity"
        )
        let expectedRequests = [
            "manual-correction-request.json", "manual-preview-request.json",
            "manual-preview-archive-request.json", "manual-confirmation-archive-request.json",
            "manual-confirmation-paper-request.json", "manual-command-request.json",
        ]
        for (index, name) in expectedRequests.enumerated() {
            let expected =
                try JSONSerialization.jsonObject(
                    with: Data(contentsOf: contracts.appending(path: name))
                ) as? [String: Any] ?? [:]
            var actual = requests[index]
            actual["request_id"] = expected["request_id"]
            try check(
                NSDictionary(dictionary: actual).isEqual(to: expected),
                "Manual IPC request differs from shared fixture: \(name); actual=\(actual); expected=\(expected)"
            )
        }
        // A refusal's reason arrives as its code, for the view to word, not as the generic error.
        await transport.refuseNext(operation: "preview_manual_order", reason: "correction_incomplete")
        let refusedPreview = ManualPreviewRequest(
            previewID: "preview-refused", accountID: "paper",
            correctionID: correctionRequest.correctionID, instructionIndex: 0
        )
        await feature.preview(refusedPreview, using: client)
        try check(
            feature.errors[refusedPreview.previewID] == "correction_incomplete",
            "A refused preview lost its reason: \(String(describing: feature.errors[refusedPreview.previewID]))"
        )
        feature.clearPrivateEvidence()
        try check(
            feature.corrections.isEmpty && feature.previews.isEmpty
                && feature.commandOutcomes.isEmpty && feature.commandResults.isEmpty,
            "Lock retained private correction, preview, or command evidence"
        )
        feature.authorizePrivateEvidence()
        await transport.suspendNextResponse(for: "save_manual_correction")
        let saving = Task {
            await feature.saveCorrection(source: source, request: correctionRequest, using: client)
        }
        try await waitForManualResponse("save_manual_correction", from: transport)
        feature.clearPrivateEvidence()
        await transport.releaseSuspendedResponse()
        await saving.value
        try check(
            feature.corrections.isEmpty && feature.errors.isEmpty,
            "A correction response repopulated private evidence after lock"
        )
        print("CopyTradingContractTests: reviewed correction, preview, confirmation, and result used typed IPC")
    }

    private static func checkManualCorrectionReplicaRepairPath() async throws {
        let contracts = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "Resources/Contracts")
        let sourceResponse = try JSONDecoder().decode(
            EngineResponse.self,
            from: Data(contentsOf: contracts.appending(path: "manual-source-activity-response.json"))
        )
        guard case .sourceActivity(let sourcePage) = try sourceResponse.successValue(),
            let source = sourcePage.items.first
        else {
            throw ContractFailure("Manual review source fixture did not decode")
        }
        let transport = ManualContractTransport(contracts: contracts)
        await transport.returnPartialCorrectionResponseOnce()
        let client = EngineClient(transport: transport)
        let feature = ManualReviewFeatureModel()
        feature.authorizePrivateEvidence()
        let request = ManualCorrectionRequest(
            correctionID: "correction-native-1", sourceID: source.sourceID,
            selectedAccountIDs: ["archive", "paper"], actor: "operator",
            reason: "Reviewed source and corrected the symbol",
            instructions: [
                ManualInstruction(
                    action: .buy, symbol: "ABC", price: "25.00", fraction: "0.25"
                )
            ]
        )

        await feature.saveCorrection(source: source, request: request, using: client)
        try check(
            feature.corrections[request.correctionID]?.accounts.contains(where: {
                $0.status != "recorded"
            }) == true,
            "The native correction action did not retain a partial account result"
        )
        try check(
            feature.canRetryCorrection(request.correctionID),
            "A partially replicated correction did not expose its retry action"
        )
        await feature.retryCorrection(source: source, correctionID: request.correctionID, using: client)
        try check(
            feature.corrections[request.correctionID]?.accounts.allSatisfy({ $0.status == "recorded" }) == true,
            "The native retry action did not repair every selected account"
        )
        let sent = try await transport.sentRequests().map {
            try JSONSerialization.jsonObject(with: $0) as? [String: Any] ?? [:]
        }
        try check(sent.count == 2, "The correction retry did not send exactly one replay")
        var first = sent[0]
        var retry = sent[1]
        first.removeValue(forKey: "request_id")
        retry.removeValue(forKey: "request_id")
        try check(
            NSDictionary(dictionary: first).isEqual(to: retry),
            "Correction retry changed the original immutable request identity or content"
        )
        print("CopyTradingContractTests: partial correction retry preserved identity and repaired copies")
    }

    private static func checkFreshPreviewIdentityAction() async throws {
        let contracts = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "Resources/Contracts")
        let sourceResponse = try JSONDecoder().decode(
            EngineResponse.self,
            from: Data(contentsOf: contracts.appending(path: "manual-source-activity-response.json"))
        )
        guard case .sourceActivity(let sourcePage) = try sourceResponse.successValue(),
            let source = sourcePage.items.first
        else {
            throw ContractFailure("Manual review source fixture did not decode")
        }
        let transport = ManualContractTransport(contracts: contracts)
        let client = EngineClient(transport: transport)
        let feature = ManualReviewFeatureModel()
        feature.authorizePrivateEvidence()
        let correction = ManualCorrectionRequest(
            correctionID: "correction-native-1", sourceID: source.sourceID,
            selectedAccountIDs: ["archive", "paper"], actor: "operator",
            reason: "Reviewed source and corrected the symbol",
            instructions: [
                ManualInstruction(
                    action: .buy, symbol: "ABC", price: "25.00", fraction: "0.25"
                )
            ]
        )
        await feature.saveCorrection(source: source, request: correction, using: client)
        guard
            let first = await feature.refreshPreview(
                accountID: "paper", correctionID: correction.correctionID,
                instructionIndex: 0, actor: "operator", using: client
            ),
            let second = await feature.refreshPreview(
                accountID: "paper", correctionID: correction.correctionID,
                instructionIndex: 0, actor: "operator", using: client
            )
        else {
            throw ContractFailure("Fresh manual preview action did not create its requests")
        }
        try check(
            first.preview.previewID != second.preview.previewID,
            "Refreshing a preview reused its stale preview identity"
        )
        try check(
            first.confirmation.commandID != second.confirmation.commandID
                && first.confirmation.previewID == first.preview.previewID
                && second.confirmation.previewID == second.preview.previewID,
            "Refreshing a preview did not create a new bound confirmation identity"
        )
        try check(
            feature.previews[second.preview.previewID]?.request == second.preview,
            "The latest preview action did not retain its fresh server evidence"
        )
        print("CopyTradingContractTests: preview refresh created fresh preview and confirmation identities")
    }

    private static func checkDurableCommandRecoveryActionPath() async throws {
        let contracts = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "Resources/Contracts")
        let sourceResponse = try JSONDecoder().decode(
            EngineResponse.self,
            from: Data(contentsOf: contracts.appending(path: "manual-source-activity-response.json"))
        )
        guard case .sourceActivity(let sourcePage) = try sourceResponse.successValue(),
            let source = sourcePage.items.first
        else {
            throw ContractFailure("Command recovery source fixture did not decode")
        }

        let transport = ManualContractTransport(contracts: contracts)
        let client = EngineClient(transport: transport, requestTimeout: .seconds(1))
        let feature = ManualReviewFeatureModel()
        feature.authorizePrivateEvidence()
        let correction = ManualCorrectionRequest(
            correctionID: "correction-native-1", sourceID: source.sourceID,
            selectedAccountIDs: ["archive", "paper"], actor: "operator",
            reason: "Reviewed source and corrected the symbol",
            instructions: [
                ManualInstruction(action: .buy, symbol: "ABC", price: "25.00", fraction: "0.25")
            ]
        )
        await feature.saveCorrection(source: source, request: correction, using: client)
        let preview = ManualPreviewRequest(
            previewID: "preview-native-paper", accountID: "paper",
            correctionID: correction.correctionID, instructionIndex: 0
        )
        await feature.preview(preview, using: client)
        try check(
            feature.previews[preview.previewID] != nil,
            "Command recovery setup preview failed: corrections=\(String(describing: feature.corrections[correction.correctionID]?.accounts.map(\.status))), errors=\(feature.errors)"
        )
        let command = ManualConfirmationRequest(
            commandID: "command-native-paper", previewID: preview.previewID,
            accountID: "paper", actor: "operator"
        )
        await transport.dropNextResponse(for: "confirm_manual_orders")
        await feature.confirm([command], using: client)
        try check(
            feature.commandResults[command.commandID] == nil
                && feature.errors[command.commandID] != nil,
            "A lost confirmation response was not represented as unknown"
        )

        feature.clearPrivateEvidence()
        try check(
            feature.commandResults.isEmpty && feature.commandPages.isEmpty
                && feature.corrections.isEmpty && feature.previews.isEmpty,
            "Lock retained private manual command or preview evidence"
        )
        let reopened = ManualReviewFeatureModel()
        reopened.authorizePrivateEvidence()
        await reopened.recoverCommands(
            sourceID: source.sourceID, accountIDs: ["archive", "paper"], using: client
        )
        try check(
            reopened.commandResults[command.commandID]?.status == "uncertain"
                && reopened.commandResults[command.commandID]?.command.request.accountID == "paper",
            "Reopened manual review did not recover the durable uncertain command by source/account"
        )
        let requests = try await transport.sentRequests().map {
            try JSONSerialization.jsonObject(with: $0) as? [String: Any] ?? [:]
        }
        let operations = requests.compactMap { $0["operation"] as? String }
        try check(
            operations.filter { $0 == "confirm_manual_orders" }.count == 1
                && operations.filter { $0 == "list_manual_commands" }.count == 2,
            "Reopening did not query account history without replaying confirmation: \(operations)"
        )
        let paperPageRequest = requests.first {
            $0["operation"] as? String == "list_manual_commands"
                && $0["account_id"] as? String == "paper"
        }
        let expected =
            try JSONSerialization.jsonObject(
                with: Data(contentsOf: contracts.appending(path: "manual-command-page-request.json"))
            ) as? [String: Any] ?? [:]
        var normalized = paperPageRequest ?? [:]
        normalized["request_id"] = expected["request_id"]
        try check(
            NSDictionary(dictionary: normalized).isEqual(to: expected),
            "Durable command page request differed from its typed source-scoped fixture"
        )
        print("CopyTradingContractTests: lost confirmation recovered after lock via source-scoped durable command page")
    }

    private static func waitForManualResponse(
        _ operation: String, from transport: ManualContractTransport
    ) async throws {
        for _ in 0..<1_000 {
            if await transport.isWaiting(for: operation) { return }
            await Task.yield()
        }
        throw ContractFailure("Manual IPC response did not suspend: \(operation)")
    }

    private static func waitForSuspension(
        _ operation: String, from actions: SuspendedAccountActions
    ) async throws {
        for _ in 0..<1_000 {
            if await actions.isSuspended(operation) { return }
            await Task.yield()
        }
        throw ContractFailure("Injected account operation did not suspend: \(operation)")
    }
}

@MainActor
private func checkLogSettingsPersistBeforeRuntime(_ stateRoot: URL) throws {
    let key = "COPYTRADING_STATE_ROOT"
    let previous = ProcessInfo.processInfo.environment[key]
    let setResult = stateRoot.path.withCString { Darwin.setenv(key, $0, 1) }
    guard setResult == 0 else { throw ContractFailure("Could not isolate log settings for the first-run test") }
    defer {
        if let previous {
            _ = previous.withCString { Darwin.setenv(key, $0, 1) }
        } else {
            _ = Darwin.unsetenv(key)
        }
    }

    let model = AppModel()
    try check(model.diagnosticsSettings == DiagnosticsSettings(), "a first run must start from the default log settings")
    model.saveDiagnosticsSettings(ageDays: 30, storageLimitBytes: 512 * 1_024 * 1_024)
    let saved = try DiagnosticsSettingsStore(url: stateRoot.appending(path: "logs/settings.json")).load()
    try check(
        saved?.ageDays == 30 && saved?.storageLimitBytes == 512 * 1_024 * 1_024,
        "first-run log settings were not saved before the engine started")

    let reopeningModel = AppModel()
    try check(reopeningModel.diagnosticsSettings == saved, "a reopened app did not load the saved log settings")
    reopeningModel.saveDiagnosticsSettings(ageDays: 0, storageLimitBytes: 1)
    try check(reopeningModel.diagnosticsSettingsWarning != nil, "an unsupported log setting must be refused with a warning")
    let afterRefusal = try DiagnosticsSettingsStore(url: stateRoot.appending(path: "logs/settings.json")).load()
    try check(afterRefusal == saved, "a refused log setting changed the saved file")
}

private actor RecordingAccountActions: AccountOperations {
    private var commands: [AccountControlCommand] = []
    private var resolutions: [OwnershipResolutionRequest] = []
    private(set) var deletedRecords: [String] = []
    private var recordRefusal: String?

    func recordedResolutions() -> [OwnershipResolutionRequest] { resolutions }

    func refuseRecordDeletion(_ reason: String?) { recordRefusal = reason }

    func deleteAccountRecord(_ accountID: String) throws {
        deletedRecords.append(accountID)
        if let refusal = recordRefusal {
            throw EngineContractError.remote(code: .invalidRequest, message: nil, reason: refusal)
        }
    }

    func resolveOwnership(accountID: String, resolution: OwnershipResolutionRequest) throws -> OwnershipResolution {
        resolutions.append(resolution)
        let request = try JSONEncoder().encode(resolution)
        let json =
            #"{"request":\#(String(decoding: request, as: UTF8.self)),"checked_at":"2026-10-08T06:00:00Z","lot_reductions":{},"allocation_revision":1}"#
        return try JSONDecoder().decode(OwnershipResolution.self, from: Data(json.utf8))
    }
    private var permission = "disabled"
    private var windows: [EquityHistoryWindow] = []
    private var firstFailure: CheckedContinuation<Void, Never>?

    func recordedCommands() -> [AccountControlCommand] { commands }
    func recordedWindows() -> [EquityHistoryWindow] { windows }

    func firstIsWaiting() -> Bool { firstFailure != nil }

    func releaseFirstFailure() {
        firstFailure?.resume()
        firstFailure = nil
    }

    func accounts(beforeAccountID: String?, limit: Int) throws -> AccountOverviewPage {
        if beforeAccountID != nil {
            return try pageFixture("account-overviews-next-page-response.json")
        }
        let data = try fixture("account-overviews-response.json")
        let source = String(decoding: data, as: UTF8.self)
        let updated = source.replacingOccurrences(
            of: "\"entry_permission\":\"paused\"",
            with: "\"entry_permission\":\"\(permission)\""
        )
        let response = try JSONDecoder().decode(EngineResponse.self, from: Data(updated.utf8))
        guard case .accounts(let value) = try response.successValue() else {
            throw ContractFailure("Account overview fixture type changed")
        }
        return value
    }

    func sourceActivity(beforeSeq: Int?, limit: Int) throws -> SourceActivityPage {
        let response = try JSONDecoder().decode(
            EngineResponse.self, from: fixture("source-activity-response.json")
        )
        guard case .sourceActivity(let value) = try response.successValue() else {
            throw ContractFailure("Source activity fixture type changed")
        }
        return value
    }

    func guruActivity(guruID: String, beforeSeq: Int?, limit: Int) throws -> SourceActivityPage {
        try sourceActivity(beforeSeq: beforeSeq, limit: limit)
    }

    func guruDayStats(dayStart: Date, dayEnd: Date) throws -> GuruDayStatsPage {
        let response = try JSONDecoder().decode(EngineResponse.self, from: fixture("guru-day-stats-response.json"))
        guard case .guruDayStats(let value) = try response.successValue() else {
            throw ContractFailure("Guru day fixture type changed")
        }
        return value
    }

    func accountFeed(accountID: String, beforeSeq: Int?, limit: Int) throws -> AccountFeedPage {
        let response = try JSONDecoder().decode(
            EngineResponse.self, from: fixture("account-feed-response.json")
        )
        guard case .accountFeed(let value) = try response.successValue() else {
            throw ContractFailure("Account feed fixture type changed")
        }
        return value
    }

    func controlAccount(_ command: AccountControlCommand) async throws -> AccountControlResult {
        commands.append(command)
        if commands.count == 1 {
            await withCheckedContinuation { firstFailure = $0 }
            throw ContractFailure("Simulated account command failure")
        }
        permission = command.action == .pause ? "paused" : "enabled"
        let result: [String: Any] = [
            "command": try JSONSerialization.jsonObject(with: JSONEncoder().encode(command)),
            "applied_at": "2026-09-26T15:00:00Z",
            "entry_permission": permission,
            "recovery_preference": "manual",
        ]
        return try JSONDecoder().decode(
            AccountControlResult.self, from: JSONSerialization.data(withJSONObject: result)
        )
    }

    func equityHistory(accountID: String, window: EquityHistoryWindow) throws -> EquityHistory? {
        windows.append(window)
        let response = try JSONDecoder().decode(
            EngineResponse.self, from: fixture("equity-history-response.json")
        )
        guard case .equityHistory(_, let value) = try response.successValue() else {
            throw ContractFailure("Equity history fixture type changed")
        }
        return value
    }

    private func fixture(_ name: String) throws -> Data {
        let contracts = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "Resources/Contracts")
        return try Data(contentsOf: contracts.appending(path: name))
    }

    private func pageFixture(_ name: String) throws -> AccountOverviewPage {
        let response = try JSONDecoder().decode(EngineResponse.self, from: fixture(name))
        guard case .accounts(let page) = try response.successValue() else {
            throw ContractFailure("Account overview page fixture type changed")
        }
        return page
    }
}

private actor SuspendedAccountActions: AccountOperations {
    private var suspendedOperation: String?
    private var activeOperation: String?
    private var continuation: CheckedContinuation<Void, Never>?

    init(suspendedOperation: String) {
        self.suspendedOperation = suspendedOperation
    }

    func isSuspended(_ operation: String) -> Bool { activeOperation == operation }

    func resolveOwnership(accountID: String, resolution: OwnershipResolutionRequest) throws -> OwnershipResolution {
        throw ContractFailure("Ownership resolution is not part of the suspension checks")
    }

    func deleteAccountRecord(_ accountID: String) throws {
        throw ContractFailure("Deleting a record is not part of the suspension checks")
    }

    func suspendNext(_ operation: String) {
        suspendedOperation = operation
    }

    func releaseSuspendedOperation() {
        continuation?.resume()
        continuation = nil
        activeOperation = nil
    }

    func accounts(beforeAccountID: String?, limit: Int) async throws -> AccountOverviewPage {
        try await suspendIfRequested("accounts")
        if beforeAccountID != nil {
            return try decoded("account-overviews-next-page-response.json", as: AccountOverviewPage.self) {
                guard case .accounts(let value) = try $0.successValue() else {
                    throw ContractFailure("Account page fixture type changed")
                }
                return value
            }
        }
        return try overviewFixture()
    }

    func sourceActivity(beforeSeq: Int?, limit: Int) async throws -> SourceActivityPage {
        try await suspendIfRequested("sourceActivity")
        return try decoded("source-activity-response.json", as: SourceActivityPage.self) {
            guard case .sourceActivity(let value) = try $0.successValue() else {
                throw ContractFailure("Activity fixture type changed")
            }
            return value
        }
    }

    func guruActivity(guruID: String, beforeSeq: Int?, limit: Int) async throws -> SourceActivityPage {
        try await sourceActivity(beforeSeq: beforeSeq, limit: limit)
    }

    func guruDayStats(dayStart: Date, dayEnd: Date) async throws -> GuruDayStatsPage {
        try await suspendIfRequested("guruDays")
        return try decoded("guru-day-stats-response.json", as: GuruDayStatsPage.self) {
            guard case .guruDayStats(let value) = try $0.successValue() else {
                throw ContractFailure("Guru day fixture type changed")
            }
            return value
        }
    }

    func accountFeed(accountID: String, beforeSeq: Int?, limit: Int) async throws -> AccountFeedPage {
        try await suspendIfRequested("feed")
        return try decoded("account-feed-response.json", as: AccountFeedPage.self) {
            guard case .accountFeed(let value) = try $0.successValue() else {
                throw ContractFailure("Feed fixture type changed")
            }
            return value
        }
    }

    func controlAccount(_ command: AccountControlCommand) async throws -> AccountControlResult {
        try await suspendIfRequested("control")
        return try decoded("account-control-response.json", as: AccountControlResult.self) {
            guard case .accountControl(let value) = try $0.successValue() else {
                throw ContractFailure("Control fixture type changed")
            }
            return value
        }
    }

    func equityHistory(accountID: String, window: EquityHistoryWindow) async throws -> EquityHistory? {
        try await suspendIfRequested("history")
        return nil
    }

    private func suspendIfRequested(_ operation: String) async throws {
        guard suspendedOperation == operation else { return }
        suspendedOperation = nil
        await withCheckedContinuation {
            continuation = $0
            activeOperation = operation
        }
    }

    private func overviewFixture() throws -> AccountOverviewPage {
        try decoded("account-overviews-response.json", as: AccountOverviewPage.self) {
            guard case .accounts(let values) = try $0.successValue() else {
                throw ContractFailure("Account fixture type changed")
            }
            return values
        }
    }

    private func decoded<Value>(
        _ name: String, as _: Value.Type, transform: (EngineResponse) throws -> Value
    ) throws -> Value {
        let contracts = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "Resources/Contracts")
        let response = try JSONDecoder().decode(
            EngineResponse.self, from: Data(contentsOf: contracts.appending(path: name))
        )
        return try transform(response)
    }
}

private actor AccountPageTransport: EngineTransport {
    private let responseFixture: Data
    private var continuation: AsyncThrowingStream<Data, any Error>.Continuation?
    private var responseWaitingForReader: Data?
    private var requestLine: Data?

    init(responseFixture: Data) {
        self.responseFixture = responseFixture
    }

    func send(_ line: Data) throws {
        requestLine = line
        guard
            var response = try JSONSerialization.jsonObject(with: responseFixture) as? [String: Any],
            let request = try JSONSerialization.jsonObject(with: line) as? [String: Any],
            let requestID = request["request_id"] as? String
        else { throw ContractFailure("Account page transport received malformed JSON") }
        response["request_id"] = requestID
        let encoded = try JSONSerialization.data(withJSONObject: response)
        if let continuation {
            continuation.yield(encoded)
            continuation.finish()
        } else {
            responseWaitingForReader = encoded
        }
    }

    func responseLines() -> AsyncThrowingStream<Data, any Error> {
        AsyncThrowingStream { continuation in
            Task { self.install(continuation) }
        }
    }

    func sentRequest() -> Data? { requestLine }

    private func install(_ continuation: AsyncThrowingStream<Data, any Error>.Continuation) {
        self.continuation = continuation
        if let response = responseWaitingForReader {
            continuation.yield(response)
            continuation.finish()
            responseWaitingForReader = nil
        }
    }
}

private actor ManualContractTransport: EngineTransport {
    private let contracts: URL
    private var continuation: AsyncThrowingStream<Data, any Error>.Continuation?
    private var responsesWaitingForReader: [Data] = []
    private var requests: [Data] = []
    private var operationToSuspend: String?
    private var suspendedOperation: String?
    private var suspendedResponse: Data?
    private var partialCorrectionResponses = 0
    private var operationToDrop: String?
    private var refusals: [String: String] = [:]

    init(contracts: URL) {
        self.contracts = contracts
    }

    func send(_ line: Data) throws {
        let request = try JSONSerialization.jsonObject(with: line) as? [String: Any] ?? [:]
        guard let operation = request["operation"] as? String,
            let requestID = request["request_id"] as? String
        else {
            throw EngineTransportError.malformedResponse
        }
        requests.append(line)
        if let reason = refusals.removeValue(forKey: operation) {
            let refused: [String: Any] = [
                "version": 1, "request_id": requestID,
                "error": ["code": "unavailable", "reason": reason],
            ]
            let encoded = try JSONSerialization.data(withJSONObject: refused)
            if let continuation {
                continuation.yield(encoded)
            } else {
                responsesWaitingForReader.append(encoded)
            }
            return
        }
        let fixtureName: String
        switch operation {
        case "save_manual_correction": fixtureName = "manual-correction-response.json"
        case "preview_manual_order":
            let preview = request["preview"] as? [String: Any] ?? [:]
            fixtureName =
                preview["account_id"] as? String == "archive"
                ? "manual-preview-archive-response.json" : "manual-preview-response.json"
        case "confirm_manual_orders": fixtureName = "manual-confirmation-response.json"
        case "get_manual_command": fixtureName = "manual-command-response.json"
        case "list_manual_commands": fixtureName = "manual-command-page-response.json"
        default: throw EngineTransportError.malformedResponse
        }
        guard
            var response = try JSONSerialization.jsonObject(
                with: Data(contentsOf: contracts.appending(path: fixtureName))
            ) as? [String: Any]
        else { throw EngineTransportError.malformedResponse }
        if operation == "save_manual_correction", partialCorrectionResponses > 0 {
            partialCorrectionResponses -= 1
            guard var success = response["ok"] as? [String: Any],
                var outcome = success["correction"] as? [String: Any],
                var accounts = outcome["accounts"] as? [[String: Any]]
            else {
                throw EngineTransportError.malformedResponse
            }
            for index in accounts.indices where accounts[index]["account_id"] as? String == "archive" {
                accounts[index]["status"] = "failed"
                accounts[index]["reason"] = "record_failed"
            }
            outcome["accounts"] = accounts
            success["correction"] = outcome
            response["ok"] = success
        }
        if operation == "preview_manual_order" {
            guard var success = response["ok"] as? [String: Any],
                var preview = success["preview"] as? [String: Any],
                let previewRequest = request["preview"] as? [String: Any]
            else {
                throw EngineTransportError.malformedResponse
            }
            preview["request"] = previewRequest
            success["preview"] = preview
            response["ok"] = success
        }
        if operation == "confirm_manual_orders" {
            let commandIDs = Set(
                (request["commands"] as? [[String: Any]] ?? [])
                    .compactMap { $0["command_id"] as? String }
            )
            guard var success = response["ok"] as? [String: Any],
                var commands = success["commands"] as? [String: Any],
                let outcomes = commands["outcomes"] as? [[String: Any]]
            else {
                throw EngineTransportError.malformedResponse
            }
            commands["outcomes"] = outcomes.filter {
                guard let commandID = $0["command_id"] as? String else { return false }
                return commandIDs.contains(commandID)
            }
            success["commands"] = commands
            response["ok"] = success
        }
        if operation == "list_manual_commands" {
            guard var success = response["ok"] as? [String: Any],
                var page = success["commands"] as? [String: Any],
                let accountID = request["account_id"] as? String,
                let sourceID = request["source_id"] as? String
            else {
                throw EngineTransportError.malformedResponse
            }
            page["account_id"] = accountID
            page["source_id"] = sourceID
            if accountID == "archive" { page["items"] = [] }
            success["commands"] = page
            response["ok"] = success
        }
        response["request_id"] = requestID
        let encoded = try JSONSerialization.data(withJSONObject: response)
        if operationToDrop == operation {
            operationToDrop = nil
            return
        }
        if operationToSuspend == operation {
            operationToSuspend = nil
            suspendedOperation = operation
            suspendedResponse = encoded
            return
        }
        if let continuation {
            continuation.yield(encoded)
        } else {
            responsesWaitingForReader.append(encoded)
        }
    }

    func responseLines() -> AsyncThrowingStream<Data, any Error> {
        AsyncThrowingStream { continuation in
            Task { self.install(continuation) }
        }
    }

    func sentRequests() -> [Data] { requests }

    func returnPartialCorrectionResponseOnce() { partialCorrectionResponses = 1 }

    func dropNextResponse(for operation: String) { operationToDrop = operation }

    /// Answers the next `operation` with a refusal that names `reason`, as the engine does.
    func refuseNext(operation: String, reason: String) { refusals[operation] = reason }

    func suspendNextResponse(for operation: String) {
        operationToSuspend = operation
    }

    func isWaiting(for operation: String) -> Bool { suspendedOperation == operation }

    func releaseSuspendedResponse() {
        guard let response = suspendedResponse else { return }
        suspendedResponse = nil
        suspendedOperation = nil
        if let continuation {
            continuation.yield(response)
        } else {
            responsesWaitingForReader.append(response)
        }
    }

    private func install(_ continuation: AsyncThrowingStream<Data, any Error>.Continuation) {
        self.continuation = continuation
        for response in responsesWaitingForReader { continuation.yield(response) }
        responsesWaitingForReader.removeAll()
    }
}

private struct ContractFailure: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

private func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw ContractFailure(message) }
}

@MainActor
private func checkActivityScreenStateAndStatusPolicy() throws {
    let state = ActivityScreenState()
    state.selectedActivityID = 42
    state.applyFilter(.waiting, visibleIDs: [7, 9])
    let reviewFilter = state.filter
    let firstVisibleID = state.selectedActivityID
    try check(
        reviewFilter == .waiting && firstVisibleID == 7,
        "Filtering Activity did not move the detail to the first visible post"
    )

    state.applyFilter(.trades, visibleIDs: [])
    let emptyFilterSelection = state.selectedActivityID
    try check(emptyFilterSelection == nil, "An empty Activity filter left a stale detail selected")

    state.focusActivity(101)
    let focusedFilter = state.filter
    let focusedActivityID = state.selectedActivityID
    try check(
        focusedFilter == .all && focusedActivityID == 101,
        "A focused Activity deep link did not override the saved filter"
    )

}

private func secretRevision(in data: Data) throws -> UUID {
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
        let raw = json["secretRevision"] as? String,
        let revision = UUID(uuidString: raw)
    else {
        throw ContractFailure("Saved configuration is missing its credential revision")
    }
    return revision
}

actor RecordingTradingStarter: TradingStarting {
    private var configuration: TradingConfiguration?
    private var lastEvaluationRequest: HistoricalProfileEvaluationRequest?
    private var lastLearningRequest: GuruPlaybookLearningRequest?
    private var learningFailure: String?
    private var operationEvents: [String] = []
    private var failStart = false
    private var acceptStartAndLoseResponse = false
    private var commitStartLater = false
    private var validationActivatable = true
    private var validationSuspended = false
    private var validationTimeouts = 0
    private var validations = 0
    /// The last check's grant ran out, as the engine's does two minutes after a check.
    private var grantExpired = false
    private var connectionChecks: [TradingConnectionCheck] = []
    private var connectionCheckFails = false
    private var activation: TradingActivationStatus?
    private var latestTradingStatus: TradingStatus?
    private var validated: TradingConfiguration?
    /// A setup whose check fails while every other one passes, like a mistyped limit or key.
    private var failingConfiguration: TradingConfiguration?

    func tradingStatus() async throws -> TradingStatus {
        if let latestTradingStatus { return latestTradingStatus }
        let json = """
            {"state":"paused","configured_accounts":0,"active_accounts":0,
             "source_connected":false,"model_ready":false,"pending_source":0,
             "pending_signals":0,"processed_signals":0,"error_code":null,"accounts":[]}
            """
        return try JSONDecoder().decode(TradingStatus.self, from: Data(json.utf8))
    }

    func validateTrading(
        configuration: TradingConfiguration, secrets: TradingSecrets
    ) async throws -> TradingValidation {
        _ = secrets
        operationEvents.append("validate")
        validated = configuration
        validations += 1
        grantExpired = false
        if validationTimeouts > 0 {
            validationTimeouts -= 1
            throw EngineTransportError.requestTimedOut
        }
        if validationSuspended { try await Task.sleep(for: .seconds(30)) }
        let validationActivatable = validationActivatable && configuration != failingConfiguration
        return TradingValidation(
            report: TradingCapabilityReport(
                configurationRevision: fakeEngineRevision(configuration),
                activatable: validationActivatable,
                checks: [
                    TradingCapabilityCheck(
                        name: .source, state: .ready, subject: nil, environment: nil,
                        identity: "discord_user:123", adapter: "fake", reasonCode: nil
                    )
                ]
                    + (validationActivatable
                        ? []
                        : [
                            TradingCapabilityCheck(
                                name: .model, state: .failed, subject: nil, environment: nil,
                                identity: nil, adapter: "fake", reasonCode: "provider_unreachable"
                            )
                        ]),
                costNotice: "Test model validation cost notice"
            ),
            activationToken: validationActivatable ? "validation-grant" : nil
        )
    }

    func expireGrant() { grantExpired = true }

    func checkConnection(_ connection: TradingConnectionCheck) async throws -> TradingCapabilityCheck {
        connectionChecks.append(connection)
        let name: TradingCapabilityName =
            switch connection {
            case .source: .source
            case .model: .model
            case .broker: .broker
            case .notification: .notification
            }
        return TradingCapabilityCheck(
            name: name, state: connectionCheckFails ? .failed : .ready, subject: nil, environment: nil,
            identity: nil, adapter: "fake", reasonCode: connectionCheckFails ? "\(name.rawValue)_capability_unavailable" : nil
        )
    }

    func startTrading(
        configuration: TradingConfiguration,
        secrets: TradingSecrets,
        validationToken: String,
        activationID: String
    ) async throws -> TradingStatus {
        guard validationToken == "validation-grant", !grantExpired else {
            throw ContractFailure("Start omitted the fresh validation grant")
        }
        guard !failStart else { throw ContractFailure("Simulated process failure before Start acknowledgement") }
        operationEvents.append("start")
        _ = secrets
        self.configuration = configuration
        let revision = fakeEngineRevision(configuration)
        if acceptStartAndLoseResponse {
            let startingJSON = """
                {"state":"starting","configured_accounts":1,"active_accounts":0,
                 "source_connected":false,"model_ready":false,"pending_source":0,
                 "pending_signals":0,"processed_signals":0,"error_code":null,"accounts":[]}
                """
            latestTradingStatus = try JSONDecoder().decode(TradingStatus.self, from: Data(startingJSON.utf8))
            activation = TradingActivationStatus(
                requestedActivationID: activationID,
                activationID: activationID,
                candidateRevision: revision,
                committedRevision: nil,
                phase: .starting,
                runtimeState: .starting,
                errorCode: nil
            )
            throw ContractFailure("Start was accepted but its response was lost")
        }
        if commitStartLater {
            activation = TradingActivationStatus(
                requestedActivationID: activationID,
                activationID: activationID,
                candidateRevision: revision,
                committedRevision: nil,
                phase: .starting,
                runtimeState: .starting,
                errorCode: nil
            )
            latestTradingStatus = try TradingStatusBuilder(.starting).build()
            return try TradingStatusBuilder(.starting).build()
        }
        activation = TradingActivationStatus(
            requestedActivationID: activationID,
            activationID: activationID,
            candidateRevision: revision,
            committedRevision: revision,
            phase: .ready,
            runtimeState: .running,
            errorCode: nil,
            committedActivationID: activationID
        )
        let json = """
            {"state":"running","configured_accounts":1,"active_accounts":1,
             "source_connected":true,"model_ready":true,"pending_source":0,
             "pending_signals":0,"processed_signals":0,"error_code":null,"accounts":[]}
            """
        let status = try JSONDecoder().decode(TradingStatus.self, from: Data(json.utf8))
        latestTradingStatus = status
        return status
    }

    func updateAccountLimits(configuration: TradingConfiguration) async throws -> String {
        operationEvents.append("update_limits")
        self.configuration = configuration
        return fakeEngineRevision(configuration)
    }

    /// Like the engine: the answer says pausing, and the next status read says paused.
    func pauseTrading() async throws -> TradingStatus {
        operationEvents.append("pause")
        latestTradingStatus = try TradingStatusBuilder(.paused).build()
        return try TradingStatusBuilder(.pausing).build()
    }

    func tradingActivation(activationID: String) async throws -> TradingActivationStatus {
        if let activation, activation.requestedActivationID == activationID { return activation }
        return TradingActivationStatus(
            requestedActivationID: activationID,
            activationID: nil,
            candidateRevision: nil,
            committedRevision: nil,
            phase: .notFound,
            runtimeState: .paused,
            errorCode: nil
        )
    }

    func setTradingStatus(_ status: TradingStatus) {
        latestTradingStatus = status
    }

    func setActivationStatus(
        _ status: TradingActivationStatus, state: TradingRunState, activeAccounts: Int
    ) throws {
        activation = status
        let accounts =
            activeAccounts > 0
            ? #"[{"id":"paper","state":"running","error_code":null}]"# : "[]"
        let json = """
            {"state":"\(state.rawValue)","configured_accounts":1,"active_accounts":\(activeAccounts),
             "source_connected":false,"model_ready":false,"pending_source":0,
             "pending_signals":0,"processed_signals":0,"error_code":null,"accounts":\(accounts)}
            """
        latestTradingStatus = try JSONDecoder().decode(TradingStatus.self, from: Data(json.utf8))
    }

    func evaluateHistoricalProfile(
        _ evaluation: HistoricalProfileEvaluationRequest
    ) async throws -> ProfileEvaluation {
        lastEvaluationRequest = evaluation
        return ProfileEvaluation(
            messageIdentity: evaluation.sourceID,
            guruID: evaluation.profile.guruID,
            profileRevision: evaluation.profile.profileRevision,
            provider: evaluation.provider.name.rawValue,
            model: evaluation.provider.model,
            decision: "trade",
            reason: "explicit_entry",
            simulated: true,
            noOrder: true,
            costNotice: "Test evaluation cost notice.",
            instructions: [],
            destinations: [],
            reviewReasons: []
        )
    }

    func learnGuruPlaybook(_ learning: GuruPlaybookLearningRequest) async throws -> LearnedGuruPlaybook {
        lastLearningRequest = learning
        operationEvents.append("learn")
        if let learningFailure {
            throw EngineContractError.remote(code: .invalidRequest, message: learningFailure, reason: nil)
        }
        return LearnedGuruPlaybook(
            postsRead: 3,
            playbook: "加了 means buy", summary: "Buys lead with the price.",
            provider: learning.provider.name.rawValue, model: learning.provider.model,
            costNotice: "Provider charges may apply."
        )
    }

    func learningRequest() -> GuruPlaybookLearningRequest? { lastLearningRequest }
    func setLearningFailure(_ message: String?) { learningFailure = message }

    func startedConfiguration() -> TradingConfiguration? { configuration }
    func validatedConfiguration() -> TradingConfiguration? { validated }
    func evaluationRequest() -> HistoricalProfileEvaluationRequest? { lastEvaluationRequest }
    func events() -> [String] { operationEvents }

    func setStartFailure(_ value: Bool) { failStart = value }
    func setAcceptStartAndLoseResponse(_ value: Bool) { acceptStartAndLoseResponse = value }
    /// Like a real engine seconds into a start: it answers "starting", and commits only when the
    /// test says so through `setActivationStatus`.
    func setCommitStartLater(_ value: Bool) { commitStartLater = value }
    func setValidationActivatable(_ value: Bool) { validationActivatable = value }
    /// The next `count` checks throw as an engine that does not answer in time.
    func setValidationTimesOut(_ count: Int) { validationTimeouts = count }
    func setFailingConfiguration(_ value: TradingConfiguration?) { failingConfiguration = value }
    func setConnectionCheckFails(_ value: Bool) { connectionCheckFails = value }
    func checkedConnections() -> [TradingConnectionCheck] { connectionChecks }
    func setValidationSuspended(_ value: Bool) { validationSuspended = value }
    func validationCallCount() -> Int { validations }
}

final class TestSecretRevisions: TradingSecretRevisionStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [UUID: TradingSecrets] = [:]

    var storedCount: Int { lock.withLock { values.count } }

    func load(revision: UUID) throws -> TradingSecrets? {
        lock.withLock { values[revision] }
    }

    func save(_ secrets: TradingSecrets, for revision: UUID) throws {
        lock.withLock { values[revision] = secrets }
    }

    func delete(revision: UUID) throws {
        _ = lock.withLock { values.removeValue(forKey: revision) }
    }
}

private final class ToggleConfigurationWriter: TradingConfigurationWriter, @unchecked Sendable {
    private let lock = NSLock()
    private var failWrite = false

    func failNextWrite() { lock.withLock { failWrite = true } }

    func write(_ data: Data, to url: URL) throws {
        let shouldFail = lock.withLock {
            defer { failWrite = false }
            return failWrite
        }
        if shouldFail { throw TradingConfigurationStoreError.unavailable }
        try AtomicTradingConfigurationWriter().write(data, to: url)
    }
}

/// Unlocks the window like the owner did at launch, then answers each later confirmation.
actor OwnerAnswers: AppOwnerAuthenticator {
    private let confirms: Bool
    private var calls = 0
    init(confirms: Bool) { self.confirms = confirms }

    /// Confirmations asked for after the window was unlocked.
    var confirmations: Int { max(calls - 1, 0) }

    func authenticate(localizedReason: String) async throws {
        calls += 1
        if calls > 1 && !confirms { throw AppUnlockError.authenticationCancelled }
    }

    func invalidate() async {}
}

@MainActor
func unlocked(by owner: OwnerAnswers) async throws -> AppUnlock {
    let unlock = AppUnlock(authenticator: owner)
    try await unlock.openWindow(UUID())
    return unlock
}
