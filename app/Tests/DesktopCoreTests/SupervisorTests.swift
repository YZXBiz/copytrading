import Darwin
@testable import DesktopCore
import Foundation
import Testing

func runProcessSupervisorTests() async throws {
    let floodProgram = "import sys; sys.stderr.write('z' * 524288); sys.stderr.flush(); sys.exit(23)"
    let exitSupervisor = ProcessSupervisor(
        configuration: ProcessSupervisorConfiguration(
            children: [
                ProcessLaunchSpecification(
                    child: .engine,
                    executableURL: URL(filePath: "/usr/bin/python3"),
                    arguments: ["-u", "-c", floodProgram],
                    environment: ["PATH": "/usr/bin:/bin"],
                    readiness: .processStarted
                )
            ],
            maximumRestarts: 0,
            outputBufferLimit: 4096,
            startupTimeout: .seconds(5)
        ))
    let exitEvents = exitSupervisor.events
    try await exitSupervisor.start()
    let exit = try await nextChildExit(from: exitEvents)
    guard case .childExited(let child, let status, let restarting) = exit else {
        throw VerificationFailure(description: "unexpected child exit event")
    }
    try #require(child == .engine, "supervisor reported the wrong child")
    try #require(status == 23, "supervisor lost the real child's exit status")
    try #require(!restarting, "restart limit zero must suppress restart")
    let stderr = await exitSupervisor.stderrTail(for: .engine)
    try #require(stderr.count == 4096, "stderr capture expected a 4096-byte tail, got \(stderr.count)")
    await exitSupervisor.stop()

    try await runStartupOwnershipStopRaceTest()
    try await runStartupOwnershipMaintenancePauseTest()
    try await runStartupOwnershipMaintenanceFailureUnblocksStopTest()
    try await runStartupOwnershipConcurrentStopJoinsTest()
    try await runEngineDrainAcknowledgementOutcomeTest()
    try runRestartTransitionPolicyTests()
    try await runSuccessfulRestartTest()
    try await runScheduledRestartStopTest()
}

private func runEngineDrainAcknowledgementOutcomeTest() async throws {
    try await checkEngineDrainAcknowledgement(fails: false, expected: .acknowledged)
    try await checkEngineDrainAcknowledgement(fails: true, expected: .unconfirmed)
}

private func checkEngineDrainAcknowledgement(
    fails: Bool,
    expected: EngineDrainAcknowledgement
) async throws {
    let root = FileManager.default.temporaryDirectory.appending(
        path: "copytrading-engine-stop-outcome-\(UUID().uuidString)"
    )
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let ready = root.appending(path: "ready")
    let stopped = root.appending(path: "stopped")
    let childProgram = """
        import pathlib,signal,sys,time
        ready=pathlib.Path(sys.argv[1])
        stopped=pathlib.Path(sys.argv[2])
        def terminate(signum,frame):
            stopped.write_text('stopped')
            raise SystemExit(0)
        signal.signal(signal.SIGTERM,terminate)
        ready.write_text('ready')
        while True: time.sleep(1)
        """
    let requester = TestGracefulEngineStopRequester(fails: fails)
    let supervisor = ProcessSupervisor(
        configuration: ProcessSupervisorConfiguration(
            children: [
                ProcessLaunchSpecification(
                    child: .engine,
                    executableURL: URL(filePath: "/usr/bin/python3"),
                    arguments: ["-u", "-c", childProgram, ready.path, stopped.path],
                    environment: ["PATH": "/usr/bin:/bin"],
                    readiness: .processStarted,
                    stdoutIsIPC: true
                )
            ],
            maximumRestarts: 0,
            startupTimeout: .seconds(5)
        ),
        gracefulStopRequester: requester
    )

    try await supervisor.start()
    try await waitForFile(ready, description: "owned engine stop test readiness")
    let report = await supervisor.stop()
    let stopRequestCount = await requester.callCount()
    let childIsRunning = await supervisor.isRunning(child: .engine)
    let childAcknowledgedTermination = FileManager.default.fileExists(atPath: stopped.path)
    try #require(
        report.engineDrainAcknowledgement == expected,
        "supervisor reported \(report.engineDrainAcknowledgement), expected \(expected)")
    try #require(stopRequestCount == 1, "graceful engine Stop must be requested exactly once")
    try #require(
        !childIsRunning && childAcknowledgedTermination,
        "engine drain failure must still stop only the supervisor-owned engine child")
}

private actor TestGracefulEngineStopRequester: GracefulEngineStopRequesting {
    private let fails: Bool
    private var calls = 0

    init(fails: Bool) {
        self.fails = fails
    }

    func requestGracefulStop() async throws {
        calls += 1
        if fails { throw EngineTransportError.requestTimedOut }
    }

    func callCount() -> Int { calls }
}

