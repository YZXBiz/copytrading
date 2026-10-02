import Foundation

@main
enum DesktopCoreTestRunner {
    static func main() async throws {
        let checks: [(String, () async throws -> Void)] = [
            ("trading secret revision deletion", { try runTradingSecretRevisionDeletionTests() }),
            ("protocol fixtures", { try runProtocolFixtureTests() }),
            ("trading contracts", { try runTradingContractTests() }),
            ("trading provider contracts", { try runTradingProviderContractTests() }),
            ("assistant contracts", { try runAssistantContractTests() }),
            ("runtime paths", { try runRuntimePathsTests() }),
            ("equity curve", { try runEquityCurveTests() }),
            ("operational generation ownership", { try runOperationalGenerationTests() }),
            ("operational schema lookup", { try runOperationalSchemaTests() }),
            ("diagnostics settings and journal", { try runDiagnosticsJournalTests() }),
            ("runtime manifest", { try runRuntimeManifestTests() }),
            ("process supervisor", { try await runProcessSupervisorTests() }),
            ("startup ownership restore reservation", { try await runStartupOwnershipPreparationReservationTest() }),
            ("restore activation coordinator", { try await runRestoreActivationCoordinatorTests() }),
            ("engine client cat pipe", { try await runEngineClientCatPipeTests() }),
            ("engine client process IPC", { try await runEngineClientProcessTests() }),
            ("agent relay socket", { try await runAgentRelayTests() }),
            ("agent access and approvals", { try await runAgentAccessTests() }),
            ("agent control with the engine", { try await runAgentControlEngineTests() }),
            ("native backup and restore actions", { try await runEngineActionsBackupRestoreTests() }),
            ("user controlled update service", { try await runUpdateServiceTests() }),
            ("engine actions after restart", { try await runEngineActionsRestartTests() }),
            ("app startup intent", { try runAppStartupIntentTests() }),
            ("app unlock session", { try await runAppUnlockSessionTests() }),
            ("window session lifecycle", { try runWindowSessionLifecycleTests() }),
            ("runtime generation", { try runRuntimeGenerationTests() }),
            ("shutdown coordination", { try await runShutdownCoordinatorTests() }),
            ("durable command journal", { try await runCommandJournalTests() }),
            ("managed native runtime", { try await runManagedRuntimeTests() }),
            ("unwritable log and command recovery", { try await runUnwritableLogCommandRecoveryTest() }),
        ]
        let selected = ProcessInfo.processInfo.environment["COPYTRADING_TEST_ONLY"]
        for (name, check) in checks where selected == nil || selected == name {
            do {
                FileHandle.standardError.write(Data("RUN \(name)\n".utf8))
                try await check()
                print("PASS \(name)")
            } catch {
                let line = "FAIL \(name): \(error)\n"
                FileHandle.standardError.write(Data(line.utf8))
                throw error
            }
        }
    }
}
