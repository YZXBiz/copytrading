import AppKit
import DesktopCore
import Foundation
import Observation

protocol TradingStarting: Sendable {
    func tradingStatus() async throws -> TradingStatus

    func validateTrading(
        configuration: TradingConfiguration, secrets: TradingSecrets
    ) async throws -> TradingValidation

    func checkConnection(_ connection: TradingConnectionCheck) async throws -> TradingCapabilityCheck

    func startTrading(
        configuration: TradingConfiguration,
        secrets: TradingSecrets,
        validationToken: String,
        activationID: String
    ) async throws -> TradingStatus

    func tradingActivation(activationID: String) async throws -> TradingActivationStatus

    func pauseTrading() async throws -> TradingStatus

    func updateAccountLimits(configuration: TradingConfiguration) async throws -> String

    func evaluateHistoricalProfile(
        _ evaluation: HistoricalProfileEvaluationRequest
    ) async throws -> ProfileEvaluation

    func learnGuruPlaybook(
        _ learning: GuruPlaybookLearningRequest
    ) async throws -> LearnedGuruPlaybook
}

extension EngineActions: TradingStarting {}

@MainActor
@Observable
final class AppModel {
    enum RuntimeState: String, Sendable {
        case stopped
        case starting
        case ready
        case degraded
        case failed
    }

    /// ⌘K's palette over the window.
    var isShowingPalette = false
    var selectedScreen: Screen = .gettingStarted {
        didSet {
            if selectedScreen != .settings {
                UserDefaults.standard.set(selectedScreen.identifier, forKey: Self.lastScreenKey)
            }
            if selectedScreen != oldValue, !isRetracingScreens {
                screenHistory.leave(oldValue)
            }
        }
    }
    /// What Back and Forward step through.
    var screenHistory = ScreenHistory()
    /// Set while Back or Forward moves, so the move isn't recorded as a new visit.
    @ObservationIgnored var isRetracingScreens = false
    /// The Settings page on show and the pages visited before it, newest last.
    var settingsPage: SettingsPage = .general
    var settingsTrail: [SettingsPage] = []
    /// Where closing Settings returns to.
    var screenBeforeSettings: Screen = .gettingStarted
    var runtimeState: RuntimeState = .stopped {
        didSet {
            holdMacAwakeWhileCopying()
            if oldValue != runtimeState, runtimeState == .ready { shareAccountReadKeys() }
        }
    }
    var engineStatus: EngineStatus?
    var tradingStatus: TradingStatus? {
        didSet {
            holdMacAwakeWhileCopying()
            trackCopyingAcrossLaunches()
            if wantsLaunchStart { Task { await startCopyingOnLaunchIfWanted() } }
            let stopped = stoppedWatch.stopped(in: tradingStatus)
            if !stopped.isEmpty { announceAccountStopped(stopped) }
        }
    }
    /// Accounts the engine stopped on its own, said once each. The real app sets
    /// `announceAccountStopped`.
    @ObservationIgnored private var stoppedWatch = StoppedWatch()
    @ObservationIgnored var announceAccountStopped: ([String]) -> Void = { _ in }
    var savedTradingConfiguration: TradingConfiguration?
    var hasTradingSecrets = false
    var tradingValidation: TradingValidation?
    var isValidatingTrading = false
    var isActivatingTrading = false
    /// A start was sent and the engine has not yet confirmed or rolled back the new setup.
    var isConfirmingActivation = false
    /// Copying was paused only to apply setup changes; anything short of starting the new setup
    /// resumes the saved one, so copying never stays paused by surprise.
    var isPausedToApplyChanges = false
    /// The accounts that were copying when Apply Changes paused; they copy again afterwards,
    /// whether the new setup started or the saved one came back.
    var accountsCopyingBeforeApply: Set<String> = []
    /// An apply is under way, from checking the draft to copying again. Start Copying waits for
    /// it: a second press would cancel it halfway and leave copying paused.
    var isApplyingChanges = false
    var isTradingCommandPending = false
    /// The last import's summary, until the owner keeps or trashes the file.
    var setupImportResult: SetupImportResult?
    /// The open panel for Import Setup…, from Connections or File; the only way a setup file
    /// reaches the app.
    var isShowingSetupImporter = false
    var isTradingUnlocked = false {
        didSet { if oldValue != isTradingUnlocked { shareAccountReadKeys() } }
    }
    var agentAccess: AgentAccessSetting = .off
    /// "Allow setup changes from the command line": off until the owner turns it on with Touch ID.
    var agentSetupChanges = false
    var isAgentRelayListening = false
    var isChangingAgentAccess = false
    var agentProposals: [AgentProposal] = []
    /// Requests already announced, so each one is said once. The real app sets `announceAgentRequest`.
    @ObservationIgnored var announcedProposalIDs: Set<String> = []
    @ObservationIgnored var announceAgentRequest: (AgentProposal) -> Void = { _ in }
    var agentAudit: [AgentAuditEntry] = []
    var agentAccessMessage: String?
    var isUnlockingTrading = false
    var latestSelfTest: WorkflowView?
    var selfTestEntries: [RecordedSelfTest] = []
    var pendingCommandID: String? { selfTestEntries.first(where: \.isPending)?.id }
    var isRunningSelfTest = false
    var selfTestText = "Bought AAPL 1/6 at 200"
    var message: String?
    var accessMessage: String?
    var runtimeStopMessage: String?
    var diagnosticsSettings = DiagnosticsSettings()
    var appliedDiagnosticsSettings: DiagnosticsSettings?
    var diagnosticsSettingsWarning: String?
    var diagnosticsEntries: [DiagnosticsJournalEntry] = []
    var diagnosticsJournalBytes: Int64 = 0
    /// The journal files as last read; a reload with the same fingerprint parses nothing.
    @ObservationIgnored private var diagnosticsFingerprint: [String]?
    var diagnosticsJournalMessage: String?
    var isLoadingDiagnostics = false
    var isRunningBackupRestore = false
    var backupRestoreNote: BackupRestoreNote?
    var backupManifest: BackupManifestView?
    var restorePreview: RestorePreviewView?
    var pendingRestoreCandidate: PendingRestoreCandidateView?
    var restorePreflightBlockers: [String] = []
    var restoreCredentialStatus: String?
    var restoreRecoveryMessage: String?

    @ObservationIgnored private var runtimePaths: RuntimePaths?
    /// Where the engine keeps the pictures it captured with posts; nil until its data folder opens.
    private(set) var sourcePicturesDirectory: URL?
    @ObservationIgnored private var supervisor: ProcessSupervisor?
    @ObservationIgnored private var startupOwnership: StartupOwnership?
    @ObservationIgnored private var commandJournal: CommandJournal?
    @ObservationIgnored private var engineActions: EngineActions?
    @ObservationIgnored private let proposalOperations: (any AgentProposalOperations)?
    @ObservationIgnored var agentRelay: AgentRelay?
    /// The conversation with the assistant; it is forgotten on lock, quit, and engine stop.
    let assistant = AssistantModel()
    /// The waiting calls the owner skipped, shared by every screen that lists posts.
    let skippedCalls = SkippedCalls()
    @ObservationIgnored var agentAccessStore: AgentAccessStore?
    @ObservationIgnored private var diagnosticsSettingsStore: DiagnosticsSettingsStore
    @ObservationIgnored private var diagnosticsJournal: DiagnosticsJournal

    var operationalStoragePath: String {
        runtimePaths?.applicationSupportDirectory.path ?? "App support is not open"
    }

    /// The running engine for agent approvals and the audit list; nil while no engine runs.
    func agentEngineActions() -> EngineActions? {
        engineActions
    }

    /// The engine's approval queue; a test hands in its own, otherwise the running engine's.
    func agentProposalOperations() -> (any AgentProposalOperations)? {
        proposalOperations ?? engineActions
    }

    /// Drops every proposal here and in the engine, whether or not agent access is on, because the
    /// assistant makes proposals too.
    func discardAgentProposals() async {
        agentProposals = []
        agentSetupProposals = [:]
        guard let operations = agentProposalOperations() else { return }
        _ = try? await operations.discardProposals()
    }

    /// The saved setup and its keys for one question to the assistant; nil when nothing is saved or the Keychain declines.
    func savedTradingSnapshot() -> (configuration: TradingConfiguration, secrets: TradingSecrets)? {
        (try? tradingConfigurationStore?.load()) ?? nil
    }

    /// A fresh owner authentication for one sensitive action inside an unlocked session.
    func confirmOwner(_ reason: String) async throws {
        try await appUnlock.confirm(localizedReason: reason)
    }

    func accountActions() -> EngineActions? {
        isTradingUnlocked && !isRunningBackupRestore && pendingRestoreCandidate == nil
            && restoreRecoveryMessage == nil ? engineActions : nil
    }

    var canActivateOperationalRestore: Bool {
        guard !isRunningBackupRestore,
            startupOwnership != nil,
            engineActions != nil,
            runtimePaths?.activeGenerationID != nil,
            runtimeState == .ready || runtimeState == .degraded,
            restoreRecoveryMessage == nil
        else { return false }
        if let pendingRestoreCandidate { return pendingRestoreCandidate.candidateValid }
        return restorePreview?.matchesInstallation == true
    }

    var canRollbackOperationalRestore: Bool {
        !isRunningBackupRestore
            && startupOwnership != nil
            && runtimePaths?.activeGenerationID != nil
            && (pendingRestoreCandidate != nil || restoreRecoveryMessage != nil)
            && (runtimeState == .ready || runtimeState == .degraded || runtimeState == .failed)
    }

    func createOperationalBackup(to destination: URL) async {
        guard !isRunningBackupRestore, let engineActions else {
            backupRestoreNote = .problem(
                L10n.string(
                    "The engine isn't running. Start it in Settings → Engine. If another CopyTrading is open, quit it first."))
            return
        }
        do {
            guard try tradingConfigurationStore?.pendingActivation() == nil else {
                backupRestoreNote = .problem(L10n.string("Finish starting or stopping copying, then back up."))
                return
            }
        } catch {
            backupRestoreNote = .problem(L10n.string("CopyTrading couldn't read your saved setup. Try again in a moment."))
            return
        }
        isRunningBackupRestore = true
        backupRestoreNote = .working(L10n.string("Pausing trading and checking the backup…"))
        defer { isRunningBackupRestore = false }
        do {
            backupManifest = try await engineActions.createBackup(destination: destination)
            tradingStatus = try? await engineActions.tradingStatus()
            backupRestoreNote = .done(
                L10n.string(
                    "Backup saved and checked: %@. Copying stopped while it ran; choose Start Copying to carry on.", destination.path))
        } catch is CancellationError {
            backupRestoreNote = .problem(L10n.string("The backup was cancelled. Nothing was left half-written."))
        } catch {
            backupRestoreNote = .problem(Self.userMessage(for: error))
        }
    }