private func runRestartTransitionPolicyTests() throws {
    try #require(
        RestartTransitionPolicy.nextAttempt(attemptsUsed: 0, maximumRestarts: 2, explicitlyStopped: false) == 1,
        "first unexpected exit should schedule restart 1")
    try #require(
        RestartTransitionPolicy.nextAttempt(attemptsUsed: 1, maximumRestarts: 2, explicitlyStopped: false) == 2,
        "second failure should use the final restart slot")
    try #require(
        RestartTransitionPolicy.nextAttempt(attemptsUsed: 2, maximumRestarts: 2, explicitlyStopped: false) == nil,
        "restart budget must be bounded")
    try #require(
        RestartTransitionPolicy.nextAttempt(attemptsUsed: 0, maximumRestarts: 2, explicitlyStopped: true) == nil,
        "explicit Stop must suppress a pending transition")
}

private func runSuccessfulRestartTest() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "copytrading-restart-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let counter = root.appending(path: "launch-count")
    let program = """
        import pathlib,sys,time
        path=pathlib.Path(sys.argv[1])
        count=int(path.read_text()) if path.exists() else 0
        path.write_text(str(count+1))
        if count == 0:
            time.sleep(.3)
            sys.exit(23)
        time.sleep(30)
        """
    let supervisor = ProcessSupervisor(
        configuration: ProcessSupervisorConfiguration(
            children: [
                ProcessLaunchSpecification(
                    child: .engine, executableURL: URL(filePath: "/usr/bin/python3"),
                    arguments: ["-u", "-c", program, counter.path],
                    environment: ["PATH": "/usr/bin:/bin"], readiness: .processStarted
                )
            ], maximumRestarts: 1, restartDelay: .milliseconds(100), startupTimeout: .seconds(3)
        ))
    try await supervisor.start()
    let deadline = ContinuousClock().now.advanced(by: .seconds(4))
    while ContinuousClock().now < deadline {
        if (try? String(contentsOf: counter, encoding: .utf8)) == "2",
            await supervisor.isRunning(child: .engine)
        {
            break
        }
        try await Task.sleep(for: .milliseconds(50))
    }
    let count = try? String(contentsOf: counter, encoding: .utf8)
    let running = await supervisor.isRunning(child: .engine)
    await supervisor.stop()
    try #require(count == "2" && running, "a child did not successfully restart once within its budget")
}

private func runScheduledRestartStopTest() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "copytrading-stop-restart-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let counter = root.appending(path: "launch-count")
    let program = """
        import pathlib,sys,time
        path=pathlib.Path(sys.argv[1])
        count=int(path.read_text()) if path.exists() else 0
        path.write_text(str(count+1))
        time.sleep(.3)
        sys.exit(23)
        """
    let supervisor = ProcessSupervisor(
        configuration: ProcessSupervisorConfiguration(
            children: [
                ProcessLaunchSpecification(
                    child: .engine, executableURL: URL(filePath: "/usr/bin/python3"),
                    arguments: ["-u", "-c", program, counter.path],
                    environment: ["PATH": "/usr/bin:/bin"], readiness: .processStarted
                )
            ], maximumRestarts: 2, restartDelay: .seconds(1), startupTimeout: .seconds(3)
        ))
    let events = supervisor.events
    try await supervisor.start()
    let event = try await nextChildExit(from: events)
    guard case .childExited(_, _, let restarting) = event else {
        throw VerificationFailure(description: "missing child-exited transition")
    }
    try #require(restarting, "the child exit should schedule a restart")
    await supervisor.stop()
    try await Task.sleep(for: .milliseconds(1_200))
    let count = try? String(contentsOf: counter, encoding: .utf8)
    try #require(count == "1", "explicit Stop did not suppress a scheduled restart")
}

