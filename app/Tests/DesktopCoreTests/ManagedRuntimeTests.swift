import DesktopCore
import Foundation
import Testing

private struct ManagedRuntime {
    let state: URL
    let paths: RuntimePaths
    let python: URL
    let libraryPath: String

    init?() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let runtimePath = environment["COPYTRADING_RUNTIME_ROOT"],
            let enginePath = environment["COPYTRADING_ENGINE_ROOT"],
            let libraryPath = environment["COPYTRADING_PYTHON_LIBRARY_PATH"]
        else { return nil }
        state = FileManager.default.temporaryDirectory
            .appending(path: "copytrading-managed-\(UUID().uuidString)", directoryHint: .isDirectory)
        paths = RuntimePaths(
            applicationSupportDirectory: state,
            runtimeRoot: URL(filePath: runtimePath, directoryHint: .isDirectory),
            engineSourceRoot: URL(filePath: enginePath, directoryHint: .isDirectory)
        )
        python = try RuntimeResourceCatalog.runtimeManifest().executable(named: "cpython", under: paths.runtimeRoot)
        self.libraryPath = libraryPath
    }

    func engine(identity: String, logsDirectory: URL, settings: DiagnosticsSettings) -> ProcessLaunchSpecification {
        ProcessLaunchSpecification(
            child: .engine,
            executableURL: python,
            arguments: ["-u", "-m", "copytrading_engine", "--data-dir", state.path, "--instance-id", identity],
            environment: [
                "PATH": "/usr/bin:/bin",
                "PYTHONPATH": "\(paths.engineSourceRoot.appending(path: "src").path):\(libraryPath)",
                "PYTHONUNBUFFERED": "1",
                "PYTHONDONTWRITEBYTECODE": "1",
                "COPYTRADING_DESKTOP_OWNER_SUPPORT_DIR": state.path,
                "COPYTRADING_DESKTOP_DIAGNOSTICS_STATE_DIR": logsDirectory.path,
            ].merging(settings.engineEnvironment) { current, _ in current },
            workingDirectory: state,
            readiness: .engineStatus(expectedInstanceID: identity),
            stdoutIsIPC: true
        )
    }
}

private func completeSelfTest(_ client: EngineClient) async throws -> (SelfTestCommand, WorkflowView) {
    let command = SelfTestCommand(
        commandID: UUID().uuidString.lowercased(),
        text: "Bought AAPL 1/6 at 200",
        destinationIDs: ["self-test-a", "self-test-b"]
    )
    _ = try await client.submitSelfTest(command)
    let deadline = ContinuousClock().now.advanced(by: .seconds(10))
    var workflow = try await client.workflow(id: command.commandID)
    while workflow.stage != .completed && ContinuousClock().now < deadline {
        try await Task.sleep(for: .milliseconds(100))
        workflow = try await client.workflow(id: command.commandID)
    }
    return (command, workflow)
}