    func previewOperationalRestore(from archive: URL) async {
        guard !isRunningBackupRestore,
            pendingRestoreCandidate == nil,
            restoreRecoveryMessage == nil,
            let engineActions
        else {
            backupRestoreNote = .problem(
                L10n.string(
                    "The engine isn't running. Start it in Settings → Engine. If another CopyTrading is open, quit it first."))
            return
        }
        isRunningBackupRestore = true
        backupRestoreNote = .working(L10n.string("Checking every file in the backup…"))
        defer { isRunningBackupRestore = false }
        do {
            let preview = try await engineActions.previewRestore(archive: archive)
            restorePreview = preview
            if preview.credentialReferences.isEmpty {
                restoreCredentialStatus = L10n.string("This backup doesn't need any saved keys.")
            } else if preview.matchesInstallation,
                let tradingConfigurationStore,
                try preview.credentialReferences.allSatisfy({
                    try tradingConfigurationStore.hasCredentialRevision($0)
                })
            {
                restoreCredentialStatus = L10n.string("The keys this backup needs are in this Mac's Keychain.")
            } else {
                restoreCredentialStatus = L10n.string(
                    "The keys this backup needs aren't on this Mac. Enter your account keys again before restoring.")
            }
            backupRestoreNote = .done(L10n.string("The backup checks out. Review it below before restoring."))
        } catch {
            restorePreview = nil
            restoreCredentialStatus = nil
            backupRestoreNote = .problem(Self.userMessage(for: error))
        }
    }

    func activateOperationalRestore() async {
        guard canActivateOperationalRestore,
            let owner = startupOwnership,
            let currentActions = engineActions,
            let currentPaths = runtimePaths
        else {
            backupRestoreNote = .problem(L10n.string("Start the engine and open a backup made on this Mac before restoring."))
            return
        }
        let preview = restorePreview
        if preview == nil && pendingRestoreCandidate == nil {
            backupRestoreNote = .problem(L10n.string("Open a backup to restore first."))
            return
        }
        do {
            guard try tradingConfigurationStore?.pendingActivation() == nil else {
                backupRestoreNote = .problem(L10n.string("Finish starting or stopping copying, then restore."))
                return
            }
        } catch {
            backupRestoreNote = .problem(L10n.string("CopyTrading couldn't read your saved setup. Try again in a moment."))
            return
        }
        guard preview == nil || currentPaths.activeGenerationID != nil else {
            backupRestoreNote = .problem(
                L10n.string("CopyTrading couldn't confirm which copy of your data is in use. Restart it and try again."))
            return
        }
        let stablePaths = RuntimePaths(
            applicationSupportDirectory: currentPaths.ownerSupportDirectory,
            runtimeRoot: currentPaths.runtimeRoot,
            engineSourceRoot: currentPaths.engineSourceRoot
        )
        let coordinator = RestoreActivationCoordinator(ownership: owner, stablePaths: stablePaths)
        let startRuntime: RestoreActivationCoordinator.RuntimeStarter = { [weak self] transition in
            guard let self else { throw CancellationError() }
            try await self.startRuntime(during: transition)
            guard let actions = self.engineActions else {
                throw RestoreActivationError.candidateStartFailed
            }
            return actions
        }
        let stopRuntime: RestoreActivationCoordinator.RuntimeStopper = { [weak self] transition in
            guard let self else { throw CancellationError() }
            try await self.stopRuntimeForMaintenance(during: transition)
        }
        isRunningBackupRestore = true
        restorePreflightBlockers = []
        restoreRecoveryMessage = nil
        backupRestoreNote = .working(L10n.string("Preparing the restore and checking it again…"))
        engineGeneration.advance()
        statusTask?.cancel()
        statusTask = nil
        eventTask?.cancel()
        eventTask = nil
        defer { isRunningBackupRestore = false }

        do {
            let result = try await coordinator.activate(
                preview: preview,
                knownPendingCandidateID: pendingRestoreCandidate?.candidateID,
                expectedPreviousGeneration: preview == nil || pendingRestoreCandidate != nil
                    ? nil
                    : currentPaths.activeGenerationID,
                engine: currentActions,
                credentialStore: tradingConfigurationStore,
                startRuntime: startRuntime,
                stopRuntime: stopRuntime
            )
            restorePreflightBlockers = result.blockers
            restorePreview = nil
            pendingRestoreCandidate = nil
            restoreCredentialStatus = nil
            backupRestoreNote = .done(
                L10n.string("Restored. Each account's buys stay off until you turn them back on."))
        } catch let error as RestoreActivationError {
            if case .preflightBlocked(let blockers) = error {
                restorePreflightBlockers = blockers
                backupRestoreNote = .problem(
                    L10n.string(
                        "This backup can't be restored yet: %@. Your data is as it was.",
                        Humanize.joined(blockers.map(RestoreBlocker.reason))))
            } else if case .rollbackIncomplete = error {
                restoreRecoveryMessage = Self.userMessage(for: error)
                backupRestoreNote = .problem(Self.userMessage(for: error))
                runtimeState = .failed
            } else {
                backupRestoreNote = .problem(Self.userMessage(for: error))
            }
        } catch {
            backupRestoreNote = .problem(restoreRecoveryMessage ?? Self.userMessage(for: error))
        }
    }

    func rollbackOperationalRestore() async {
        guard !isRunningBackupRestore,
            let owner = startupOwnership,
            let paths = runtimePaths
        else { return }
        isRunningBackupRestore = true
        backupRestoreNote = .working(L10n.string("Undoing the restore…"))
        engineGeneration.advance()
        statusTask?.cancel()
        statusTask = nil
        eventTask?.cancel()
        eventTask = nil
        defer { isRunningBackupRestore = false }
        let stablePaths = RuntimePaths(
            applicationSupportDirectory: paths.ownerSupportDirectory,
            runtimeRoot: paths.runtimeRoot,
            engineSourceRoot: paths.engineSourceRoot
        )
        let coordinator = RestoreActivationCoordinator(ownership: owner, stablePaths: stablePaths)
        let startRuntime: RestoreActivationCoordinator.RuntimeStarter = { [weak self] transition in
            guard let self else { throw CancellationError() }
            try await self.startRuntime(during: transition)
            guard let actions = self.engineActions else {
                throw RestoreActivationError.candidateStartFailed
            }
            return actions
        }
        let stopRuntime: RestoreActivationCoordinator.RuntimeStopper = { [weak self] transition in
            guard let self else { throw CancellationError() }
            try await self.stopRuntimeForMaintenance(during: transition)
        }
        do {
            try await coordinator.rollback(
                knownPendingCandidateID: pendingRestoreCandidate?.candidateID,
                engine: engineActions,
                startRuntime: startRuntime,
                stopRuntime: stopRuntime
            )
            restoreRecoveryMessage = nil
            pendingRestoreCandidate = nil
            backupRestoreNote = .done(L10n.string("Restore undone. CopyTrading is back on your data from before."))
        } catch {
            restoreRecoveryMessage =
                Self.userMessage(for: error is RestoreActivationError ? error : RestoreActivationError.rollbackIncomplete)
            backupRestoreNote = restoreRecoveryMessage.map(BackupRestoreNote.problem)
            runtimeState = .failed
        }
    }

    private func stopRuntimeForMaintenance(during transition: MaintenanceTransition) async throws {
        guard let owner = startupOwnership else { throw StartupOwnershipError.staleMaintenanceTransition }
        await assistant.reset()
        runtimeGeneration.advance()
        engineGeneration.advance()
        statusTask?.cancel()
        statusTask = nil
        eventTask?.cancel()
        eventTask = nil
        _ = try await owner.stopReplacementForMaintenance(during: transition)
        supervisor = nil
        stopAgentRelay()
        engineActions = nil
        engineStatus = nil
        tradingStatus = nil
        runtimeState = .starting
    }

    func evaluateHistoricalProfile(
        sourceID: String, routeID: String
    ) async throws -> ProfileEvaluation {
        guard isTradingUnlocked else { throw TradingSettingsError.privateAccessLocked }
        guard let tradingConfigurationStore,
            let evaluator: any TradingStarting = tradingStarter ?? engineActions
        else {
            throw TradingSettingsError.engineUnavailable
        }
        guard let saved = try tradingConfigurationStore.load(),
            let route = saved.configuration.routes.first(where: { $0.id == routeID }),
            let profile = saved.configuration.profiles.first(where: {
                $0.guruID == route.guruID && $0.profileRevision == route.profileRevision
            })
        else {
            throw TradingSettingsError.historicalEvaluationUnavailable
        }
        let request = HistoricalProfileEvaluationRequest(
            sourceID: sourceID,
            profile: profile,
            provider: saved.configuration.provider,
            providerAPIKey: saved.secrets.providerAPIKey,
            destinations: route.connections
        )
        let result = try await evaluator.evaluateHistoricalProfile(request)
        guard result.simulated, result.noOrder,
            result.messageIdentity == sourceID,
            result.guruID == profile.guruID,
            result.profileRevision == profile.profileRevision,
            result.provider == saved.configuration.provider.name.rawValue,
            result.model == saved.configuration.provider.model
        else {
            throw TradingSettingsError.invalidEvaluationResult
        }
        return result
    }
    @ObservationIgnored private var tradingStarter: (any TradingStarting)?
    /// How long an agent's apply waits for a start the engine has not confirmed yet.
    @ObservationIgnored var startSettleLimit: Duration = .seconds(30)
    @ObservationIgnored private(set) var tradingConfigurationStore: TradingConfigurationStore?
    /// The unsaved setup, edited from Connections, People, and Accounts. It lives here, not in a
    /// screen, so switching screens keeps what was typed; locking or closing the window drops it,
    /// secrets included.
    var setupDraft = ConnectionsDraft()
    /// The saved configuration `setupDraft` was last filled from, so refilling the draft never
    /// overwrites pending edits with the saved copy.
    var setupDraftSource: TradingConfiguration?
    /// The account or guru being edited, shown as one sheet over whichever screen asked for it.
    var setupEditor: ConnectionsEditingTarget?
    /// Where the account sheet opens: on its limits, or on the price tolerance Activity suggests.
    var accountEditorFocus: AccountEditorFocus?
    /// Accounts whose new limits were just saved without a check, each until the owner edits again.
    var limitsSavedAccountIDs: Set<String> = []
    /// The engine refused the draft's limits, so they wait for the full check like other changes.
    var limitsSaveRefused = false
    /// Limits edited while copying was starting; they save as soon as the start settles.
    var limitsAwaitingStart = false
    /// The accounts whose limits wait for that start; only theirs save when it settles.
    @ObservationIgnored var limitsAwaitingAccountIDs: Set<String> = []
    /// Accounts whose limits an agent changed in the unsaved setup. A live one's changes never save
    /// from its sheet: only an approved `setup apply`, or the owner's own Start Copying, saves them.
    @ObservationIgnored var agentLimitEdits: Set<String> = []
    /// Accounts and activity, shared with the window and the menu bar; an account's own Start
    /// Copying turns its buys on through it.
    var accountFeature: AccountFeatureModel?
    /// A connection the guide asked to open; Connections opens its panel and clears it.
    var requestedConnection: ConnectionKind?
    /// The draft as it stood when the current check began; Start Copying needs it unchanged.
    var checkedSetupSignature: SetupDraftSignature?
    /// Each connection's latest check, kept only while what it checked stays as typed.
    var connectionChecks: [ConnectionCheckSubject: ConnectionCheckResult] = [:]
    /// Every check the latest full check of the setup ran, for an agent's `setup apply`.
    @ObservationIgnored var latestSetupChecks: [TradingCapabilityCheck] = []
    /// Setups an agent asked to apply that touch a live account, by proposal: the draft as the
    /// owner was asked to approve it, so approving never applies a setup edited since.
    /// `start` is whether the agent asked to start copying with it.
    @ObservationIgnored var agentSetupProposals: [String: (signature: SetupDraftSignature, start: Bool)] = [:]
    var isShowingSetupCheck = false
    /// A Getting Started section asked for from the Help menu; the guide clears it.
    var guideAnchor: GuideAnchor?
    /// The setup tour is walking the owner through Connections. Where it points is read from the
    /// setup itself (`SetupTourStop.current`), so this is the only state the tour keeps.
    var isTouringSetup = false
    /// Where the running tour points, published by Connections so a panel can show the stop's
    /// hint under its own field.
    var setupTourStop: SetupTourStop?
    /// Bumped by Help ▸ Show Tips Again, so every tip gets a fresh identity and can show again.
    var tipGeneration = UserDefaults.standard.integer(forKey: AppModel.tipGenerationKey)
    @ObservationIgnored private var pendingTradingActivation: PendingTradingActivation?
    /// The banner the last check left, so discarding that check takes its banner with it.
    @ObservationIgnored private var checkOutcomeMessage: String?
    @ObservationIgnored private var hasChosenFirstScreen = false