private func runStartupOwnershipStopRaceTest() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "startup-stop-race-\(UUID().uuidString)")
    let paths = RuntimePaths(applicationSupportDirectory: root, runtimeRoot: root, engineSourceRoot: root)
    defer { try? FileManager.default.removeItem(at: root) }
    let lock = try paths.acquireInstallationLock()
    let attempt = StartupOwnership(lock: lock)
    let startupToken = try await attempt.beginStartupAttempt()
    let ready = root.appending(path: "engine-ready")
    let childProgram = "import pathlib,sys,time; pathlib.Path(sys.argv[1]).write_text('ready'); time.sleep(30)"
    let stopRequester = HeldFailingGracefulEngineStopRequester()
    let supervisor = ProcessSupervisor(
        configuration: ProcessSupervisorConfiguration(
            children: [
                ProcessLaunchSpecification(
                    child: .engine,
                    executableURL: URL(filePath: "/usr/bin/python3"),
                    arguments: ["-u", "-c", childProgram, ready.path],
                    environment: ["PATH": "/usr/bin:/bin"],
                    readiness: .processStarted,
                    stdoutIsIPC: true
                )
            ],
            maximumRestarts: 0,
            startupTimeout: .seconds(5)
        ),
        installationLock: lock,
        gracefulStopRequester: stopRequester
    )
    let adoptedSupervisor = await attempt.adopt(supervisor, for: startupToken)
    try #require(adoptedSupervisor, "startup owner refused the original supervisor")
    try await supervisor.start()
    try await waitForFile(ready, description: "startup ownership terminal-stop race readiness")

    let stopTask = Task { await attempt.stop() }
    await stopRequester.waitUntilRequested()
    let maintenanceReturned = StartupOwnershipCompletionFlag()
    let maintenanceTask = Task { () -> Bool in
        do {
            let transition = try await attempt.beginMaintenanceTransition()
            await attempt.finishMaintenanceTransition(transition)
            await maintenanceReturned.complete()
            return true
        } catch StartupOwnershipError.terminalStopWon {
            // Terminal Stop keeps ownership until its detached drain and release finish.
            await maintenanceReturned.complete()
            return false
        } catch {
            await maintenanceReturned.complete()
            return false
        }
    }

    try await Task.sleep(for: .milliseconds(100))
    let maintenanceCompletedTooEarly = await maintenanceReturned.isComplete()
    try #require(
        !maintenanceCompletedTooEarly,
        "maintenance returned before terminal Stop finished draining and releasing its lock")
    do {
        let competingLock = try paths.acquireInstallationLock()
        competingLock.release()
        throw VerificationFailure(description: "terminal Stop released the lock before its drain completed")
    } catch RuntimePathsError.alreadyRunning {
        // The held engine drain keeps the stable lock owned.
    }

    await stopRequester.release()
    _ = await stopTask.value
    let maintenanceBegan = await maintenanceTask.value
    try #require(!maintenanceBegan, "maintenance took ownership after terminal Stop won")
    let maintenanceCompleted = await maintenanceReturned.isComplete()
    try #require(maintenanceCompleted, "maintenance did not finish after terminal Stop")
    let staleSupervisor = ProcessSupervisor(
        configuration: ProcessSupervisorConfiguration(children: []),
        installationLock: lock
    )
    let adoptedAfterStop = await attempt.adopt(staleSupervisor, for: startupToken)
    try #require(!adoptedAfterStop, "stopped attempt adopted a supervisor after ownership transfer")
    let finalLock = try paths.acquireInstallationLock()
    finalLock.release()
}

