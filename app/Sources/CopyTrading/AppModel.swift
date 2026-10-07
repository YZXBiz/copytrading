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

    func evaluateHistoricalProfile(
        _ evaluation: HistoricalProfileEvaluationRequest
    ) async throws -> ProfileEvaluation

    func reviewProfileExamples(
        _ request: ProfileExampleReviewRequest
    ) async throws -> ProfileExampleReview

    func learnGuruPlaybook(
        _ learning: GuruPlaybookLearningRequest
    ) async throws -> LearnedGuruPlaybook

    func replayGuruPosts(_ replay: GuruReplayRequest) async throws -> GuruReplay
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

    enum Screen: String, CaseIterable, Hashable, Identifiable {
        case today
        case activity
        case people
        case accounts
        case connections
        case gettingStarted
        case diagnostics
        case settings

        var id: String { rawValue }

        var title: String {
            switch self {
            case .today: "Today"
            case .activity: "Activity"
            case .people: "People"
            case .accounts: "Accounts"
            case .connections: "Connections"
            case .gettingStarted: "Getting Started"
            case .diagnostics: "Diagnostics"
            case .settings: "Settings"
            }
        }

        var symbol: String {
            switch self {
            case .today: "sun.max"
            case .activity: "list.bullet.rectangle"
            case .people: "person.2"
            case .accounts: "building.columns"
            case .connections: "cloud"
            case .gettingStarted: "hand.wave"
            case .diagnostics: "waveform.path.ecg"
            case .settings: "gearshape"
            }
        }
    }

    var selectedScreen: Screen = .today
    /// The Settings page on show and the pages visited before it, newest last.
    var settingsPage: SettingsPage = .general
    var settingsTrail: [SettingsPage] = []
    /// Where closing Settings returns to.
    var screenBeforeSettings: Screen = .today
    var runtimeState: RuntimeState = .stopped {
        didSet { holdMacAwakeWhileCopying() }
    }
    var engineStatus: EngineStatus?
    var tradingStatus: TradingStatus? {
        didSet { holdMacAwakeWhileCopying() }
    }
    var savedTradingConfiguration: TradingConfiguration?
    var hasTradingSecrets = false
    var tradingValidation: TradingValidation?
    var profileExampleReviews: [String: ProfileExampleReview] = [:]
    var profileExamplesAcknowledged = false
    var isValidatingTrading = false
    var isActivatingTrading = false
    var isTradingCommandPending = false
    var isTradingUnlocked = false
    var agentAccess: AgentAccessSetting = .off
    var isAgentRelayListening = false
    var isChangingAgentAccess = false
    var agentProposals: [AgentProposal] = []
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
                L10n.string("Restored. Each account stays off, with manual recovery, until you turn it back on."))
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
    @ObservationIgnored private var tradingConfigurationStore: TradingConfigurationStore?
    /// The unsaved setup, edited from Connections, People, and Accounts. It lives here, not in a
    /// screen, so switching screens keeps what was typed; locking or closing the window drops it,
    /// secrets included.
    var setupDraft = ConnectionsDraft()
    /// The saved configuration `setupDraft` was last filled from, so refilling the draft never
    /// overwrites pending edits with the saved copy.
    var setupDraftSource: TradingConfiguration?
    /// The account or guru being edited, shown as one sheet over whichever screen asked for it.
    var setupEditor: ConnectionsEditingTarget?
    /// A connection the guide asked to open; Connections opens its panel and clears it.
    var requestedConnection: ConnectionKind?
    /// A guru an assistant link asked to open; People opens their sheet and clears it.
    var requestedGuruID: String?
    /// The guru whose sheet is open on People, so the assistant knows who "this guru" is.
    var openGuruID: String?
    /// An account an assistant link asked to show; Accounts scrolls to it and clears it.
    var requestedAccountID: String?
    /// The draft as it stood when the current check began; Start Copying needs it unchanged.
    var checkedSetupSignature: SetupDraftSignature?
    /// Each connection's latest check, kept only while what it checked stays as typed.
    var connectionChecks: [ConnectionCheckSubject: ConnectionCheckResult] = [:]
    var isShowingSetupCheck = false
    /// When copying last started from a new setup. Today says so until the first post after it.
    var copyingStartedAt: Date?
    /// A Getting Started section asked for from the Help menu; the guide clears it.
    var guideAnchor: GuideAnchor?
    /// Bumped by Help ▸ Show Tips Again, so every tip gets a fresh identity and can show again.
    var tipGeneration = UserDefaults.standard.integer(forKey: AppModel.tipGenerationKey)
    @ObservationIgnored private var pendingTradingActivation: PendingTradingActivation?
    /// The banner the last check left, so discarding that check takes its banner with it.
    @ObservationIgnored private var checkOutcomeMessage: String?
    @ObservationIgnored private var hasChosenFirstScreen = false

    /// The exact configuration the current check covers; Start Copying saves this one.
    var validatedConfiguration: TradingConfiguration? { pendingTradingActivation?.configuration }

    @ObservationIgnored private var tradingValidationTask: Task<Void, Never>?
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
    @ObservationIgnored private var didStartCopyingOnLaunch = false
    /// How long the launch start waits before each retry after a failed connection check.
    @ObservationIgnored var launchStartRetryDelays: [Duration] = [.seconds(10), .seconds(30), .seconds(60)]
    @ObservationIgnored private var launchStartRetry: Task<Void, Never>?
    private(set) var launchPreferences: LaunchPreferences
    @ObservationIgnored private let sleepGuard: SleepGuard

    private struct PendingTradingActivation: Sendable {
        let configuration: TradingConfiguration
        /// The engine's revision of `configuration`; the app never computes its own.
        let revision: String
        let secrets: TradingSecrets
        let validationToken: String
    }

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
        agentProposalOperations: (any AgentProposalOperations)? = nil,
        sleepGuard: SleepGuard = SleepGuard()
    ) {
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
            if try configurationStore.discardOlderVersion() {
                message =
                    L10n.string(
                        "Your setup was saved by an older version of CopyTrading. Set it up again from Getting Started, including your keys."
                    )
            }
            let savedTrading = try configurationStore.load()
            savedTradingConfiguration = savedTrading?.configuration
            hasTradingSecrets = savedTrading != nil
            syncSetupDraftWithSaved()
            // A first launch opens on the guide; an engine restart later never moves the owner.
            if !hasChosenFirstScreen {
                hasChosenFirstScreen = true
                if savedTrading == nil && selectedScreen == .today {
                    selectedScreen = .gettingStarted
                }
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

    static func stopMessage(for report: ProcessSupervisorStopReport) -> String {
        let acknowledgement: String
        switch report.engineDrainAcknowledgement {
        case .acknowledged:
            acknowledgement = L10n.string("The engine acknowledged its graceful drain.")
        case .unconfirmed:
            acknowledgement = L10n.string("The engine did not confirm its graceful drain; owned local processes were stopped.")
        case .noLiveEngine:
            acknowledgement = L10n.string("No live engine session was available to confirm a drain.")
        }
        let forcedChildren = report.forciblyStoppedChildren.map(\.rawValue)
        var sentences = [acknowledgement]
        if !forcedChildren.isEmpty {
            sentences.append(L10n.string("Forced termination was required for: %@.", Humanize.joined(forcedChildren)))
        }
        sentences.append(L10n.string("Broker-accepted orders may remain open."))
        return sentences.dropFirst().reduce(acknowledgement) { L10n.string("%@ %@", $0, $1) }
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
            diagnosticsSettingsWarning = error.localizedDescription
        }
    }

    /// Re-reads the journal from disk; it works whether or not the engine is running.
    func reloadDiagnostics() async {
        guard !isLoadingDiagnostics else { return }
        isLoadingDiagnostics = true
        defer { isLoadingDiagnostics = false }
        let journal = diagnosticsJournal
        do {
            let (entries, bytes) = try await Task.detached(priority: .userInitiated) {
                (try journal.entries(), journal.usageBytes())
            }.value
            diagnosticsEntries = entries
            diagnosticsJournalBytes = bytes
            diagnosticsJournalMessage = nil
        } catch {
            diagnosticsJournalMessage = error.localizedDescription
        }
    }

    /// The journal itself, already redacted by the engine, for a support file the owner saves.
    func diagnosticsExportText() throws -> String {
        try diagnosticsJournal.exportText()
    }

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
        } catch EngineContractError.remote(code: _, message: let message?) {
            throw TradingSettingsError.invalidConfiguration(message)
        } catch is EngineContractError {
            throw TradingSettingsError.invalidConfiguration(L10n.string("The engine could not learn from this channel. Try again."))
        }
    }

    /// Reads the guru's recent posts with this draft's playbook and rules and says what each would
    /// have done (ADR-0007). Nothing is placed or saved.
    func replayPosts(for route: TradingRouteDraft, in draft: ConnectionsDraft) async throws -> GuruReplay {
        let reading = try channelReading(
            for: route, in: draft, locked: L10n.string("Unlock CopyTrading before replaying posts."),
            stopped: L10n.string("The engine isn't running. Start it in Settings → Engine. If another CopyTrading is open, quit it first."))
        let profile = try TradingProfileBuilder().build(
            TradingProfileDraft(
                guruID: route.guruID.trimmed,
                displayName: route.displayName.trimmed.isEmpty ? route.guruID.trimmed : route.displayName.trimmed,
                playbook: route.playbook.trimmedLines,
                examples: []
            ))
        do {
            return try await reading.engine.replayGuruPosts(
                GuruReplayRequest(
                    channelID: reading.channelID,
                    authorID: route.authorID.trimmed.nilIfEmpty,
                    discordToken: reading.discordToken,
                    provider: draft.providerConfiguration,
                    providerAPIKey: reading.providerAPIKey,
                    profile: profile
                ))
        } catch EngineContractError.remote(code: _, message: let message?) {
            throw TradingSettingsError.invalidConfiguration(message)
        } catch is EngineContractError {
            throw TradingSettingsError.invalidConfiguration(L10n.string("The engine could not replay this channel. Try again."))
        }
    }

    func validateTradingSettings(
        _ configuration: TradingConfiguration, enteredSecrets: TradingSecrets
    ) async {
        defer { checkOutcomeMessage = message }
        guard !isRunningBackupRestore else {
            message = L10n.string("Wait for the backup or restore to finish, then check the setup.")
            return
        }
        guard isTradingUnlocked else {
            message = L10n.string("Unlock CopyTrading first.")
            return
        }
        guard let tradingConfigurationStore else {
            message = L10n.string("CopyTrading is still starting. Check the setup again in a moment.")
            return
        }
        guard tradingStatus?.state == .paused, !isTradingCommandPending else {
            message = L10n.string("Pause copying before checking the setup.")
            return
        }
        guard let validator: (any TradingStarting) = tradingStarter ?? engineActions else {
            message = L10n.string("CopyTrading is still starting. Check the setup again in a moment.")
            return
        }
        guard !isValidatingTrading, !isActivatingTrading else { return }
        isValidatingTrading = true
        tradingValidation = nil
        profileExampleReviews = [:]
        profileExamplesAcknowledged = false
        pendingTradingActivation = nil
        isShowingSetupCheck = false
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
            let profilesByRevision = Dictionary(
                configuration.profiles.map { ($0.profileRevision, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            var reviews: [String: ProfileExampleReview] = [:]
            for route in configuration.routes {
                guard let profile = profilesByRevision[route.profileRevision] else {
                    throw TradingSettingsError.invalidConfiguration(
                        L10n.string(
                            "The guru reading channel %@ has no saved details. Open them in Connections and check their fields.",
                            route.channelID
                        ))
                }
                guard !profile.examples.isEmpty else { continue }
                let request = ProfileExampleReviewRequest(
                    profile: profile,
                    provider: configuration.provider,
                    providerAPIKey: secrets.providerAPIKey,
                    destinations: route.connections
                )
                let review = try await validator.reviewProfileExamples(request)
                guard !Task.isCancelled else { throw CancellationError() }
                try Self.validateProfileExampleReview(
                    review, profile: profile, provider: configuration.provider,
                    destinations: route.connections
                )
                reviews[route.id] = review
            }
            profileExampleReviews = reviews
            guard !reviews.values.contains(where: { !$0.automaticActivationAllowed }) else {
                message = L10n.string(
                    "An example was read differently from what you expected. Fix the playbook or the example, then check again.")
                isShowingSetupCheck = true
                return
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
                return
            }
            pendingTradingActivation = PendingTradingActivation(
                configuration: configuration,
                revision: validation.report.configurationRevision,
                secrets: secrets,
                validationToken: activationToken
            )
            // The changes bar says the check passed; the readings still need a look when present.
            message = nil
            isShowingSetupCheck = !reviews.isEmpty
        } catch {
            if error is CancellationError {
                tradingValidation = nil
                message = L10n.string("Check cancelled. Nothing was saved.")
            } else {
                message = Self.userMessage(for: error)
            }
        }
    }

    /// Checks the setup; with `thenStart`, starts copying straight after when everything passed
    /// and there is nothing to look over, and otherwise shows what needs the owner.
    func beginTradingValidation(
        _ configuration: TradingConfiguration, enteredSecrets: TradingSecrets, thenStart: Bool = false
    ) {
        tradingValidationTask?.cancel()
        tradingValidationTask = Task { [weak self] in
            await self?.validateTradingSettings(configuration, enteredSecrets: enteredSecrets)
            guard thenStart, !Task.isCancelled, let self else { return }
            if self.canStartCopyingFromCheck {
                await self.activateValidatedTradingSettings()
            } else if self.tradingValidation != nil || !self.profileExampleReviews.isEmpty {
                self.isShowingSetupCheck = true
            }
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
        guard profileExampleReviews.values.allSatisfy(\.automaticActivationAllowed) else {
            message = L10n.string("Fix the examples that were read differently, then check again.")
            return
        }
        guard profileExampleReviews.isEmpty || profileExamplesAcknowledged else {
            message = L10n.string("Look over how the examples were read before starting to copy.")
            return
        }
        guard tradingStatus?.state == .paused, !isTradingCommandPending,
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
        else { return }
        do {
            let status = try await control.tradingActivation(activationID: pending.activationID)
            if let current = try? await control.tradingStatus() {
                tradingStatus = current
            }
            let activationCommitted =
                status.activationID == pending.activationID
                && status.candidateRevision == pending.candidateRevision
                && status.committedRevision == pending.candidateRevision
                && status.committedActivationID == pending.activationID
            if activationCommitted && (status.phase == .ready || status.phase == .stopped) {
                try tradingConfigurationStore.finalizeValidatedActivation(
                    activationID: pending.activationID
                )
                let saved = try tradingConfigurationStore.load()
                savedTradingConfiguration = saved?.configuration
                hasTradingSecrets = saved != nil
                pendingTradingActivation = nil
                tradingValidation = nil
                syncSetupDraftWithSaved()
                didStartCopyingNewSetup()
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
                let saved = try tradingConfigurationStore.load()
                savedTradingConfiguration = saved?.configuration
                hasTradingSecrets = saved != nil
                pendingTradingActivation = nil
                tradingValidation = nil
                syncSetupDraftWithSaved()
                message = L10n.string("The new setup didn't start, so your previous setup is still in place.")
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
            message = L10n.string("Configuration activation is pending; engine status is unavailable. Credentials are retained.")
        }
    }

    func startTrading() async {
        guard !isRunningBackupRestore else {
            message = L10n.string("Wait for the backup or restore preview to finish before starting processing.")
            return
        }
        guard isTradingUnlocked else {
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
        do {
            if try tradingConfigurationStore.pendingActivation() != nil {
                await reconcilePendingTradingActivation(using: starter)
                return
            }
            guard let saved = try tradingConfigurationStore.load() else {
                throw TradingSettingsError.missingCredentials("the saved credentials in Connections")
            }
            guard await confirmLiveStart(saved.configuration) else { return }
            let validation = try await starter.validateTrading(
                configuration: saved.configuration, secrets: saved.secrets
            )
            tradingValidation = validation
            guard validation.report.activatable, let token = validation.activationToken else {
                message = Self.failedChecksMessage(validation.report)
                return
            }
            let activationID = UUID().uuidString.lowercased()
            try tradingConfigurationStore.stageSavedResume(
                activationID: activationID, when: .paused
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
            message = Self.userMessage(for: error)
        }
    }

    func pauseTrading() async {
        launchStartRetry?.cancel()
        guard let engineActions else { return }
        guard !isTradingCommandPending else { return }
        isTradingCommandPending = true
        defer { isTradingCommandPending = false }
        do {
            tradingStatus = try await engineActions.pauseTrading()
            message = nil
        } catch {
            message = Self.userMessage(for: error)
        }
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
        windowSessionID = nil
        accessGeneration += 1
        isTradingUnlocked = false
        isUnlockingTrading = false
        accessMessage = nil
        assistant.isOpen = false
        discardSetupWork()
        return Task { [weak self] in
            guard let self else { return }
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

    /// Starts copying once per launch when the owner asked for it, the setup is paper only,
    /// and the engine reports copying paused. Start runs the same checks as the toolbar button.
    func startCopyingOnLaunchIfWanted() async {
        guard launchPreferences.startsCopying, !didStartCopyingOnLaunch, isTradingUnlocked,
            canStartCopyingOnLaunch, tradingStatus?.state == .paused
        else { return }
        didStartCopyingOnLaunch = true
        await startTrading()
        retryLaunchStartWhileHeldBack()
    }

    /// A failed check right after launch is often the network still waking up, and a paused app
    /// nobody is watching misses trades. The launch start tries again a few times; a start the
    /// owner makes or a pause they choose ends the retries.
    private func retryLaunchStartWhileHeldBack() {
        guard isHeldBackAtLaunch else { return }
        launchStartRetry = Task { [weak self] in
            for delay in self?.launchStartRetryDelays ?? [] {
                try? await Task.sleep(for: delay)
                guard let self, !Task.isCancelled, self.isHeldBackAtLaunch else { return }
                await self.startTrading()
            }
        }
    }

    private var isHeldBackAtLaunch: Bool {
        launchPreferences.startsCopying && isTradingUnlocked && tradingStatus?.state == .paused
            && tradingValidation?.report.activatable == false
    }

    static func failedChecksMessage(_ report: TradingCapabilityReport) -> String {
        let failed = report.checks.filter { $0.state == .failed }.map(\.title)
        guard !failed.isEmpty else { return L10n.string("A required connection check failed. Processing remains paused.") }
        let names = L10n.list(failed)
        return L10n.string(
            failed.count == 1
                ? "%@ failed its connection check. Processing remains paused."
                : "%@ failed their connection check. Processing remains paused.",
            names
        )
    }

    func lockAccess() async {
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
        profileExampleReviews = [:]
        profileExamplesAcknowledged = false
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

    var canAcknowledgeProfileExamples: Bool {
        !profileExampleReviews.isEmpty
            && profileExampleReviews.values.allSatisfy(\.automaticActivationAllowed)
    }

    func acknowledgeProfileExamples() {
        guard canAcknowledgeProfileExamples else {
            profileExamplesAcknowledged = false
            return
        }
        profileExamplesAcknowledged = true
    }

    /// Checks the rules the engine also enforces, and names the first one a draft breaks.
    /// The model key to use: what was typed, or the saved one when the provider is the one it was
    /// saved for, so switching providers never sends one service's key to another.
    /// What checks a single connection: the test double, or the running engine.
    var connectionChecker: (any TradingStarting)? { tradingStarter ?? engineActions }

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
                    playbook: profile.playbook, examples: profile.examples
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
            // One guru copies into one account, sized from that account's maximum per stock.
            guard let connection = route.connections.first else {
                throw fail(L10n.string("“%@” needs an account to copy into.", name))
            }
            guard let account = configuration.accounts.first(where: { $0.id == connection.accountID }) else {
                throw fail(L10n.string("“%@” copies into “%@”, which isn't one of your broker accounts.", name, connection.accountID))
            }
            guard let full = Decimal(string: account.policy.maxSymbolUSD), full > 0,
                connection.fullPositionUSD == account.policy.maxSymbolUSD
            else {
                throw fail(L10n.string("Set a max per stock for “%@”. It's %@'s full position.", account.id, name))
            }
            if let other = copiedInto[connection.accountID] {
                throw fail(L10n.string("“%@” already copies “%@”. Each account copies one guru.", connection.accountID, other))
            }
            copiedInto[connection.accountID] = name
        }
        let identityRules = configuration.routes.map { "\($0.source):\($0.channelID):\($0.authorID ?? "*")" }
        guard Set(identityRules).count == identityRules.count else {
            throw fail(L10n.string("Two gurus read the same channel and author. Give each guru a different author ID in Connections."))
        }
        let sharedChannels = Dictionary(grouping: configuration.routes, by: { "\($0.source):\($0.channelID)" })
        guard sharedChannels.values.allSatisfy({ routes in routes.count == 1 || routes.allSatisfy { $0.authorID != nil } }) else {
            throw fail(L10n.string("Routes that share a channel each need an author ID."))
        }
    }

    /// Models write 1/6 as 0.16666666666666666; the engine treats that as the stated sixth.
    private static let fractionTolerance = Decimal(sign: .plus, exponent: -9, significand: 1)

    private static func validateProfileExampleReview(
        _ review: ProfileExampleReview,
        profile: TradingProfileRevision,
        provider: TradingProviderConfiguration,
        destinations: [TradingRouteConnection]
    ) throws {
        guard review.simulated, review.noOrder,
            review.guruID == profile.guruID,
            review.profileRevision == profile.profileRevision,
            review.provider == provider.name.rawValue,
            review.model == provider.model,
            review.examples.count == profile.examples.count
        else {
            throw TradingSettingsError.invalidEvaluationResult
        }
        var allMatch = true
        for (index, pair) in zip(profile.examples, review.examples).enumerated() {
            let (expected, actual) = pair
            guard actual.exampleIndex == index,
                actual.expectedAction == expected.expectedAction,
                actual.expectedSymbol == expected.expectedSymbol,
                actual.expectedFraction == expected.expectedFraction,
                actual.actual.simulated, actual.actual.noOrder,
                actual.actual.guruID == profile.guruID,
                actual.actual.profileRevision == profile.profileRevision,
                actual.actual.provider == provider.name.rawValue,
                actual.actual.model == provider.model
            else {
                throw TradingSettingsError.invalidEvaluationResult
            }
            let instruction =
                actual.actual.instructions.count == 1
                ? actual.actual.instructions[0] : nil
            let expectedFraction = expected.expectedFraction.flatMap { Decimal(string: $0) }
            let actualFraction = instruction?.fraction.flatMap { Decimal(string: $0) }
            // Same rule as the engine: both absent, or equal within 1e-9.
            let fractionMatches =
                switch (expectedFraction, actualFraction) {
                case (nil, nil): true
                case let (expected?, actual?): abs(expected - actual) <= Self.fractionTolerance
                default: false
                }
            // Same rules as the engine: a stated price must match, and a sell's buy price must
            // match what the example names (none means every buy).
            let priceMatches =
                expected.expectedPrice.flatMap { Decimal(string: $0) }.map { expectedPrice in
                    instruction.flatMap { Decimal(string: $0.price) } == expectedPrice
                } ?? true
            let checksBuyPrice = expected.expectedBuyPrice != nil || expected.expectedAction != .buy
            let buyPriceMatches =
                !checksBuyPrice
                || instruction?.entryPrice.flatMap { Decimal(string: $0) }
                    == expected.expectedBuyPrice.flatMap { Decimal(string: $0) }
            let matches =
                actual.actual.decision == "trade"
                && instruction?.action == expected.expectedAction
                && instruction?.symbol == expected.expectedSymbol
                && fractionMatches
                && priceMatches
                && buyPriceMatches
            guard actual.matches == matches else {
                throw TradingSettingsError.invalidEvaluationResult
            }
            let destinationIDs = Set(actual.actual.destinations.map(\.accountID))
            let expectedDestinationIDs = Set(destinations.map(\.accountID))
            guard destinationIDs == expectedDestinationIDs,
                actual.actual.destinations.allSatisfy({ destination in
                    destinations.contains { $0.accountID == destination.accountID }
                })
            else {
                throw TradingSettingsError.invalidEvaluationResult
            }
            allMatch = allMatch && matches
        }
        guard review.automaticActivationAllowed == allMatch else {
            throw TradingSettingsError.invalidEvaluationResult
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
            } catch EngineContractError.remote(code: .notFound, message: _) {
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
            } catch EngineContractError.remote(code: .notFound, message: _) {
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
            message = restarting ? L10n.string("The engine stopped and is restarting.") : L10n.string("The engine stopped unexpectedly.")
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
        return L10n.string("CopyTrading could not complete that local operation.")
    }
}