    /// The exact configuration the current check covers; Start Copying saves this one.
    var validatedConfiguration: TradingConfiguration? { pendingTradingActivation?.configuration }

    @ObservationIgnored private var tradingValidationTask: Task<Void, Never>?
    /// Applying changes while copying runs, from checking the draft to starting the new setup.
    @ObservationIgnored var applyChangesTask: Task<Void, Never>?
    @ObservationIgnored private var startupIntent = AppStartupIntent()
    @ObservationIgnored private let appUnlock: AppUnlock
    @ObservationIgnored private let shutdownCoordinator = ShutdownCoordinator()
    @ObservationIgnored private var windowSessionID: UUID?
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var statusTask: Task<Void, Never>?
    @ObservationIgnored private var startupTask: Task<Void, Never>?
    @ObservationIgnored private var runtimeGeneration = RuntimeGeneration()
    @ObservationIgnored private var engineGeneration = RuntimeGeneration()
    @ObservationIgnored private var isStoppingRuntime = false
    @ObservationIgnored private var accessGeneration = 0
    /// Only the real app launch passes a store; other models (tests) keep preferences in memory
    /// and never read the owner's Keychain.
    @ObservationIgnored private let launchPreferencesStore: LaunchPreferencesStore?
    /// Whether this launch already tried starting copying on the owner's behalf.
    @ObservationIgnored var didStartCopyingOnLaunch = false
    /// The engine stopped under copying that was running; once it is back, copying starts again.
    @ObservationIgnored var resumesAfterEngineRestart = false
    /// The saved setup is an earlier version's until `upgradeSavedSetup` finishes; nothing starts
    /// copying meanwhile, at launch, after an update, or after an engine restart.
    @ObservationIgnored var setupAwaitsUpgrade = false
    /// Whether copying was on when the app last stopped, kept across launches.
    @ObservationIgnored let copyingMemory: CopyingMemory
    /// Copying was on when CopyTrading last stopped and has not started again. Read once at launch,
    /// before the engine's first status can clear it, and ended by copying starting or a dismissal.
    var copyingStoppedWithQuit: Bool
    /// The macOS notification for it goes out once per launch.
    /// When the owner was last told copying is paused; it is said again every half hour while it
    /// stays paused during trading hours.
    @ObservationIgnored var copyingStoppedAnnouncedAt: Date?
    @ObservationIgnored var clock: () -> Date = { .now }
    @ObservationIgnored var announceCopyingStopped: () -> Void = {}
    /// How long the launch start waits before each retry after a failed connection check.
    @ObservationIgnored var launchStartRetryDelays: [Duration] = [.seconds(10), .seconds(30), .seconds(60)]
    @ObservationIgnored private var launchStartRetry: Task<Void, Never>?
    /// The last start threw (the engine did not answer in time) instead of reporting failed checks.
    @ObservationIgnored private var launchStartThrew = false
    private(set) var launchPreferences: LaunchPreferences
    @ObservationIgnored private let sleepGuard: SleepGuard

    private struct PendingTradingActivation: Sendable {
        let configuration: TradingConfiguration
        /// The engine's revision of `configuration`; the app never computes its own.
        let revision: String
        let secrets: TradingSecrets
        let validationToken: String
        /// When the engine granted `validationToken`. The grant lasts two minutes.
        let checkedAt: ContinuousClock.Instant
    }

    /// A check's grant ends two minutes after the engine gives it; a Start Copying later than this
    /// checks the connections again first, so a slow start never costs the grant.
    static let validationGrantFreshness: Duration = .seconds(90)
    /// The time Setup Check grants are measured by; tests move it forward.
    @ObservationIgnored var now: @MainActor () -> ContinuousClock.Instant = { .now }

    /// The installation root: `COPYTRADING_STATE_ROOT` when set, else Application Support.
    static var stateRoot: URL {
        ProcessInfo.processInfo.environment["COPYTRADING_STATE_ROOT"].map {
            URL(filePath: $0, directoryHint: .isDirectory)
        } ?? URL.applicationSupportDirectory.appending(path: "CopyTrading", directoryHint: .isDirectory)
    }

    init(
        tradingConfigurationStore: TradingConfigurationStore? = nil,
        tradingStarter: (any TradingStarting)? = nil,
        appUnlock: AppUnlock? = nil,
        launchPreferencesStore: LaunchPreferencesStore? = nil,
        copyingMemory: CopyingMemory = CopyingMemory(),
        agentProposalOperations: (any AgentProposalOperations)? = nil,
        sleepGuard: SleepGuard = SleepGuard()
    ) {
        self.copyingMemory = copyingMemory
        copyingStoppedWithQuit = copyingMemory.wasOn
        proposalOperations = agentProposalOperations
        self.sleepGuard = sleepGuard
        let stateRoot = Self.stateRoot
        let logsDirectory = stateRoot.appending(path: "logs", directoryHint: .isDirectory)
        diagnosticsSettingsStore = DiagnosticsSettingsStore(url: logsDirectory.appending(path: "settings.json"))
        diagnosticsJournal = DiagnosticsJournal(directory: logsDirectory)
        self.tradingConfigurationStore = tradingConfigurationStore
        self.tradingStarter = tradingStarter
        let preferences = launchPreferencesStore?.load() ?? LaunchPreferences()
        self.launchPreferencesStore = launchPreferencesStore
        launchPreferences = preferences
        self.appUnlock = appUnlock ?? AppUnlock(ownerCheckRequired: preferences.asksForOwner)
        loadDiagnosticsSettings()
        loadAgentAccess(stateRoot: stateRoot)
        connectAssistant()
    }

    func startIfNeeded() {
        guard startupIntent.allowsAutomaticStart else { return }
        guard startupTask == nil, runtimeState == .stopped || runtimeState == .failed else { return }
        startupTask = Task { [weak self] in
            guard let self else { return }
            await self.startRuntime()
            self.startupTask = nil
        }
    }

    func requestStart() {
        startupIntent.startRequested()
        startIfNeeded()
    }

    func startRuntime() async {
        do {
            try await launchRuntime(during: nil)
        } catch {
            // Ordinary startup reports its failure through runtimeState and message.
        }
    }

    func startRuntime(during transition: MaintenanceTransition) async throws {
        try await launchRuntime(during: transition)
    }