private func runStartupOwnershipMaintenancePauseTest() async throws {
    let root = FileManager.default.temporaryDirectory.appending(
        path: "startup-maintenance-pause-\(UUID().uuidString)"
    )
    let paths = RuntimePaths(applicationSupportDirectory: root, runtimeRoot: root, engineSourceRoot: root)
    defer { try? FileManager.default.removeItem(at: root) }
    let lock = try paths.acquireInstallationLock()
    let stopJoinSignal = StartupStopJoinSignal()
    let ownership = StartupOwnership(lock: lock) {
        await stopJoinSignal.signal()
    }
    let staleStartupToken = try await ownership.beginStartupAttempt()
    let original = ProcessSupervisor(
        configuration: ProcessSupervisorConfiguration(children: []),
        installationLock: lock
    )
    let adoptedOriginal = await ownership.adopt(original, for: staleStartupToken)
    try #require(adoptedOriginal, "startup owner refused its original supervisor")

    let transition = try await ownership.beginMaintenanceTransition()
    let activeBeforeSwitch = try await ownership.resolveActiveGeneration(from: paths, during: transition)
    guard let previousGeneration = activeBeforeSwitch.activeGenerationID else {
        throw VerificationFailure(description: "maintenance did not resolve its current generation")
    }
    let candidateID = UUID().uuidString.lowercased()
    let candidateDirectory = root.appending(path: "generations/\(candidateID)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: candidateDirectory, withIntermediateDirectories: true)
    try FileManager.default.setAttributes(
        [.posixPermissions: NSNumber(value: 0o700)],
        ofItemAtPath: candidateDirectory.path
    )
    try Data("restore-manual".utf8).write(to: candidateDirectory.appending(path: "restore-gate"))
    let returnedPrevious = try await ownership.switchActiveGeneration(
        from: paths,
        to: candidateID,
        expectedCurrentGeneration: previousGeneration,
        during: transition
    )
    try #require(
        returnedPrevious == previousGeneration,
        "maintenance generation switch lost the rollback target")
    let activeCandidate = try await ownership.resolveActiveGeneration(from: paths, during: transition)
    try #require(
        activeCandidate.activeGenerationID == candidateID,
        "maintenance generation switch did not select the staged candidate")
    let lockStayedHeld: Bool
    do {
        let competingLock = try paths.acquireInstallationLock()
        competingLock.release()
        lockStayedHeld = false
    } catch RuntimePathsError.alreadyRunning {
        lockStayedHeld = true
    }
    try #require(lockStayedHeld, "maintenance pause released the stable installation lock")

    let staleSupervisor = ProcessSupervisor(
        configuration: ProcessSupervisorConfiguration(children: []),
        installationLock: lock
    )
    let adoptedStaleStartup = await ownership.adopt(staleSupervisor, for: staleStartupToken)
    try #require(!adoptedStaleStartup, "pre-maintenance startup adopted into a later generation")
    let lockStayedHeldAfterStaleCleanup: Bool
    do {
        let competingLock = try paths.acquireInstallationLock()
        competingLock.release()
        lockStayedHeldAfterStaleCleanup = false
    } catch RuntimePathsError.alreadyRunning {
        lockStayedHeldAfterStaleCleanup = true
    }
    try #require(lockStayedHeldAfterStaleCleanup, "stale supervisor cleanup released the maintenance-owned lock")

    let replacement = try await ownership.makeSupervisor(
        configuration: ProcessSupervisorConfiguration(children: []),
        during: transition
    )
    let adoptedReplacement = await ownership.adopt(replacement, during: transition)
    try #require(adoptedReplacement, "startup owner refused the replacement supervisor")
    let replacementStop = try await ownership.stopReplacementForMaintenance(during: transition)
    try #require(
        replacementStop.engineDrainAcknowledgement == .noLiveEngine,
        "an unstarted replacement reported a live engine drain")
    let replacementStopKeptLock: Bool
    do {
        let competingLock = try paths.acquireInstallationLock()
        competingLock.release()
        replacementStopKeptLock = false
    } catch RuntimePathsError.alreadyRunning {
        replacementStopKeptLock = true
    }
    try #require(
        replacementStopKeptLock,
        "stopping a replacement during restore released the retained installation lock")

    let shutdownCoordinator = ShutdownCoordinator()
    let competingQuit = Task {
        await shutdownCoordinator.run {
            await ownership.stop()
        }
    }
    await stopJoinSignal.waitUntilSignaled()
    let lockRemainedHeldWhileQuitWaited: Bool
    do {
        let competingLock = try paths.acquireInstallationLock()
        competingLock.release()
        lockRemainedHeldWhileQuitWaited = false
    } catch RuntimePathsError.alreadyRunning {
        lockRemainedHeldWhileQuitWaited = true
    }
    await ownership.finishMaintenanceTransition(transition)
    await stopJoinSignal.release()
    _ = await competingQuit.value
    let releasedLock = try paths.acquireInstallationLock()
    releasedLock.release()
    try #require(
        lockRemainedHeldWhileQuitWaited,
        "competing Stop/Quit released the stable lock during restore maintenance")
}

private func runStartupOwnershipMaintenanceFailureUnblocksStopTest() async throws {
    let root = FileManager.default.temporaryDirectory.appending(
        path: "startup-maintenance-failure-\(UUID().uuidString)"
    )
    let paths = RuntimePaths(applicationSupportDirectory: root, runtimeRoot: root, engineSourceRoot: root)
    defer { try? FileManager.default.removeItem(at: root) }
    let lock = try paths.acquireInstallationLock()
    let stopJoinSignal = StartupStopJoinSignal()
    let ownership = StartupOwnership(lock: lock) {
        await stopJoinSignal.signal()
    }
    let operationGate = StartupMaintenanceOperationGate()
    let transitionBox = StartupMaintenanceTransitionBox()
    let activation = Task { () -> Bool in
        do {
            try await ownership.withMaintenanceTransition { transition in
                await transitionBox.store(transition)
                await operationGate.pauseUntilReleased()
                throw VerificationFailure(description: "injected activation failure")
            }
            return false
        } catch let error as VerificationFailure where error.description == "injected activation failure" {
            return true
        } catch {
            return false
        }
    }
    await operationGate.waitUntilEntered()
    let stopCompleted = StartupOwnershipCompletionFlag()
    let stopTask = Task {
        let report = await ownership.stop()
        await stopCompleted.complete()
        return report
    }
    await stopJoinSignal.waitUntilSignaled()

    await operationGate.release()
    let activationFailed = await activation.value
    try #require(activationFailed, "maintenance returned an unexpected activation result")
    try await Task.sleep(for: .milliseconds(100))
    let stopWasUnblocked = await stopCompleted.isComplete()
    if !stopWasUnblocked, let transition = await transitionBox.value() {
        // Leave the test process clean if the regression under test strands the waiter.
        await ownership.finishMaintenanceTransition(transition)
    }
    await stopJoinSignal.release()
    _ = await stopTask.value
    try #require(stopWasUnblocked, "failed activation left a waiting Stop suspended")

    let reacquired = try paths.acquireInstallationLock()
    reacquired.release()
}