@MainActor
func runManagedRuntimeTests() async throws {
    guard let runtime = try ManagedRuntime() else {
        FileHandle.standardError.write(Data("SKIP managed native runtime: paths are unset\n".utf8))
        return
    }
    defer { try? FileManager.default.removeItem(at: runtime.state) }
    let lock = try runtime.paths.acquireInstallationLock()
    let identity = try runtime.paths.installationIdentity()
    let settings = try DiagnosticsSettings(ageDays: 14, storageLimitBytes: 64 * 1_024 * 1_024)
    let supervisor = ProcessSupervisor(
        configuration: ProcessSupervisorConfiguration(
            children: [runtime.engine(identity: identity, logsDirectory: runtime.paths.logsDirectory, settings: settings)],
            maximumRestarts: 0,
            startupTimeout: .seconds(45)
        ),
        installationLock: lock
    )
    do {
        try await supervisor.start()
        let client = try await supervisor.engineClient()
        let ready = try await client.status()
        try #require(
            ready.instanceID == identity && ready.state == .running,
            "managed engine did not report its installation identity and readiness")
        let (command, workflow) = try await completeSelfTest(client)
        try #require(
            workflow.stage == .completed && workflow.outcomes.count == 2,
            "managed engine did not complete the two simulated outcomes")
        let status = try await client.status()
        try #require(
            status.telemetryState == .healthy && status.telemetryDropped == 0,
            "the engine did not journal its diagnostics cleanly")

        let journal = DiagnosticsJournal(directory: runtime.paths.logsDirectory)
        let file = runtime.paths.logsDirectory.appending(path: DiagnosticsJournal.fileName)
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        try #require(
            (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600,
            "the diagnostics journal is not private to the owner")
        let deadline = ContinuousClock().now.advanced(by: .seconds(5))
        var stages: [String] = []
        while stages.count < 3 && ContinuousClock().now < deadline {
            stages = try journal.entries().compactMap { entry -> String? in
                let isCommand = entry.fields.contains { field in
                    field.name == "command_id" && field.value == command.commandID
                }
                return entry.kind == .stage && isCommand ? entry.name : nil
            }
            if stages.count < 3 { try await Task.sleep(for: .milliseconds(100)) }
        }
        try #require(
            stages == ["completed", "parsed", "captured"],
            "the app could not read the self-test's stages from the engine journal, newest first: \(stages)")
        try #require(journal.usageBytes() > 0, "the journal reported no bytes on disk")

        await supervisor.stop()
        let engineRunning = await supervisor.isRunning(child: .engine)
        try #require(!engineRunning, "engine remained running after Stop")
        let afterStop = try journal.entries()
        try #require(afterStop.count >= 3, "the journal was not readable after the engine stopped")
    } catch {
        let tail = await supervisor.stderrTail(for: .engine)
        FileHandle.standardError.write(Data("Managed engine stderr tail: \(tail)\n".utf8))
        await supervisor.stop()
        throw error
    }
}

/// An unwritable log location degrades diagnostics only: trading work and command recovery go on.
func runUnwritableLogCommandRecoveryTest() async throws {
    guard let runtime = try ManagedRuntime() else {
        FileHandle.standardError.write(Data("SKIP unwritable log recovery: paths are unset\n".utf8))
        return
    }
    defer { try? FileManager.default.removeItem(at: runtime.state) }
    let lock = try runtime.paths.acquireInstallationLock()
    let identity = try runtime.paths.installationIdentity()
    let blocked = runtime.state.appending(path: "blocked-logs")
    try Data("a file where the log directory belongs".utf8).write(to: blocked)
    let supervisor = ProcessSupervisor(
        configuration: ProcessSupervisorConfiguration(
            children: [runtime.engine(identity: identity, logsDirectory: blocked, settings: DiagnosticsSettings())],
            maximumRestarts: 0,
            startupTimeout: .seconds(20)
        ), installationLock: lock)
    do {
        try await supervisor.start()
        let client = try await supervisor.engineClient()
        let initial = try await client.status()
        try #require(
            initial.state == .running && initial.telemetryState == .degraded
                && initial.telemetryErrorCode == "journal_unavailable",
            "an unwritable log did not produce a running engine with degraded logging")
        let command = SelfTestCommand(
            commandID: UUID().uuidString.lowercased(),
            text: "Bought AAPL 1/6 at 200", destinationIDs: ["self-test-a", "self-test-b"])
        let journal = CommandJournal(url: runtime.state.appending(path: "commands.json"))
        try await journal.record(command)
        _ = try await client.submitSelfTest(command)
        let restored = try await CommandJournal(url: runtime.state.appending(path: "commands.json")).entries()
        try #require(
            restored.count == 1 && restored[0].command == command && restored[0].workflow == nil,
            "a relaunch could not recover the pre-send envelope")
        var workflow = try await client.workflow(id: command.commandID)
        let deadline = ContinuousClock().now.advanced(by: .seconds(10))
        while workflow.stage != .completed && ContinuousClock().now < deadline {
            try await Task.sleep(for: .milliseconds(100))
            workflow = try await client.workflow(id: command.commandID)
        }
        try await journal.record(workflow)
        let repeated = try await client.submitSelfTest(restored[0].command)
        let afterRetry = try await client.status()
        try #require(
            repeated.commandID == command.commandID && afterRetry.accepted == 1,
            "same-ID recovery duplicated the engine workflow")
        try #require(
            workflow.stage == .completed && workflow.outcomes.count == 2,
            "an engine without a writable log did not complete two simulated outcomes")
        await supervisor.stop()
    } catch {
        let tail = await supervisor.stderrTail(for: .engine)
        await supervisor.stop()
        throw VerificationFailure(description: "unwritable log recovery test: \(error); engine stderr: \(tail)")
    }
}