    private func launchRuntime(
        during transition: MaintenanceTransition?,
        propagateStartupFailure: Bool = false
    ) async throws {
        guard transition != nil || runtimeState == .stopped || runtimeState == .failed else { return }
        let startingGeneration = runtimeGeneration.advance()
        runtimeState = .starting
        message = nil
        runtimeStopMessage = nil

        var unownedLock: InstallationLock?
        var attempt: StartupOwnership?
        do {
            let ownerPaths = try RuntimePaths.discover()
            let paths: RuntimePaths
            let ownedAttempt: StartupOwnership
            let startupAttemptToken: StartupAttemptToken?
            let lock: InstallationLock?
            if let transition {
                guard let existingAttempt = startupOwnership else {
                    throw StartupOwnershipError.staleMaintenanceTransition
                }
                ownedAttempt = existingAttempt
                attempt = existingAttempt
                lock = nil
                startupAttemptToken = nil
                paths = try await existingAttempt.resolveActiveGeneration(
                    from: ownerPaths,
                    during: transition
                )
            } else {
                let acquiredLock = try ownerPaths.acquireInstallationLock()
                unownedLock = acquiredLock
                paths = try ownerPaths.resolveActiveGeneration(whileHolding: acquiredLock)
                let newAttempt = StartupOwnership(lock: acquiredLock)
                ownedAttempt = newAttempt
                attempt = newAttempt
                startupOwnership = newAttempt
                unownedLock = nil
                startupAttemptToken = try await newAttempt.beginStartupAttempt()
                lock = acquiredLock
            }
            guard runtimeGeneration.accepts(startingGeneration), !Task.isCancelled else { throw CancellationError() }
            let identity = try paths.installationIdentity()
            diagnosticsSettingsStore = DiagnosticsSettingsStore(url: paths.logsDirectory.appending(path: "settings.json"))
            diagnosticsJournal = DiagnosticsJournal(directory: paths.logsDirectory)
            diagnosticsFingerprint = nil
            loadDiagnosticsSettings()
            let selectedDiagnosticsSettings = diagnosticsSettings
            appliedDiagnosticsSettings = selectedDiagnosticsSettings
            let tradingKeychain = TradingKeychainStore(
                service: try TradingKeychainStore.service(forInstallationID: identity)
            )
            let configurationStore = TradingConfigurationStore(
                url: paths.applicationSupportDirectory.appending(path: "trading-configuration.json"),
                secrets: tradingKeychain
            )
            tradingConfigurationStore = configurationStore
            if try configurationStore.setAsideBeforeUpgrades() {
                message = L10n.string(
                    "Your setup is from a CopyTrading too old to carry over. It's kept in %@; set up again in Connections.",
                    configurationStore.setAsideURL.lastPathComponent)
            }
            // An earlier version's setup is upgraded once the engine can read its accounts; until
            // then nothing starts copying, so the engine never runs a setup missing a choice.
            let awaitsUpgrade = configurationStore.olderVersion() != nil
            setupAwaitsUpgrade = awaitsUpgrade
            let savedTrading = awaitsUpgrade ? nil : try configurationStore.load()
            savedTradingConfiguration = savedTrading?.configuration
            hasTradingSecrets = savedTrading != nil
            syncSetupDraftWithSaved()
            if !awaitsUpgrade { prefillEmptySetup() }
            // A first launch walks the owner through setup on Connections, until they end the tour;
            // an engine restart later never moves the owner.
            if !hasChosenFirstScreen {
                hasChosenFirstScreen = true
                if savedTrading == nil && !awaitsUpgrade {
                    if !UserDefaults.standard.bool(forKey: Self.setupTourEndedKey) {
                        startSetupTour()
                    }
                } else {
                    selectedScreen = homeScreen
                }
                // The screen a launch opens on is where the owner starts; Back has nothing before it.
                screenHistory = ScreenHistory()
            }
            let newJournal = CommandJournal(url: paths.applicationSupportDirectory.appending(path: "commands.json"))
            selfTestEntries = try await newJournal.entries()
            guard runtimeGeneration.accepts(startingGeneration), !Task.isCancelled else { throw CancellationError() }
            commandJournal = newJournal
            try paths.rejectOrphanedEngine()
            let manifest = try RuntimeResourceCatalog.runtimeManifest()
            let python = try manifest.executable(named: "cpython", under: paths.runtimeRoot)
            let engineRoot = paths.engineSourceRoot.appending(path: "src", directoryHint: .isDirectory)
            let pythonLibraryPath = ProcessInfo.processInfo.environment["COPYTRADING_PYTHON_LIBRARY_PATH"]

            var engineEnvironment = [
                "PATH": "/usr/bin:/bin",
                "PYTHONPATH": engineRoot.path,
                "PYTHONUNBUFFERED": "1",
                "PYTHONDONTWRITEBYTECODE": "1",
                "COPYTRADING_DESKTOP_DIAGNOSTICS_STATE_DIR": paths.logsDirectory.path,
                "COPYTRADING_DESKTOP_OWNER_SUPPORT_DIR": paths.ownerSupportDirectory.path,
            ].merging(selectedDiagnosticsSettings.engineEnvironment) { current, _ in current }
            if let pythonLibraryPath {
                engineEnvironment["PYTHONPATH"] = "\(engineRoot.path):\(pythonLibraryPath)"
            }
            let engine = ProcessLaunchSpecification(
                child: .engine,
                executableURL: python,
                arguments: [
                    "-u", "-m", "copytrading_engine",
                    "--data-dir", paths.applicationSupportDirectory.path,
                    "--instance-id", identity,
                ],
                environment: engineEnvironment,
                workingDirectory: paths.applicationSupportDirectory,
                readiness: .engineStatus(expectedInstanceID: identity),
                stdoutIsIPC: true
            )

            let supervisorConfiguration = ProcessSupervisorConfiguration(
                children: [engine],
                maximumRestarts: 3,
                restartDelay: .seconds(1),
                outputBufferLimit: 8192,
                startupTimeout: .seconds(45)
            )
            let newSupervisor: ProcessSupervisor
            if let transition {
                newSupervisor = try await ownedAttempt.makeSupervisor(
                    configuration: supervisorConfiguration,
                    during: transition
                )
            } else if let lock {
                newSupervisor = ProcessSupervisor(
                    configuration: supervisorConfiguration,
                    installationLock: lock
                )
            } else {
                throw StartupOwnershipError.terminalStopWon
            }
            let adoptedSupervisor: Bool
            if let startupAttemptToken {
                adoptedSupervisor = await ownedAttempt.adopt(newSupervisor, for: startupAttemptToken)
            } else if let transition {
                adoptedSupervisor = await ownedAttempt.adopt(newSupervisor, during: transition)
            } else {
                adoptedSupervisor = false
            }
            guard adoptedSupervisor, runtimeGeneration.accepts(startingGeneration), !Task.isCancelled else {
                throw CancellationError()
            }
            supervisor = newSupervisor
            let actions = EngineActions(supervisor: newSupervisor)
            engineActions = actions
            runtimePaths = paths
            sourcePicturesDirectory = paths.applicationSupportDirectory.appending(
                path: "attachments", directoryHint: .isDirectory)
            observe(newSupervisor)
            try await newSupervisor.start()
            guard runtimeGeneration.accepts(startingGeneration), !Task.isCancelled else {
                throw CancellationError()
            }
            let readyStatus = try await actions.status()
            guard runtimeGeneration.accepts(startingGeneration), !Task.isCancelled else { throw CancellationError() }
            engineStatus = readyStatus
            pendingRestoreCandidate = try await actions.restoreCandidateStatus()
            restorePreflightBlockers = []
            if let pendingRestoreCandidate {
                restoreRecoveryMessage = nil
                restoreCredentialStatus =
                    pendingRestoreCandidate.candidateValid
                    ? L10n.string("The half-finished restore can be resumed.")
                    : L10n.string("The half-finished restore didn't pass its checks, so it can only be rolled back.")
                backupRestoreNote = .problem(
                    L10n.string("A restore is half-finished. Resume it, or roll back to your data from before."))
            } else {
                restoreRecoveryMessage = nil
            }
            tradingStatus = try await actions.tradingStatus()
            if awaitsUpgrade {
                await upgradeSavedSetup(
                    in: configurationStore,
                    recordedRecovery: { try await Self.recordedRecoveryPreferences(using: actions) },
                    revision: { try await actions.updateAccountLimits(configuration: $0) })
            }
            await reconcilePendingTradingActivation(using: actions)
            runtimeState = engineStatus?.telemetryState == .degraded ? .degraded : .ready
            startAgentRelay(stateRoot: paths.ownerSupportDirectory, actions: actions)
            await refreshPendingSelfTest()
            guard runtimeGeneration.accepts(startingGeneration), !Task.isCancelled else { throw CancellationError() }
            startStatusPolling()
        } catch {
            #if DEBUG
                if let supervisor {
                    let tail = await supervisor.stderrTail(for: .engine)
                    FileHandle.standardError.write(Data("desktop startup engine stderr:\n\(tail)\n".utf8))
                }
            #endif
            if let transition, let attempt {
                do {
                    _ = try await attempt.stopReplacementForMaintenance(during: transition)
                } catch {
                    message = L10n.string(
                        "Restore recovery could not stop the replacement runtime. The durable gate and installation lock remain held.")
                }
            } else {
                unownedLock?.release()
                await attempt?.stop()
            }
            if transition != nil {
                guard runtimeGeneration.accepts(startingGeneration) else { throw error }
            } else {
                guard runtimeGeneration.accepts(startingGeneration) else { return }
            }
            supervisor = nil
            if transition == nil { startupOwnership = nil }
            await assistant.reset()
            stopAgentRelay()
            engineActions = nil
            tradingStatus = nil
            runtimeState = .failed
            if message == nil { message = Self.userMessage(for: error) }
            FileHandle.standardError.write(Data("desktop startup failed: \(message ?? "unknown")\n".utf8))
            #if DEBUG
                FileHandle.standardError.write(Data("desktop startup error: \(String(reflecting: error))\n".utf8))
            #endif
            if transition != nil || propagateStartupFailure { throw error }
        }
    }

    func stopRuntime() async {
        startupIntent.stop()
        isStoppingRuntime = true
        await shutdownCoordinator.run { [weak self] in
            await self?.performRuntimeShutdown()
        }
        isStoppingRuntime = false
    }

    /// Invalidates any status read that began before the machine woke. It does
    /// not start a stopped runtime or override an explicit Stop/pause choice.
    func runtimeDidWake() {
        guard !isStoppingRuntime,
            supervisor != nil,
            runtimeState == .ready || runtimeState == .degraded
        else { return }
        engineGeneration.advance()
        startStatusPolling()
    }

    private func performRuntimeShutdown() async {
        await assistant.reset()
        runtimeGeneration.advance()
        engineGeneration.advance()
        startupTask?.cancel()
        startupTask = nil
        statusTask?.cancel()
        statusTask = nil
        eventTask?.cancel()
        eventTask = nil
        let stopReport: ProcessSupervisorStopReport
        if let startupOwnership {
            stopReport = await startupOwnership.stop()
        } else if let supervisor {
            stopReport = await supervisor.stop()
        } else {
            stopReport = .noLiveEngine
        }
        runtimeStopMessage = Self.stopMessage(for: stopReport)
        supervisor = nil
        startupOwnership = nil
        stopAgentRelay()
        engineActions = nil
        engineStatus = nil
        tradingStatus = nil
        runtimeState = .stopped
        message = nil
    }

    /// How the engine stopped, in the owner's words: whether it finished what it was doing, and
    /// that orders the broker already took can still fill.
    static func stopMessage(for report: ProcessSupervisorStopReport) -> String {
        let how: String
        switch report.engineDrainAcknowledgement {
        case .acknowledged:
            how = L10n.string("The engine finished what it was doing and stopped.")
        case .unconfirmed:
            how = L10n.string("The engine didn't answer, so CopyTrading stopped it.")
        case .noLiveEngine:
            how = L10n.string("The engine wasn't running.")
        }
        let forced = report.forciblyStoppedChildren.isEmpty ? nil : L10n.string("It had to be forced to stop.")
        // Sentences join through the catalog: a space in English, none in Chinese.
        return [forced, L10n.string("Orders the broker already accepted may stay open until they fill or expire.")]
            .compactMap { $0 }
            .reduce(how) { L10n.string("%@ %@", $0, $1) }
    }

    private func loadDiagnosticsSettings() {
        do {
            diagnosticsSettings = try diagnosticsSettingsStore.load() ?? DiagnosticsSettings()
            diagnosticsSettingsWarning = nil
        } catch {
            diagnosticsSettings = DiagnosticsSettings()
            diagnosticsSettingsWarning = L10n.string("Saved log settings could not be read, so the defaults apply.")
        }
    }

    func saveDiagnosticsSettings(ageDays: Int, storageLimitBytes: Int64) {
        do {
            let settings = try DiagnosticsSettings(ageDays: ageDays, storageLimitBytes: storageLimitBytes)
            try diagnosticsSettingsStore.save(settings)
            diagnosticsSettings = settings
            diagnosticsSettingsWarning = nil
        } catch {
            diagnosticsSettingsWarning = Self.userMessage(for: error)
        }
    }

    /// Re-reads the journal from disk; it works whether or not the engine is running.
    func reloadDiagnostics() async {
        guard !isLoadingDiagnostics else { return }
        isLoadingDiagnostics = true
        defer { isLoadingDiagnostics = false }
        let journal = diagnosticsJournal
        let previous = diagnosticsFingerprint
        do {
            // The page polls every few seconds; an unchanged journal is not read or parsed again.
            let read = try await Task.detached(priority: .userInitiated) {
                () -> (fingerprint: [String], entries: [DiagnosticsJournalEntry], bytes: Int64)? in
                let fingerprint = journal.fingerprint()
                guard fingerprint != previous else { return nil }
                return (fingerprint, try journal.entries(), journal.usageBytes())
            }.value
            guard let read else { return }
            diagnosticsFingerprint = read.fingerprint
            diagnosticsEntries = read.entries
            diagnosticsJournalBytes = read.bytes
            diagnosticsJournalMessage = nil
        } catch {
            diagnosticsJournalMessage = Self.userMessage(for: error)
        }
    }

    /// The journal itself, already redacted by the engine, for a support file the owner saves.
    func diagnosticsExportText() throws -> String {
        try diagnosticsJournal.exportText()
    }

    /// Whether the local engine takes commands; the self-test waits for it.
    var isEngineRunning: Bool { runtimeState == .ready || runtimeState == .degraded }

    func runSelfTest() async {
        guard engineActions != nil else {
            message = L10n.string("The engine isn't running. Start it in Settings → Engine. If another CopyTrading is open, quit it first.")
            return
        }
        guard pendingCommandID == nil else {
            message = L10n.string("Look up the pending command before starting another self-test.")
            return
        }
        guard !isRunningSelfTest else { return }
        isRunningSelfTest = true
        defer { isRunningSelfTest = false }
        let command = SelfTestCommand(
            commandID: UUID().uuidString.lowercased(),
            text: selfTestText,
            destinationIDs: ["self-test-a", "self-test-b"]
        )
        do {
            guard let commandJournal else { throw CommandJournalError.unavailable }
            try await commandJournal.record(command)
            selfTestEntries = try await commandJournal.entries()
            try await submit(command)
            await refreshStatus()
            message = nil
        } catch {
            message = Self.userMessage(for: error)
        }
    }