func runStartupOwnershipPreparationReservationTest() async throws {
    let root = FileManager.default.temporaryDirectory.appending(
        path: "startup-maintenance-reservation-\(UUID().uuidString)"
    )
    let paths = RuntimePaths(applicationSupportDirectory: root, runtimeRoot: root, engineSourceRoot: root)
    defer { try? FileManager.default.removeItem(at: root) }
    let lock = try paths.acquireInstallationLock()
    let stopJoinSignal = StartupStopJoinSignal()
    let ownership = StartupOwnership(lock: lock) {
        await stopJoinSignal.signal()
    }
    let preparationGate = StartupMaintenanceOperationGate()
    let activation = Task {
        try await ownership.withReservedMaintenanceTransition(
            prepare: {
                await preparationGate.pauseUntilReleased()
                return "prepared-candidate"
            },
            operation: { prepared, transition in
                try #require(
                    prepared == "prepared-candidate",
                    "maintenance did not carry the prepared candidate into the transition")
                try #require(
                    transition.stopReport.engineDrainAcknowledgement == .noLiveEngine,
                    "empty maintenance owner reported a live engine drain")
                return "activated"
            }
        )
    }
    await preparationGate.waitUntilEntered()
    let stopTask = Task { await ownership.stop() }
    await stopJoinSignal.waitUntilSignaled()

    let lockStayedHeldDuringPreparation: Bool
    do {
        let competingLock = try paths.acquireInstallationLock()
        competingLock.release()
        lockStayedHeldDuringPreparation = false
    } catch RuntimePathsError.alreadyRunning {
        lockStayedHeldDuringPreparation = true
    }
    try #require(
        lockStayedHeldDuringPreparation,
        "Stop released the installation lock during restore candidate preparation")

    await preparationGate.release()
    let result = try await activation.value
    try #require(result == "activated", "reserved maintenance did not finish after Stop joined")
    _ = await stopTask.value
    let releasedLock = try paths.acquireInstallationLock()
    releasedLock.release()
}

private func runStartupOwnershipConcurrentStopJoinsTest() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "startup-concurrent-stop-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let paths = RuntimePaths(
        applicationSupportDirectory: root.appending(path: "support", directoryHint: .isDirectory),
        runtimeRoot: root,
        engineSourceRoot: root
    )
    let installationLock = try paths.acquireInstallationLock()

    let ready = root.appending(path: "engine-ready")
    let engineProgram = """
        import pathlib,sys,time
        pathlib.Path(sys.argv[1]).write_text('ready')
        while True: time.sleep(1)
        """
    let stopRequester = HeldFailingGracefulEngineStopRequester()
    let supervisor = ProcessSupervisor(
        configuration: ProcessSupervisorConfiguration(
            children: [
                ProcessLaunchSpecification(
                    child: .engine,
                    executableURL: URL(filePath: "/usr/bin/python3"),
                    arguments: ["-u", "-c", engineProgram, ready.path],
                    environment: ["PATH": "/usr/bin:/bin"],
                    readiness: .processStarted,
                    stdoutIsIPC: true
                )
            ],
            maximumRestarts: 0,
            startupTimeout: .seconds(5)
        ),
        gracefulStopRequester: stopRequester
    )
    try await supervisor.start()
    try await waitForFile(ready, description: "startup ownership stop-race engine readiness")

    let joinSignal = StartupStopJoinSignal()
    let ownership = StartupOwnership(lock: installationLock) {
        await joinSignal.signal()
    }
    let startupToken = try await ownership.beginStartupAttempt()
    let acceptedSupervisor = await ownership.adopt(supervisor, for: startupToken)
    try #require(acceptedSupervisor, "startup owner refused its runtime supervisor")

    let startupCatchCleanup = Task { await ownership.stop() }
    await stopRequester.waitUntilRequested()

    let reportBox = StopReportBox()
    let quitCoordinator = ShutdownCoordinator()
    let stopOrQuitCleanup = Task {
        await quitCoordinator.run {
            await reportBox.store(await ownership.stop())
        }
        return await reportBox.report()
    }
    await joinSignal.waitUntilSignaled()

    let lockStillHeld: Bool
    do {
        let competingLock = try paths.acquireInstallationLock()
        competingLock.release()
        lockStillHeld = false
    } catch {
        lockStillHeld = true
    }

    await joinSignal.release()
    await stopRequester.release()
    let startupReport = await startupCatchCleanup.value
    let stopOrQuitReport = await stopOrQuitCleanup.value
    let remainingEngine = await supervisor.isRunning(child: .engine)
    let releasedLock = try paths.acquireInstallationLock()
    releasedLock.release()

    try #require(lockStillHeld, "startup cleanup released its installation lock before the held supervisor stop completed")
    try #require(
        startupReport.engineDrainAcknowledgement == .unconfirmed,
        "startup catch lost the supervisor's unconfirmed drain report")
    try #require(
        stopOrQuitReport == startupReport,
        "concurrent Stop/Quit returned before startup cleanup and lost its actual stop report")
    try #require(!remainingEngine, "startup cleanup left its owned engine running")
}

