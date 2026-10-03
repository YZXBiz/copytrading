import Foundation
import Testing

/// The DesktopCore checks, run one at a time in this order: several start real processes or
/// share temporary state, so they never overlap. `swift test --filter` picks one by name.
enum DesktopCoreCheck: String, CaseIterable, Sendable, CustomTestStringConvertible {
    case tradingSecretRevisionDeletion = "trading secret revision deletion"
    case protocolFixtures = "protocol fixtures"
    case tradingContracts = "trading contracts"
    case tradingProviderContracts = "trading provider contracts"
    case assistantContracts = "assistant contracts"
    case runtimePaths = "runtime paths"
    case equityCurve = "equity curve"
    case operationalGenerationOwnership = "operational generation ownership"
    case operationalSchemaLookup = "operational schema lookup"
    case diagnosticsSettingsAndJournal = "diagnostics settings and journal"
    case runtimeManifest = "runtime manifest"
    case processSupervisor = "process supervisor"
    case startupOwnershipRestoreReservation = "startup ownership restore reservation"
    case restoreActivationCoordinator = "restore activation coordinator"
    case engineClientCatPipe = "engine client cat pipe"
    case engineClientProcessIPC = "engine client process IPC"
    case agentRelaySocket = "agent relay socket"
    case agentAccessAndApprovals = "agent access and approvals"
    case nativeBackupAndRestoreActions = "native backup and restore actions"
    case userControlledUpdateService = "user controlled update service"
    case engineActionsAfterRestart = "engine actions after restart"
    case appStartupIntent = "app startup intent"
    case appUnlockSession = "app unlock session"
    case windowSessionLifecycle = "window session lifecycle"
    case runtimeGeneration = "runtime generation"
    case shutdownCoordination = "shutdown coordination"
    case durableCommandJournal = "durable command journal"
    case unwritableLogAndCommandRecovery = "unwritable log and command recovery"

    var testDescription: String { rawValue }

    /// On the main actor, as the executable's `main` ran every check.
    @MainActor func run() async throws {
        switch self {
        case .tradingSecretRevisionDeletion: try runTradingSecretRevisionDeletionTests()
        case .protocolFixtures: try runProtocolFixtureTests()
        case .tradingContracts: try runTradingContractTests()
        case .tradingProviderContracts: try runTradingProviderContractTests()
        case .assistantContracts: try runAssistantContractTests()
        case .runtimePaths: try runRuntimePathsTests()
        case .equityCurve: try runEquityCurveTests()
        case .operationalGenerationOwnership: try runOperationalGenerationTests()
        case .operationalSchemaLookup: try runOperationalSchemaTests()
        case .diagnosticsSettingsAndJournal: try runDiagnosticsJournalTests()
        case .runtimeManifest: try runRuntimeManifestTests()
        case .processSupervisor: try await runProcessSupervisorTests()
        case .startupOwnershipRestoreReservation: try await runStartupOwnershipPreparationReservationTest()
        case .restoreActivationCoordinator: try await runRestoreActivationCoordinatorTests()
        case .engineClientCatPipe: try await runEngineClientCatPipeTests()
        case .engineClientProcessIPC: try await runEngineClientProcessTests()
        case .agentRelaySocket: try await runAgentRelayTests()
        case .agentAccessAndApprovals: try await runAgentAccessTests()
        case .nativeBackupAndRestoreActions: try await runEngineActionsBackupRestoreTests()
        case .userControlledUpdateService: try await runUpdateServiceTests()
        case .engineActionsAfterRestart: try await runEngineActionsRestartTests()
        case .appStartupIntent: try runAppStartupIntentTests()
        case .appUnlockSession: try await runAppUnlockSessionTests()
        case .windowSessionLifecycle: try runWindowSessionLifecycleTests()
        case .runtimeGeneration: try runRuntimeGenerationTests()
        case .shutdownCoordination: try await runShutdownCoordinatorTests()
        case .durableCommandJournal: try await runCommandJournalTests()
        case .unwritableLogAndCommandRecovery: try await runUnwritableLogCommandRecoveryTest()
        }
    }
}

@Test(.serialized, arguments: DesktopCoreCheck.allCases)
@MainActor func desktopCore(_ check: DesktopCoreCheck) async throws {
    try await check.run()
}

/// Its own test so `make desktop-smoke` can run it alone against a relocated app:
/// `swift test --filter managedNativeRuntime`.
@Test @MainActor func managedNativeRuntime() async throws {
    try await runManagedRuntimeTests()
}

/// Starts the real engine and drives the `copytrading` CLI through the app's relay. On GitHub's
/// macOS runners the CLI cannot reach the relay (it reports the app as not running), though it
/// passes on a Mac; it is skipped there until that is understood (https://github.com/YZXBiz/copytrading/issues/19).
@Test(
    .disabled(
        if: ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true",
        "fails only on GitHub's runners: https://github.com/YZXBiz/copytrading/issues/19"))
@MainActor func agentControlWithTheEngine() async throws {
    try await runAgentControlEngineTests()
}