    func refreshStatus() async {
        guard let engineActions else { return }
        let currentRuntimeGeneration = runtimeGeneration.current
        let currentEngineGeneration = engineGeneration.current
        do {
            let status = try await engineActions.status()
            guard runtimeGeneration.accepts(currentRuntimeGeneration),
                engineGeneration.accepts(currentEngineGeneration)
            else { return }
            engineStatus = status
            tradingStatus = try await engineActions.tradingStatus()
            guard runtimeGeneration.accepts(currentRuntimeGeneration),
                engineGeneration.accepts(currentEngineGeneration)
            else { return }
            await reconcilePendingTradingActivation(using: engineActions)
            await saveLimitsAwaitingStart()
            guard runtimeGeneration.accepts(currentRuntimeGeneration),
                engineGeneration.accepts(currentEngineGeneration)
            else { return }
            if status.state == .running {
                runtimeState = status.telemetryState == .degraded ? .degraded : .ready
            }
            await refreshPendingSelfTest()
            await refreshAgentActivity()
        } catch {
            guard runtimeGeneration.accepts(currentRuntimeGeneration),
                engineGeneration.accepts(currentEngineGeneration)
            else { return }
            runtimeState = .degraded
            message = Self.userMessage(for: error)
        }
    }

    /// Where a guru posts and the keys to read it with: keys left blank in Setup fall back to the
    /// saved ones, exactly as Validate does.
    private func channelReading(
        for route: TradingRouteDraft, in draft: ConnectionsDraft, locked: String, stopped: String
    ) throws -> (engine: any TradingStarting, channelID: String, discordToken: String, providerAPIKey: String) {
        func fail(_ reason: String) -> TradingSettingsError { .invalidConfiguration(reason) }
        guard isTradingUnlocked else { throw fail(locked) }
        guard let engine: any TradingStarting = tradingStarter ?? engineActions else { throw fail(stopped) }
        let channelID = draft.effectiveChannel(for: route)
        guard !channelID.isEmpty else { throw fail(L10n.string("Add the guru's Discord channel ID first.")) }
        guard !draft.modelName.trimmed.isEmpty else { throw fail(L10n.string("Choose a model under Interpreter first.")) }
        let stored = try tradingConfigurationStore?.load()
        let saved = stored?.secrets
        let discordToken = draft.discordToken.isEmpty ? saved?.discordToken ?? "" : draft.discordToken
        let providerAPIKey = Self.providerKey(
            entered: draft.providerAPIKey, for: draft.provider, saved: stored)
        if let problem = draft.providerConfiguration.baseURLProblem { throw fail(problem) }
        let missing = [
            discordToken.isEmpty ? "the Discord token" : nil,
            providerAPIKey.isEmpty && draft.provider.requiresAPIKey ? "the model API key" : nil,
        ].compactMap(\.self)
        guard missing.isEmpty else {
            throw TradingSettingsError.missingCredentials(L10n.list(missing))
        }
        return (engine, channelID, discordToken, providerAPIKey)
    }

    /// Reads the route's channel and has the configured model draft a playbook. Nothing is saved.
    func learnPlaybook(for route: TradingRouteDraft, in draft: ConnectionsDraft) async throws -> LearnedGuruPlaybook {
        let reading = try channelReading(
            for: route, in: draft, locked: L10n.string("Unlock CopyTrading before learning a playbook."),
            stopped: L10n.string("The engine isn't running. Start it in Settings → Engine. If another CopyTrading is open, quit it first."))
        do {
            return try await reading.engine.learnGuruPlaybook(
                GuruPlaybookLearningRequest(
                    channelID: reading.channelID,
                    authorID: route.authorID.trimmed.nilIfEmpty,
                    discordToken: reading.discordToken,
                    provider: draft.providerConfiguration,
                    providerAPIKey: reading.providerAPIKey
                ))
        } catch EngineContractError.remote(code: _, message: let message?, reason: _) {
            throw TradingSettingsError.invalidConfiguration(message)
        } catch is EngineContractError {
            throw TradingSettingsError.invalidConfiguration(L10n.string("The engine could not learn from this channel. Try again."))
        }
    }

    /// Checks the setup in two stages: the draft and its keys, which needs no pause, then every
    /// connection, which the engine runs only while copying is paused. `beforePause` stops after
    /// the first stage. Returns whether every stage asked for passed.
    @discardableResult
    func validateTradingSettings(
        _ configuration: TradingConfiguration, enteredSecrets: TradingSecrets, beforePause: Bool = false
    ) async -> Bool {
        defer { checkOutcomeMessage = message }
        guard !isRunningBackupRestore else {
            message = L10n.string("Wait for the backup or restore to finish, then check the setup.")
            return false
        }
        guard isTradingUnlocked else {
            message = L10n.string("Unlock CopyTrading first.")
            return false
        }
        guard let tradingConfigurationStore else {
            message = L10n.string("CopyTrading is still starting. Check the setup again in a moment.")
            return false
        }
        guard beforePause || tradingStatus?.state.isStopped == true, !isTradingCommandPending else {
            message = L10n.string("Pause copying before checking the setup.")
            return false
        }
        guard let validator: (any TradingStarting) = tradingStarter ?? engineActions else {
            message = L10n.string("CopyTrading is still starting. Check the setup again in a moment.")
            return false
        }
        guard !isValidatingTrading, !isActivatingTrading else { return false }
        isValidatingTrading = true
        tradingValidation = nil
        isShowingSetupCheck = false
        pendingTradingActivation = nil
        defer { isValidatingTrading = false }
        do {
            try Self.validateTradingConfiguration(configuration)
            let stored = try tradingConfigurationStore.load()
            let previous = stored?.secrets
            let existingBrokers = Dictionary(
                uniqueKeysWithValues: (previous?.brokers ?? []).map { ($0.accountID, $0) }
            )
            let brokers = try configuration.accounts.map { account in
                let entered = enteredSecrets.brokers.first { $0.accountID == account.id }
                let previousBroker = existingBrokers[account.id]
                let key =
                    entered.flatMap { $0.key.isEmpty ? nil : $0.key }
                    ?? previousBroker?.key ?? ""
                let secret =
                    entered.flatMap { $0.secret.isEmpty ? nil : $0.secret }
                    ?? previousBroker?.secret ?? ""
                guard !key.isEmpty, !secret.isEmpty else {
                    throw TradingSettingsError.missingCredentials(L10n.string("the Alpaca API key and secret for “%@”", account.id))
                }
                return TradingBrokerCredentials(accountID: account.id, key: key, secret: secret)
            }
            let discordToken =
                enteredSecrets.discordToken.isEmpty
                ? previous?.discordToken ?? "" : enteredSecrets.discordToken
            let providerAPIKey = Self.providerKey(
                entered: enteredSecrets.providerAPIKey, for: configuration.provider.name, saved: stored)
            // A saved bot token is no webhook URL: it is kept only while alerts stay on its service.
            let sameAlertService = stored?.configuration.notification?.service == configuration.notification?.service
            let notificationToken =
                enteredSecrets.notificationToken?.isEmpty == false
                ? enteredSecrets.notificationToken : sameAlertService ? previous?.notificationToken : nil
            let missing = [
                discordToken.isEmpty ? "the Discord token" : nil,
                providerAPIKey.isEmpty && configuration.provider.name.requiresAPIKey ? "the model API key" : nil,
                configuration.notification != nil && notificationToken?.isEmpty != false
                    ? (configuration.notification?.service == .discord ? "the Discord webhook URL" : "the Telegram bot token") : nil,
            ].compactMap(\.self)
            guard missing.isEmpty else {
                throw TradingSettingsError.missingCredentials(L10n.list(missing))
            }
            let secrets = TradingSecrets(
                discordToken: discordToken, providerAPIKey: providerAPIKey,
                brokers: brokers, notificationToken: notificationToken
            )
            if beforePause {
                message = nil
                return true
            }
            let validation = try await validator.validateTrading(
                configuration: configuration, secrets: secrets
            )
            guard !Task.isCancelled else { throw CancellationError() }
            tradingValidation = validation
            recordConnectionChecks(validation.report.checks)
            guard validation.report.activatable, let activationToken = validation.activationToken else {
                message = L10n.string("Some connections need attention. Nothing was saved.")
                isShowingSetupCheck = true
                return false
            }
            pendingTradingActivation = PendingTradingActivation(
                configuration: configuration,
                revision: validation.report.configurationRevision,
                secrets: secrets,
                validationToken: activationToken,
                checkedAt: now()
            )
            // The changes bar says the check passed.
            message = nil
            return true
        } catch {
            if error is CancellationError {
                tradingValidation = nil
                message = L10n.string("Check cancelled. Nothing was saved.")
            } else {
                message = Self.userMessage(for: error)
            }
            return false
        }
    }

    /// Checks the setup; with `thenStart`, starts copying straight after when everything passed,
    /// and otherwise shows what needs the owner.
    @discardableResult
    func beginTradingValidation(
        _ configuration: TradingConfiguration, enteredSecrets: TradingSecrets, thenStart: Bool = false
    ) -> Task<Void, Never> {
        tradingValidationTask?.cancel()
        let task = Task { [weak self] in
            guard let self else { return }
            if thenStart {
                await self.checkThenStart(configuration, enteredSecrets: enteredSecrets)
            } else {
                await self.validateTradingSettings(configuration, enteredSecrets: enteredSecrets)
            }
        }
        tradingValidationTask = task
        return task
    }

    /// Checks the setup, then starts it when everything passed; otherwise shows what needs the
    /// owner.
    func checkThenStart(_ configuration: TradingConfiguration, enteredSecrets: TradingSecrets) async {
        await validateTradingSettings(configuration, enteredSecrets: enteredSecrets)
        guard !Task.isCancelled else { return }
        if canStartCopyingFromCheck {
            await activateValidatedTradingSettings()
        } else if tradingValidation != nil {
            isShowingSetupCheck = true
        }
    }

    func activateValidatedTradingSettings() async {
        guard !isRunningBackupRestore else {
            message = L10n.string("Wait for the backup or restore to finish, then start copying.")
            return
        }
        guard isTradingUnlocked else {
            message = L10n.string("Unlock CopyTrading first.")
            return
        }
        guard let pending = pendingTradingActivation,
            let tradingConfigurationStore,
            let starter = tradingStarter ?? engineActions
        else {
            message = L10n.string("Check the setup before starting to copy.")
            return
        }
        guard tradingStatus?.state.isStopped == true, !isTradingCommandPending,
            !isActivatingTrading
        else {
            message = L10n.string("Pause copying before starting a new setup.")
            return
        }
        isActivatingTrading = true
        isTradingCommandPending = true
        defer {
            isActivatingTrading = false
            isTradingCommandPending = false
        }
        guard await confirmLiveStart(pending.configuration) else { return }
        let activationID = UUID().uuidString.lowercased()
        do {
            guard let pending = try await freshlyGranted(pending, using: starter) else { return }
            try tradingConfigurationStore.stageValidatedActivation(
                configuration: pending.configuration,
                revision: pending.revision,
                secrets: pending.secrets,
                activationID: activationID,
                when: .paused
            )
            do {
                tradingStatus = try await starter.startTrading(
                    configuration: pending.configuration,
                    secrets: pending.secrets,
                    validationToken: pending.validationToken,
                    activationID: activationID
                )
            } catch {
                // Start may have been accepted even when its response was lost.
                // Only the durable engine activation query can settle that ambiguity.
                message = L10n.string("CopyTrading didn't hear back after starting. It keeps checking whether the new setup took effect.")
            }
            await reconcilePendingTradingActivation(using: starter)
        } catch {
            message = Self.userMessage(for: error)
        }
    }