private actor HeldFailingGracefulEngineStopRequester: GracefulEngineStopRequesting {
    private var requestContinuation: CheckedContinuation<Void, Never>?
    private var requestStartedContinuation: CheckedContinuation<Void, Never>?
    private var requestStarted = false

    func requestGracefulStop() async throws {
        requestStarted = true
        requestStartedContinuation?.resume()
        requestStartedContinuation = nil
        await withCheckedContinuation { requestContinuation = $0 }
        throw EngineTransportError.requestTimedOut
    }

    func waitUntilRequested() async {
        guard !requestStarted else { return }
        await withCheckedContinuation { requestStartedContinuation = $0 }
    }

    func release() {
        requestContinuation?.resume()
        requestContinuation = nil
    }
}

private actor StartupStopJoinSignal {
    private var signaled = false
    private var signalContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func signal() async {
        signaled = true
        signalContinuation?.resume()
        signalContinuation = nil
        await withCheckedContinuation { releaseContinuation = $0 }
    }

    func waitUntilSignaled() async {
        guard !signaled else { return }
        await withCheckedContinuation { signalContinuation = $0 }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private actor StartupOwnershipCompletionFlag {
    private var completed = false

    func complete() {
        completed = true
    }

    func isComplete() -> Bool {
        completed
    }
}

private actor StartupMaintenanceOperationGate {
    private var entered = false
    private var released = false
    private var enteredContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func pauseUntilReleased() async {
        entered = true
        enteredContinuation?.resume()
        enteredContinuation = nil
        guard !released else { return }
        await withCheckedContinuation { releaseContinuation = $0 }
    }

    func waitUntilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { enteredContinuation = $0 }
    }

    func release() {
        released = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private actor StartupMaintenanceTransitionBox {
    private var transition: MaintenanceTransition?

    func store(_ value: MaintenanceTransition) {
        transition = value
    }

    func value() -> MaintenanceTransition? {
        transition
    }
}

private actor StopReportBox {
    private var value: ProcessSupervisorStopReport?

    func store(_ report: ProcessSupervisorStopReport) {
        value = report
    }

    func report() -> ProcessSupervisorStopReport {
        value ?? .noLiveEngine
    }
}

private func nextChildExit(from events: AsyncStream<RuntimeEvent>) async throws -> RuntimeEvent {
    for await event in events {
        if case .childExited = event { return event }
    }
    throw VerificationFailure(description: "supervisor event stream ended before child exit")
}

func runEngineClientProcessTests() async throws {
    let program = #"""
        import json, sys
        pending = []
        def send(request, result_type, value):
            print(json.dumps({"version": 1, "request_id": request["request_id"], "ok": {"type": result_type, result_type: value}}), flush=True)
        for line in sys.stdin:
            request = json.loads(line)
            operation = request["operation"]
            if operation == "get_status":
                send(request, "status", {"instance_id":"installation-1","state":"running","accepted":0,"pending":0,"completed":0,"telemetry_state":"healthy","telemetry_dropped":0,"telemetry_error_code":None,"diagnostic_capture":{"source_events":0,"source_event_gaps":0,"model_requests":0,"model_request_gaps":0,"model_responses":0,"model_response_gaps":0}})
            elif operation == "get_workflow":
                pending.append(request)
                if len(pending) == 3:
                    for item in reversed(pending):
                        command_id = item["command_id"]
                        send(item, "workflow", {"command_id":command_id,"stage":"completed","outcomes":[],"trace_id":"30000000-0000-4000-8000-000000000003"})
                    pending.clear()
            elif operation == "stop":
                print(json.dumps({"version":1,"request_id":request["request_id"],"ok":{"type":"stopping"}}), flush=True)
                break
        """#
    let supervisor = ProcessSupervisor(
        configuration: ProcessSupervisorConfiguration(
            children: [
                ProcessLaunchSpecification(
                    child: .engine,
                    executableURL: URL(filePath: "/usr/bin/python3"),
                    arguments: ["-u", "-c", program],
                    environment: ["PATH": "/usr/bin:/bin"],
                    readiness: .engineStatus(expectedInstanceID: "installation-1"),
                    stdoutIsIPC: true
                )
            ],
            maximumRestarts: 0,
            startupTimeout: .seconds(5)
        ))
    do {
        try await supervisor.start()
        let client = try await supervisor.engineClient()
        let results = try await withThrowingTaskGroup(of: String.self) { group in
            for commandID in ["sim-a", "sim-b", "sim-c"] {
                group.addTask {
                    try await client.workflow(id: commandID).commandID
                }
            }
            var received: [String] = []
            for try await commandID in group { received.append(commandID) }
            return received
        }
        try #require(Set(results) == Set(["sim-a", "sim-b", "sim-c"]), "concurrent IPC responses were matched to the wrong request IDs")
        await supervisor.stop()
    } catch {
        await supervisor.stop()
        throw error
    }
}

func runEngineActionsBackupRestoreTests() async throws {
    let program = #"""
        import json,sys
        for line in sys.stdin:
            request=json.loads(line)
            operation=request['operation']
            if operation == 'create_backup':
                payload={'type':'backup','manifest':{'format':'copytrading-backup','format_version':1,'created_at':'2026-09-27T12:00:00+00:00','installation_id':request['destination'],'environment_ids':[],'members':[{'path':'application.db','size':64,'sha256':'a'*64,'schema_version':'sqlite:application:2;components='}]}}
            elif operation == 'preview_restore':
                payload={'type':'restore_preview','preview':{'format_version':1,'created_at':'2026-09-27T12:00:00+00:00','installation_id':request['archive_path'],'matches_installation':False,'environment_ids':[],'account_ids':[],'credential_references':[],'staging_id':'restore-test','members':[{'path':'application.db','size':64,'sha256':'a'*64,'schema_version':'sqlite:application:2;components='}]}}
            elif operation == 'prepare_restore_candidate':
                assert request['staging_id'] == 'restore-test'
                payload={'type':'restore_candidate','candidate_id':'00000000-0000-4000-8000-000000000001'}
            elif operation == 'restore_candidate_status':
                payload={'type':'restore_candidate_status','candidate':{'candidate_id':'00000000-0000-4000-8000-000000000001','previous_generation':'00000000-0000-4000-8000-000000000002','active_generation':'00000000-0000-4000-8000-000000000002','installation_id':'00000000-0000-4000-8000-000000000003','environment_ids':['paper:acct-a'],'account_ids':['acct-a'],'credential_references':['00000000-0000-4000-8000-000000000004'],'candidate_valid':True}}
            elif operation == 'abort_restore_candidate':
                assert request['candidate_id'] == '00000000-0000-4000-8000-000000000001'
                payload={'type':'restore_aborted','candidate_id':request['candidate_id']}
            elif operation == 'restore_preflight':
                assert request['candidate_id'] == '00000000-0000-4000-8000-000000000001'
                assert request['accounts'] == [{'account_id':'acct-a','environment':'paper','key':'test-key','secret':'test-secret'}]
                payload={'type':'restore_preflight','candidate_id':request['candidate_id'],'eligible':True,'checked_account_count':1,'blockers':[],'completion_token':'0123456789abcdef0123456789abcdef'}
            elif operation == 'complete_restore_candidate':
                assert request['candidate_id'] == '00000000-0000-4000-8000-000000000001'
                assert request['completion_token'] == '0123456789abcdef0123456789abcdef'
                payload={'type':'restore_activated','candidate_id':request['candidate_id']}
            elif operation == 'stop':
                payload={'type':'stopping'}
            else:
                continue
            print(json.dumps({'version':1,'request_id':request['request_id'],'ok':payload}),flush=True)
            if operation == 'stop': break
        """#
    let supervisor = ProcessSupervisor(
        configuration: ProcessSupervisorConfiguration(
            children: [
                ProcessLaunchSpecification(
                    child: .engine,
                    executableURL: URL(filePath: "/usr/bin/python3"),
                    arguments: ["-u", "-c", program],
                    environment: ["PATH": "/usr/bin:/bin"],
                    readiness: .processStarted,
                    stdoutIsIPC: true
                )
            ],
            maximumRestarts: 0,
            startupTimeout: .seconds(5)
        ))
    try await supervisor.start()
    let actions = EngineActions(supervisor: supervisor)
    do {
        let destination = URL(filePath: "/tmp/native-backup.zip")
        let manifest = try await actions.createBackup(destination: destination)
        try #require(
            manifest.installationID == destination.path,
            "native backup action did not send the selected destination")
        let archive = URL(filePath: "/tmp/native-restore.zip")
        let preview = try await actions.previewRestore(archive: archive)
        try #require(
            preview.installationID == archive.path && !preview.matchesInstallation,
            "native restore action lost the selected archive or identity warning")
        try #require(preview.stagingID == "restore-test", "native restore action lost isolated staging state")
        let candidate = try await actions.prepareRestoreCandidate(stagingID: preview.stagingID)
        try #require(
            candidate == "00000000-0000-4000-8000-000000000001",
            "native restore candidate action lost the candidate identity")
        let pendingRestore = try await actions.restoreCandidateStatus()
        try #require(
            pendingRestore?.candidateID == candidate && pendingRestore?.candidateValid == true,
            "native restore recovery status lost durable candidate state")
        try await actions.abortRestoreCandidate(candidateID: candidate)
        let checked = try await actions.restorePreflight(
            candidateID: candidate,
            accounts: [
                RestorePreflightAccount(
                    accountID: "acct-a", environment: .paper, key: "test-key", secret: "test-secret"
                )
            ])
        try #require(
            checked.eligible && checked.completionToken != nil && checked.blockers.isEmpty,
            "native restore preflight action lost eligibility or completion token")
        guard let completionToken = checked.completionToken else {
            throw VerificationFailure(description: "eligible preflight omitted its completion token")
        }
        try await actions.completeRestoreCandidate(
            candidateID: candidate,
            completionToken: completionToken
        )
        await supervisor.stop()
    } catch {
        await supervisor.stop()
        throw error
    }
}

func runEngineActionsRestartTests() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "copytrading-actions-restart-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let counter = root.appending(path: "launch-count")
    let program = #"""
        import json,pathlib,sys,time
        path=pathlib.Path(sys.argv[1])
        generation=int(path.read_text())+1 if path.exists() else 1
        path.write_text(str(generation))
        requests=0
        for line in sys.stdin:
            request=json.loads(line)
            requests+=1
            operation=request['operation']
            if operation == 'get_status':
                value={'instance_id':'installation-1','state':'running','accepted':generation,'pending':0,'completed':generation,'telemetry_state':'healthy','telemetry_dropped':0,'telemetry_error_code':None,'diagnostic_capture':{'source_events':0,'source_event_gaps':0,'model_requests':0,'model_request_gaps':0,'model_responses':0,'model_response_gaps':0}}
                result={'type':'status','status':value}
            elif operation == 'submit_self_test':
                command=request['command']
                value={'command_id':command['command_id'],'stage':'completed','outcomes':[], 'trace_id':'30000000-0000-4000-8000-000000000003'}
                result={'type':'workflow','workflow':value}
            elif operation == 'stop':
                result={'type':'stopping'}
            else:
                continue
            print(json.dumps({'version':1,'request_id':request['request_id'],'ok':result}),flush=True)
            if operation == 'stop': break
            if generation == 1 and requests >= 2: time.sleep(.25); break
        """#
    let supervisor = ProcessSupervisor(
        configuration: ProcessSupervisorConfiguration(
            children: [
                ProcessLaunchSpecification(
                    child: .engine, executableURL: URL(filePath: "/usr/bin/python3"),
                    arguments: ["-u", "-c", program, counter.path],
                    environment: ["PATH": "/usr/bin:/bin"],
                    readiness: .engineStatus(expectedInstanceID: "installation-1"), stdoutIsIPC: true
                )
            ], maximumRestarts: 1, restartDelay: .milliseconds(100), startupTimeout: .seconds(3)
        ))
    do {
        try await supervisor.start()
        let actions = EngineActions(supervisor: supervisor)
        let deadline = ContinuousClock().now.advanced(by: .seconds(4))
        while (try? String(contentsOf: counter, encoding: .utf8)) != "2" && ContinuousClock().now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        try #require((try? String(contentsOf: counter, encoding: .utf8)) == "2", "engine did not restart for action test")
        var recoveredStatus: EngineStatus?
        while ContinuousClock().now < deadline {
            if let status = try? await actions.status(), status.accepted == 2 {
                recoveredStatus = status
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        guard let status = recoveredStatus else {
            let stderr = await supervisor.stderrTail(for: .engine)
            throw VerificationFailure(description: "model status did not reconnect to engine generation 2: \(stderr)")
        }
        try #require(status.accepted == 2, "model status used the first engine generation")
        let workflow = try await actions.submitSelfTest(
            SelfTestCommand(
                commandID: "after-restart", text: "Bought AAPL 1/6 at 200", destinationIDs: ["self-test-a"]
            ))
        try #require(workflow.commandID == "after-restart", "model action used the first engine generation")
        await supervisor.stop()
    } catch {
        await supervisor.stop()
        throw error
    }
}

func runEngineClientCatPipeTests() async throws {
    let supervisor = ProcessSupervisor(
        configuration: ProcessSupervisorConfiguration(
            children: [
                ProcessLaunchSpecification(
                    child: .engine,
                    executableURL: URL(filePath: "/bin/cat"),
                    arguments: [],
                    environment: ["PATH": "/usr/bin:/bin"],
                    readiness: .processStarted,
                    stdoutIsIPC: true
                )
            ],
            maximumRestarts: 0,
            startupTimeout: .seconds(3)
        ))
    try await supervisor.start()
    let client = try await supervisor.engineClient()
    do {
        _ = try await client.status()
        throw VerificationFailure(description: "cat unexpectedly returned a typed engine status")
    } catch EngineContractError.missingResult {
        // cat echoed a complete newline framed request through the owned process pipes.
        await supervisor.stop()
    } catch {
        await supervisor.stop()
        throw error
    }
}

private func waitForFile(_ url: URL, description: String) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while !FileManager.default.fileExists(atPath: url.path), ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
    try #require(FileManager.default.fileExists(atPath: url.path), "timed out waiting for \(description)")
}