    /// The activation with a grant the engine still honors: an older check runs the connection
    /// checks again for a new one. Nil when a connection fails now; Setup Check then shows it.
    private func freshlyGranted(
        _ pending: PendingTradingActivation, using starter: any TradingStarting
    ) async throws -> PendingTradingActivation? {
        guard now() - pending.checkedAt >= Self.validationGrantFreshness else { return pending }
        let validation = try await starter.validateTrading(
            configuration: pending.configuration, secrets: pending.secrets
        )
        tradingValidation = validation
        recordConnectionChecks(validation.report.checks)
        guard validation.report.activatable, let token = validation.activationToken,
            validation.report.configurationRevision == pending.revision
        else {
            pendingTradingActivation = nil
            message = L10n.string("Some connections need attention. Nothing was saved.")
            isShowingSetupCheck = true
            return nil
        }
        let renewed = PendingTradingActivation(
            configuration: pending.configuration, revision: pending.revision, secrets: pending.secrets,
            validationToken: token, checkedAt: now()
        )
        pendingTradingActivation = renewed
        return renewed
    }

    func confirmLiveProcessing() async {
        if pendingTradingActivation != nil {
            await activateValidatedTradingSettings()
        } else {
            await startTrading()
        }
    }

    func reconcilePendingTradingActivation(using control: any TradingStarting) async {
        guard !isRunningBackupRestore else { return }
        guard let tradingConfigurationStore,
            let pending = try? tradingConfigurationStore.pendingActivation(),
            pending.activationID.isEmpty == false
        else {
            isConfirmingActivation = false
            return
        }
        isConfirmingActivation = true
        defer { isConfirmingActivation = (try? tradingConfigurationStore.pendingActivation()) != nil }
        do {
            let status = try await control.tradingActivation(activationID: pending.activationID)
            if let current = try? await control.tradingStatus() {
                tradingStatus = current
            }
            // The engine already copying with the candidate's revision is as good as a commit: a
            // resume of the saved setup that lost Discord while starting keeps copying with it, so
            // there is nothing to wait for or roll back.
            let runsCandidate =
                status.phase != .starting
                && status.committedRevision == pending.candidateRevision
                && (status.runtimeState == .running || status.runtimeState == .degraded)
            let activationCommitted =
                runsCandidate
                || (status.activationID == pending.activationID
                    && status.candidateRevision == pending.candidateRevision
                    && status.committedRevision == pending.candidateRevision
                    && status.committedActivationID == pending.activationID)
            if activationCommitted && (runsCandidate || status.phase == .ready || status.phase == .stopped) {
                try tradingConfigurationStore.finalizeValidatedActivation(
                    activationID: pending.activationID
                )
                let saved = try tradingConfigurationStore.load()
                savedTradingConfiguration = saved?.configuration
                hasTradingSecrets = saved != nil
                pendingTradingActivation = nil
                tradingValidation = nil
                settleSetupDraftAfterStart()
                didStartCopyingNewSetup()
                await saveLimitsAwaitingStart()
                return
            }

            let terminal =
                status.phase == .failed || status.phase == .stopped
                || status.phase == .interrupted || status.phase == .notFound
            let stopped = status.runtimeState == .paused || status.runtimeState == .failed
            if terminal && stopped && !activationCommitted {
                try tradingConfigurationStore.rollbackValidatedActivation(
                    activationID: pending.activationID
                )
                let before = savedTradingConfiguration
                let saved = try tradingConfigurationStore.load()
                savedTradingConfiguration = saved?.configuration
                hasTradingSecrets = saved != nil
                pendingTradingActivation = nil
                tradingValidation = nil
                syncSetupDraftWithSaved()
                let why = StartFailure.text(
                    errorCode: status.errorCode, accounts: tradingStatus?.accounts ?? [],
                    modelService: setupDraft.provider.title)
                // Starting the saved setup again is not a new setup, so there is nothing to keep.
                message =
                    saved == nil || saved?.configuration == before
                    ? L10n.string("Copying didn't start. %@", why)
                    : L10n.string("The new setup didn't start, so your previous setup is still in place. %@", why)
                await saveLimitsAwaitingStart()
                return
            }
            // An activation the engine is still committing is progress, even with accounts already
            // running; only one that stopped advancing without committing is unresolved.
            if status.phase != .starting, let current = tradingStatus, current.activeAccounts > 0 {
                message =
                    L10n.string(
                        "CopyTrading can't confirm the new setup yet. Copying continues for %@; pause copying before changing the setup again.",
                        Humanize.count(current.activeAccounts, "account"))
            } else {
                message = Self.pendingSetupMessage
            }
        } catch {
            // The next status check asks again; the owner only needs to know it is still going.
            message = L10n.string("Checking whether copying started…")
        }
    }

    /// Starts the saved setup. `resumingSavedSetup` puts back a setup that was copying moments
    /// ago, paused only to apply changes: the owner approved it already, so neither the unlock nor
    /// a live account's Touch ID is asked for again.
    func startTrading(resumingSavedSetup: Bool = false) async {
        guard !isRunningBackupRestore else {
            message = L10n.string("Wait for the backup or restore preview to finish before starting processing.")
            return
        }
        guard isTradingUnlocked || resumingSavedSetup else {
            message = L10n.string("Unlock trading controls before starting processing.")
            return
        }
        let starter: (any TradingStarting)? = tradingStarter ?? engineActions
        guard let starter, let tradingConfigurationStore,
            savedTradingConfiguration != nil
        else {
            message = L10n.string("Start the local engine and save trading settings first.")
            return
        }
        guard !isTradingCommandPending else { return }
        isTradingCommandPending = true
        defer { isTradingCommandPending = false }
        launchStartThrew = false
        do {
            if try tradingConfigurationStore.pendingActivation() != nil {
                await reconcilePendingTradingActivation(using: starter)
                return
            }
            guard let saved = try tradingConfigurationStore.load() else {
                throw TradingSettingsError.missingCredentials("the saved credentials in Connections")
            }
            if !resumingSavedSetup {
                guard await confirmLiveStart(saved.configuration) else { return }
            }
            let validation = try await starter.validateTrading(
                configuration: saved.configuration, secrets: saved.secrets
            )
            tradingValidation = validation
            recordConnectionChecks(validation.report.checks)
            guard validation.report.activatable, let token = validation.activationToken else {
                message = failedChecksMessage(validation.report)
                return
            }
            let activationID = UUID().uuidString.lowercased()
            try tradingConfigurationStore.stageSavedResume(
                activationID: activationID, revision: validation.report.configurationRevision,
                when: .paused
            )
            do {
                tradingStatus = try await starter.startTrading(
                    configuration: saved.configuration,
                    secrets: saved.secrets,
                    validationToken: token,
                    activationID: activationID
                )
            } catch {
                message = L10n.string("CopyTrading didn't hear back after starting. It keeps checking whether copying started.")
            }
            await reconcilePendingTradingActivation(using: starter)
        } catch {
            // The engine not answering in time is a failed start, which a launch start retries.
            launchStartThrew = true
            message = Self.userMessage(for: error)
        }
    }

    func pauseTrading() async {
        launchStartRetry?.cancel()
        guard let control: (any TradingStarting) = tradingStarter ?? engineActions else {
            message = AccountFeatureModel.noEngine
            return
        }
        guard !isTradingCommandPending else { return }
        isTradingCommandPending = true
        defer { isTradingCommandPending = false }
        do {
            tradingStatus = try await control.pauseTrading()
            message = nil
        } catch {
            message = Self.userMessage(for: error)
        }
    }

    /// When limits are all the draft changes, copying takes them now: no check, no Apply Changes,
    /// no pause. The engine answers with the new setup's revision, which is saved with it, so the
    /// next check and Start match the engine. `accounts` names the accounts to save: an account
    /// sheet saves only its own, and a live account whose limits an agent changed never saves this
    /// way. nil saves every changed account, for an agent's apply the engine allowed. Returns nil
    /// when the draft changes more than limits, which wait for the full check; otherwise whether
    /// the limits were saved.
    @discardableResult
    func saveLimitOnlyChanges(for accounts: Set<String>? = nil) async -> Bool? {
        limitsSaveRefused = false
        guard isTradingUnlocked, !setupDraft.hasTypedSecrets,
            let saved = savedTradingConfiguration,
            let draft = try? setupDraft.submission().0,
            let allChanged = draft.limitOnlyChanges(from: saved),
            let tradingConfigurationStore,
            let control: (any TradingStarting) = tradingStarter ?? engineActions
        else { return nil }
        let liveAgentEdits = Set(
            draft.accounts.filter { $0.environment == .live && agentLimitEdits.contains($0.id) }.map(\.id))
        let chosen = accounts.map { Set(allChanged).intersection($0) } ?? Set(allChanged)
        if accounts != nil, !chosen.isDisjoint(with: liveAgentEdits) { return nil }
        guard !chosen.isEmpty else { return true }
        var edited = saved
        for index in edited.accounts.indices where chosen.contains(edited.accounts[index].id) {
            if let policy = draft.accounts.first(where: { $0.id == edited.accounts[index].id })?.policy {
                edited.accounts[index].policy = policy
            }
        }
        // A start in flight owns the saved setup; the limits wait for it and save right after,
        // whether copying started or not.
        guard !isTradingCommandPending, !isValidatingTrading, !isActivatingTrading, pendingTradingActivation == nil,
            (try? tradingConfigurationStore.pendingActivation()) == nil
        else {
            limitsAwaitingStart = true
            limitsAwaitingAccountIDs.formUnion(chosen)
            limitsSavedAccountIDs.formUnion(chosen)
            return true
        }
        limitsAwaitingStart = false
        isTradingCommandPending = true
        defer { isTradingCommandPending = false }
        do {
            try Self.validateTradingConfiguration(edited)
            let revision = try await control.updateAccountLimits(configuration: edited)
            try tradingConfigurationStore.saveLimits(configuration: edited, revision: revision)
            savedTradingConfiguration = edited
            setupDraftSource = edited
            tradingValidation = nil
            limitsSavedAccountIDs.formUnion(chosen)
            agentLimitEdits.subtract(chosen)
            limitsSaveRefused = false
            message = nil
            return true
        } catch {
            limitsSaveRefused = true
            message = Self.userMessage(for: error)
            return false
        }
    }

    /// A start is being confirmed, so the saved setup is not the app's to change yet.
    var hasPendingActivation: Bool {
        pendingTradingActivation != nil || (try? tradingConfigurationStore?.pendingActivation()) != nil
    }

    /// Saves the setup the latest check passed, keys included, without starting copying: an
    /// agent's apply while copying is paused keeps it paused. The next Start Copying checks it
    /// again and starts it. Returns whether it was saved.
    func saveCheckedSetupWithoutStarting() -> Bool {
        guard let pending = pendingTradingActivation, let tradingConfigurationStore, tradingStatus?.state == .paused
        else { return false }
        do {
            try tradingConfigurationStore.save(
                configuration: pending.configuration, revision: pending.revision, secrets: pending.secrets,
                when: .paused)
        } catch {
            message = Self.userMessage(for: error)
            return false
        }
        pendingTradingActivation = nil
        tradingValidation = nil
        checkedSetupSignature = nil
        savedTradingConfiguration = pending.configuration
        hasTradingSecrets = true
        settleSetupDraftAfterStart()
        message = nil
        return true
    }

    /// Start Copying as an agent asked for and the owner approved: the button's own checks and start.
    /// Returns nil once copying is starting or running, or a code that says why it did not.
    func startCopyingForAgent() async -> String? {
        guard isTradingUnlocked else { return "unavailable" }
        guard savedTradingConfiguration != nil else { return "no_saved_setup" }
        guard !isTradingCommandPending, !isValidatingTrading, !isActivatingTrading else { return "busy" }
        await startTrading()
        switch tradingStatus?.state {
        case .running, .starting, .degraded: return nil
        default: return tradingValidation?.report.activatable == false ? "failed_checks" : "failed"
        }
    }

    /// Limits an agent asked for and the owner approved go over the saved setup the way the account
    /// sheet's limit save does: no check, no pause. Returns nil once they took effect, or a code
    /// that says why nothing changed; unsaved edits and a start in flight are never overwritten.
    func applyAgentLimitChanges(accountID: String, changes: [AgentLimitChange]) async -> String? {
        await applyAgentPolicyEdit(accountID: accountID) { try $0.applying(changes) }
    }

    /// What an account does after a restart, as an agent asked and the owner approved: a setup
    /// change saved like a limit.
    func applyAgentRecovery(accountID: String, preference: String) async -> String? {
        guard let preference = RecoveryPreference(rawValue: preference) else { return "invalid_request" }
        return await applyAgentPolicyEdit(accountID: accountID) { policy in
            var edited = policy
            edited.recoveryPreference = preference
            return edited
        }
    }

    private func applyAgentPolicyEdit(
        accountID: String, _ edit: (TradingAccountPolicy) throws -> TradingAccountPolicy
    ) async -> String? {
        syncSetupDraftWithSaved()
        guard isTradingUnlocked, let saved = savedTradingConfiguration, let tradingConfigurationStore,
            let control: (any TradingStarting) = tradingStarter ?? engineActions
        else { return "unavailable" }
        guard !hasUnsavedSetupChanges else { return "unsaved_changes" }
        guard !isTradingCommandPending, !isValidatingTrading, !isActivatingTrading, pendingTradingActivation == nil,
            (try? tradingConfigurationStore.pendingActivation()) == nil
        else { return "busy" }
        guard let index = saved.accounts.firstIndex(where: { $0.id == accountID }) else { return "not_found" }
        var edited = saved
        do {
            edited.accounts[index].policy = try edit(saved.accounts[index].policy)
        } catch {
            return "invalid_request"
        }
        guard edited != saved else { return nil }
        isTradingCommandPending = true
        defer { isTradingCommandPending = false }
        do {
            try Self.validateTradingConfiguration(edited)
            let revision = try await control.updateAccountLimits(configuration: edited)
            try tradingConfigurationStore.saveLimits(configuration: edited, revision: revision)
            savedTradingConfiguration = edited
            tradingValidation = nil
            syncSetupDraftWithSaved()
            limitsSavedAccountIDs.insert(accountID)
            message = nil
            return nil
        } catch {
            return "failed"
        }
    }

    /// Limits edited while a start was in flight, saved once it settles.
    func saveLimitsAwaitingStart() async {
        guard limitsAwaitingStart, !isTradingCommandPending else { return }
        limitsAwaitingStart = false
        let accounts = limitsAwaitingAccountIDs
        limitsAwaitingAccountIDs = []
        await saveLimitOnlyChanges(for: accounts)
    }

    /// While unlocked, the engine may read every saved account live, so a paused account still
    /// shows its money; locking takes the keys back. Copying stays the only path to an order.
    func shareAccountReadKeys() {
        guard let engineActions else { return }
        guard isTradingUnlocked, let stored = try? tradingConfigurationStore?.load() else {
            Task { try? await engineActions.detachAccountReaders() }
            return
        }
        let environments = Dictionary(
            stored.configuration.accounts.map { ($0.id, $0.environment) }, uniquingKeysWith: { first, _ in first })
        let keys = stored.secrets.brokers.compactMap { broker in
            environments[broker.accountID].map {
                AccountReadKeys(accountID: broker.accountID, environment: $0, key: broker.key, secret: broker.secret)
            }
        }
        Task { try? await engineActions.attachAccountReaders(keys) }
    }

    func unlockTrading() async {
        guard !isUnlockingTrading else { return }
        guard let windowSessionID else {
            accessMessage = L10n.string("Open the CopyTrading window to unlock private controls.")
            return
        }
        let openingGeneration = accessGeneration
        isUnlockingTrading = true
        defer {
            if accessGeneration == openingGeneration,
                self.windowSessionID == windowSessionID
            {
                isUnlockingTrading = false
            }
        }
        do {
            try await appUnlock.openWindow(windowSessionID, localizedReason: "Access CopyTrading")
            guard accessGeneration == openingGeneration,
                self.windowSessionID == windowSessionID
            else { return }
            isTradingUnlocked = true
            accessMessage = nil
            message = nil
        } catch {
            guard accessGeneration == openingGeneration,
                self.windowSessionID == windowSessionID
            else { return }
            isTradingUnlocked = false
            accessMessage = Self.userMessage(for: error)
        }
    }

    @discardableResult
    func windowDidOpen(_ sessionID: UUID) -> Task<Void, Never>? {
        guard windowSessionID != sessionID else { return nil }
        windowSessionID = sessionID
        accessGeneration += 1
        let openingGeneration = accessGeneration
        isTradingUnlocked = false
        isUnlockingTrading = true
        accessMessage = nil
        return Task { [weak self] in
            await self?.authenticateWindowSession(sessionID, generation: openingGeneration)
        }
    }

    @discardableResult
    func windowDidClose(_ sessionID: UUID) -> Task<Void, Never>? {
        guard windowSessionID == sessionID else { return nil }
        // Changes still being applied stop here; the saved setup copies again below.
        let applying = applyChangesTask
        applyChangesTask = nil
        applying?.cancel()
        windowSessionID = nil
        accessGeneration += 1
        isTradingUnlocked = false
        isUnlockingTrading = false
        accessMessage = nil
        assistant.isOpen = false
        discardSetupWork()
        return Task { [weak self] in
            guard let self else { return }
            await self.finishInterruptedApply(applying)
            await self.assistant.reset()
            await self.discardAgentProposals()
            await self.appUnlock.closeWindow(sessionID)
        }
    }

    private func authenticateWindowSession(_ sessionID: UUID, generation: Int) async {
        guard accessGeneration == generation, windowSessionID == sessionID else { return }
        do {
            try await appUnlock.openWindow(sessionID)
            guard accessGeneration == generation, windowSessionID == sessionID else {
                await appUnlock.closeWindow(sessionID)
                return
            }
            isTradingUnlocked = true
            accessMessage = nil
            message = nil
        } catch {
            guard accessGeneration == generation, windowSessionID == sessionID else { return }
            isTradingUnlocked = false
            accessMessage = Self.userMessage(for: error)
        }
        if accessGeneration == generation, windowSessionID == sessionID {
            isUnlockingTrading = false
        }
    }

    /// Turning the owner check off is itself confirmed with Touch ID; turning it on is not.
    func setAsksForOwner(_ asks: Bool) async {
        guard asks != launchPreferences.asksForOwner else { return }
        if !asks {
            do {
                try await appUnlock.confirm(localizedReason: "open CopyTrading without asking for Touch ID")
            } catch {
                message = Self.userMessage(for: error)
                return
            }
        }
        var chosen = launchPreferences
        chosen.asksForOwner = asks
        guard saveLaunchPreferences(chosen) else { return }
        await appUnlock.setOwnerCheckRequired(asks)
    }

    func setKeepsMacAwake(_ keeps: Bool) {
        guard keeps != launchPreferences.keepsMacAwake else { return }
        var chosen = launchPreferences
        chosen.keepsMacAwake = keeps
        saveLaunchPreferences(chosen)
    }

    /// Copying is on: the engine is up and copying is starting, running, or running with a problem
    /// it is working through. A stopped or failed engine copies nothing, whatever it last reported.
    var isCopying: Bool {
        [.starting, .ready, .degraded].contains(runtimeState)
            && [.starting, .running, .degraded].contains(tradingStatus?.state)
    }

    /// Holds the Mac awake exactly while copying is on and the owner wants it (Settings → General).
    private func holdMacAwakeWhileCopying() {
        sleepGuard.hold(isCopying && launchPreferences.keepsMacAwake)
    }

    func setStartsCopying(_ starts: Bool) {
        guard starts != launchPreferences.startsCopying else { return }
        var chosen = launchPreferences
        chosen.startsCopying = starts
        saveLaunchPreferences(chosen)
    }

    @discardableResult
    private func saveLaunchPreferences(_ chosen: LaunchPreferences) -> Bool {
        do {
            try launchPreferencesStore?.save(chosen)
            launchPreferences = chosen
            holdMacAwakeWhileCopying()
            return true
        } catch {
            message = L10n.string("That setting could not be saved in the Keychain.")
            return false
        }
    }

    /// Paper accounts only: live accounts always wait for the owner to start copying.
    var canStartCopyingOnLaunch: Bool {
        guard let configuration = savedTradingConfiguration else { return false }
        return configuration.accounts.allSatisfy { $0.environment == .paper }
    }

    /// A launch start is due: the owner asked for one, an update or an engine restart left copying
    /// to resume, the setup is paper only, and the engine reports copying paused.
    private var wantsLaunchStart: Bool {
        wantsCopyingOnLaunch && !didStartCopyingOnLaunch && canStartCopyingOnLaunch && !setupAwaitsUpgrade
            && tradingStatus?.state == .paused
    }

    /// Starts copying once per launch when it is due, with the same checks as the toolbar button.
    /// It never waits for the window: Touch ID guards what the window shows and changes, and the
    /// owner already chose to copy this saved, paper-only setup, so a Mac nobody is at, or an app
    /// in the menu bar with its window closed, still copies.
    func startCopyingOnLaunchIfWanted() async {
        guard wantsLaunchStart else { return }
        didStartCopyingOnLaunch = true
        UserDefaults.standard.removeObject(forKey: Self.resumesAfterUpdateKey)
        resumesAfterEngineRestart = false
        await startTrading(resumingSavedSetup: true)
        retryLaunchStartWhileHeldBack()
    }

    /// A failed check right after launch is often the network still waking up, and the engine may
    /// still be reading the posts it missed; a paused app nobody is watching misses trades. The
    /// launch start tries again a few times, whether a check failed or the engine was slow to
    /// answer; a start the owner makes or a pause they choose ends the retries.
    private func retryLaunchStartWhileHeldBack() {
        guard isHeldBackAtLaunch else { return }
        launchStartRetry = Task { [weak self] in
            for delay in self?.launchStartRetryDelays ?? [] {
                try? await Task.sleep(for: delay)
                guard let self, !Task.isCancelled, self.isHeldBackAtLaunch else { return }
                await self.startTrading(resumingSavedSetup: true)
            }
        }
    }

    private var isHeldBackAtLaunch: Bool {
        wantsCopyingOnLaunch && tradingStatus?.state.isStopped == true
            && (tradingValidation?.report.activatable == false || launchStartThrew)
    }

    /// Why the checks before a start held it back: one failed check by name, with what happened
    /// and what to do; several by name, with each one's fix on its row in Connections.
    func failedChecksMessage(_ report: TradingCapabilityReport) -> String {
        let failed = report.checks.filter { $0.state == .failed }
        guard let only = failed.first else {
            return L10n.string("Copying didn't start because the setup check didn't pass. Connections shows what to fix.")
        }
        if failed.count == 1 {
            return L10n.string(
                "Copying didn't start. %@: %@", CapabilityCheckTitle.text(for: only),
                ConnectionProblem.text(for: only, modelName: setupDraft.modelName))
        }
        return L10n.string(
            "Copying didn't start. %@ need attention; each one's row in Connections says what to do.",
            L10n.list(failed.map(CapabilityCheckTitle.text(for:))))
    }

    func lockAccess() async {
        let applying = applyChangesTask
        applyChangesTask = nil
        applying?.cancel()
        await finishInterruptedApply(applying)
        isTradingUnlocked = false
        isUnlockingTrading = false
        accessMessage = nil
        assistant.isOpen = false
        // The assistant stops first, so a turn still running cannot propose after the discard.
        await assistant.reset()
        await discardAgentProposals()
        discardSetupWork()
        await lockApp()
    }

    /// Drops the current check. A "validated" banner never outlives the check it describes.
    func cancelTradingActivation(message newMessage: String? = nil) {
        tradingValidationTask?.cancel()
        tradingValidationTask = nil
        pendingTradingActivation = nil
        tradingValidation = nil
        checkedSetupSignature = nil
        isShowingSetupCheck = false
        if let newMessage {
            message = newMessage
        } else if message != nil && message == checkOutcomeMessage {
            message = nil
        }
        checkOutcomeMessage = nil
    }

    /// Locking or closing the window drops everything typed into the setup, secrets included;
    /// what was saved comes straight back so the screens never show an empty setup by mistake.
    private func discardSetupWork() {
        discardSetupChanges()
    }

    /// Checks the rules the engine also enforces, and names the first one a draft breaks.
    /// The model key to use: what was typed, or the saved one when the provider is the one it was
    /// saved for, so switching providers never sends one service's key to another.
    /// What checks a single connection: the test double, or the running engine.
    var connectionChecker: (any TradingStarting)? { tradingStarter ?? engineActions }

    /// What starts copying and confirms a start: the test double, or the running engine.
    var tradingControl: (any TradingStarting)? { tradingStarter ?? engineActions }

    /// The saved setup and its Keychain keys, which fill any key the owner left blank.
    func savedSetup() -> (configuration: TradingConfiguration, secrets: TradingSecrets)? {
        try? tradingConfigurationStore?.load()
    }

    static func providerKey(
        entered: String, for provider: TradingProviderName,
        saved: (configuration: TradingConfiguration, secrets: TradingSecrets)?
    ) -> String {
        guard entered.isEmpty else { return entered }
        guard let saved, saved.configuration.provider.name == provider else { return "" }
        return saved.secrets.providerAPIKey
    }

    private static func validateTradingConfiguration(
        _ configuration: TradingConfiguration
    ) throws {
        func fail(_ reason: String) -> TradingSettingsError { .invalidConfiguration(reason) }
        guard configuration.version == TradingConfiguration.currentVersion else {
            throw fail(L10n.string("This setup was saved by an older version. Set it up again."))
        }
        guard !configuration.source.channelIDs.isEmpty else {
            throw fail(L10n.string("Enter at least one Discord channel ID in Connections."))
        }
        guard !configuration.provider.model.isEmpty else { throw fail(L10n.string("Enter a model name under Interpreter in Connections.")) }
        if let problem = configuration.provider.baseURLProblem {
            throw fail(L10n.string("%@ Fix it under Interpreter in Connections.", problem))
        }
        guard !configuration.accounts.isEmpty else { throw fail(L10n.string("Add a broker account in Connections.")) }
        guard !configuration.routes.isEmpty, !configuration.profiles.isEmpty else {
            throw fail(L10n.string("Add a guru to copy in Connections."))
        }

        let accountIDs = configuration.accounts.map(\.id)
        for id in accountIDs where id.range(of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression) == nil {
            throw fail(L10n.string("The account name “%@” may only use letters, digits, “-” and “_”.", id))
        }
        guard Set(accountIDs).count == accountIDs.count else { throw fail(L10n.string("Each broker account needs a different name.")) }
        guard Set(configuration.profiles.map(\.profileRevision)).count == configuration.profiles.count,
            configuration.profiles.allSatisfy({ profile in
                let draft = TradingProfileDraft(
                    guruID: profile.guruID, displayName: profile.displayName,
                    playbook: profile.playbook
                )
                return (try? TradingProfileBuilder().build(draft)) == profile
            })
        else {
            throw fail("A guru's details don't line up. Open the guru in Connections and check its fields.")
        }

        let profiles = Dictionary(
            configuration.profiles.map { ($0.profileRevision, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var copiedInto: [String: String] = [:]
        for route in configuration.routes {
            let name = profiles[route.profileRevision]?.displayName ?? route.guruID
            guard !route.channelID.isEmpty else { throw fail(L10n.string("“%@” needs a Discord channel.", name)) }
            guard configuration.source.channelIDs.contains(route.channelID) else {
                throw fail(L10n.string("“%@” uses channel %@, which is not listed under Discord in Connections.", name, route.channelID))
            }
            guard route.source == "discord", route.guruID == profiles[route.profileRevision]?.guruID else {
                throw fail(L10n.string("“%@” doesn't match its saved details. Open the guru in Connections and check its fields.", name))
            }
            // One guru copies into one account, sized from its own full position (ADR-0010).
            guard let connection = route.connections.first else {
                throw fail(L10n.string("“%@” needs an account to copy into.", name))
            }
            guard let account = configuration.accounts.first(where: { $0.id == connection.accountID }) else {
                throw fail(L10n.string("“%@” copies into “%@”, which isn't one of your broker accounts.", name, connection.accountID))
            }
            guard let full = Decimal(string: connection.fullPositionUSD), full > 0 else {
                throw fail(
                    L10n.string(
                        "Set %@'s full position, or a max per stock for “%@”: a 1/6 call buys a sixth of it.", name,
                        account.id))
            }
            if let other = copiedInto[connection.accountID] {
                throw fail(L10n.string("“%@” already copies “%@”. Each account copies one guru.", connection.accountID, other))
            }
            copiedInto[connection.accountID] = name
        }
        // The channel names its guru (GuruIdentity), so a channel has one.
        var reading: [String: String] = [:]
        for route in configuration.routes {
            let name = profiles[route.profileRevision]?.displayName ?? route.guruID
            if let other = reading[route.channelID] {
                throw fail(
                    L10n.string(
                        "“%@” and “%@” both read channel %@. Each channel copies one guru: remove one of them, or give it its own channel.",
                        other, name, route.channelID))
            }
            reading[route.channelID] = name
        }
    }

    func refreshPendingSelfTest() async {
        guard let engineActions, let commandJournal else { return }
        for entry in selfTestEntries where entry.isPending {
            do {
                let workflow = try await engineActions.workflow(id: entry.id)
                try await commandJournal.record(workflow)
                selfTestEntries = try await commandJournal.entries()
                latestSelfTest = workflow
            } catch EngineContractError.remote(code: .notFound, message: _, reason: _) {
                message = L10n.string("Command %@ has no engine workflow yet. Retry the saved self-test from System.", entry.id)
            } catch {
                message = L10n.string(
                    "Command %@ has an uncertain response. Look it up or retry the same ID after the engine reconnects.", entry.id)
            }
        }
    }

    func retryPendingSelfTest() async {
        guard let id = pendingCommandID,
            let command = selfTestEntries.first(where: { $0.id == id })?.command,
            let engineActions, let commandJournal
        else { return }
        guard !isRunningSelfTest else { return }
        isRunningSelfTest = true
        defer { isRunningSelfTest = false }
        do {
            let workflow: WorkflowView
            do {
                workflow = try await engineActions.workflow(id: id)
            } catch EngineContractError.remote(code: .notFound, message: _, reason: _) {
                workflow = try await engineActions.submitSelfTest(command)
            }
            try await commandJournal.record(workflow)
            selfTestEntries = try await commandJournal.entries()
            latestSelfTest = selfTestEntries.first(where: { $0.id == id })?.workflow
            message = nil
        } catch {
            message = Self.userMessage(for: error)
        }
    }

    private func submit(_ command: SelfTestCommand) async throws {
        guard let engineActions, let commandJournal else { throw CommandJournalError.unavailable }
        let workflow = try await engineActions.submitSelfTest(command)
        try await commandJournal.record(workflow)
        selfTestEntries = try await commandJournal.entries()
        latestSelfTest = workflow
    }

    func lockApp() async {
        accessGeneration += 1
        isTradingUnlocked = false
        isUnlockingTrading = false
        accessMessage = nil
        await appUnlock.lock()
        message = nil
    }

    private func observe(_ currentSupervisor: ProcessSupervisor) {
        eventTask?.cancel()
        let events = currentSupervisor.events
        eventTask = Task { [weak self] in
            for await event in events {
                guard let self, !Task.isCancelled else { return }
                guard self.supervisor === currentSupervisor else { return }
                self.handle(event)
            }
        }
    }

    func handle(_ event: RuntimeEvent) {
        switch event {
        case .starting:
            runtimeState = .starting
        case .ready:
            if engineActions != nil {
                startStatusPolling()
            }
        case .stopped:
            runtimeState = .stopped
        case .childExited(let child, _, let restarting):
            #if DEBUG
                if child == .engine, let supervisor {
                    Task {
                        let tail = await supervisor.stderrTail(for: .engine)
                        FileHandle.standardError.write(Data("engine exited; stderr:\n\(tail)\n".utf8))
                    }
                }
            #endif
            if child == .engine {
                // A crash is not the owner pausing: copying that was running starts again once
                // the restarted engine reports, with the same checks as Start Copying.
                if restarting, [.running, .degraded].contains(tradingStatus?.state) {
                    resumesAfterEngineRestart = true
                    didStartCopyingOnLaunch = false
                }
                engineGeneration.advance()
                statusTask?.cancel()
                statusTask = nil
                engineStatus = nil
                tradingStatus = nil
                // The engine forgot every conversation and proposal; the app must not show them.
                agentProposals = []
                Task { [weak self] in await self?.assistant.reset() }
            }
            runtimeState = .degraded
            message =
                !restarting
                ? L10n.string("The engine stopped unexpectedly.")
                : resumesAfterEngineRestart && canStartCopyingOnLaunch
                    ? L10n.string("The engine stopped and is restarting. Copying starts again when it's back.")
                    : L10n.string("The engine stopped and is restarting.")
        case .degraded(let code):
            runtimeState = .degraded
            switch code {
            case "restart_limit_reached":
                message = L10n.string("A local service reached its restart limit.")
            default:
                message = L10n.string("A local service is degraded.")
            }
        }
    }

    private func startStatusPolling() {
        statusTask?.cancel()
        statusTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refreshStatus()
                do {
                    try await Task.sleep(for: .seconds(2))
                } catch {
                    return
                }
            }
        }
    }

    static func userMessage(for error: any Error) -> String {
        if case TradingSettingsError.missingCredentials(let what) = error {
            return L10n.string("Enter %@ first.", what)
        }
        if let error = error as? LocalizedError, let description = error.errorDescription {
            return L10n.string(description)
        }
        // A file or network error from macOS already reads in the Mac's own words.
        let system = error as NSError
        if [NSCocoaErrorDomain, NSPOSIXErrorDomain, NSURLErrorDomain].contains(system.domain) {
            return system.localizedDescription
        }
        return L10n.string("CopyTrading could not complete that local operation.")
    }
}
