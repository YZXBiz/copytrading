import Foundation

public enum RuntimeChild: String, Sendable, Hashable {
    case engine
}

public enum ChildReadiness: Sendable {
    case processStarted
    case engineStatus(expectedInstanceID: String)
}

public struct ProcessLaunchSpecification: Sendable {
    public let child: RuntimeChild
    public let executableURL: URL
    public let arguments: [String]
    public let environment: [String: String]
    public let workingDirectory: URL?
    public let readiness: ChildReadiness
    public let stdoutIsIPC: Bool

    public init(
        child: RuntimeChild,
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        workingDirectory: URL? = nil,
        readiness: ChildReadiness,
        stdoutIsIPC: Bool = false
    ) {
        self.child = child
        self.executableURL = executableURL
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
        self.readiness = readiness
        self.stdoutIsIPC = stdoutIsIPC
    }
}

public struct ProcessSupervisorConfiguration: Sendable {
    public let children: [ProcessLaunchSpecification]
    public let maximumRestarts: Int
    public let restartDelay: Duration
    public let outputBufferLimit: Int
    public let startupTimeout: Duration

    public init(
        children: [ProcessLaunchSpecification],
        maximumRestarts: Int = 3,
        restartDelay: Duration = .seconds(1),
        outputBufferLimit: Int = 16_384,
        startupTimeout: Duration = .seconds(40)
    ) {
        self.children = children
        self.maximumRestarts = max(0, maximumRestarts)
        self.restartDelay = restartDelay
        self.outputBufferLimit = max(1, outputBufferLimit)
        self.startupTimeout = startupTimeout
    }
}

public enum EngineDrainAcknowledgement: String, Equatable, Sendable {
    case acknowledged
    case unconfirmed
    case noLiveEngine
}

public struct ProcessSupervisorStopReport: Equatable, Sendable {
    public let engineDrainAcknowledgement: EngineDrainAcknowledgement
    public let forciblyStoppedChildren: [RuntimeChild]

    public init(
        engineDrainAcknowledgement: EngineDrainAcknowledgement,
        forciblyStoppedChildren: [RuntimeChild]
    ) {
        self.engineDrainAcknowledgement = engineDrainAcknowledgement
        self.forciblyStoppedChildren = forciblyStoppedChildren
    }

    public static let noLiveEngine = ProcessSupervisorStopReport(
        engineDrainAcknowledgement: .noLiveEngine,
        forciblyStoppedChildren: []
    )
}

public protocol GracefulEngineStopRequesting: Sendable {
    func requestGracefulStop() async throws
}

extension EngineClient: GracefulEngineStopRequesting {
    public func requestGracefulStop() async throws {
        try await stop()
    }
}

public enum RuntimeEvent: Sendable {
    case starting
    case ready(instanceID: String?)
    case stopped
    case childExited(child: RuntimeChild, status: Int32, restarting: Bool)
    case degraded(code: String)
}

public enum ProcessSupervisorError: Error, Equatable, LocalizedError, Sendable {
    case alreadyStarted
    case startupTimeout
    case startupFailed
    case missingEngineClient

    public var errorDescription: String? {
        switch self {
        case .alreadyStarted:
            "The local runtime is already starting or running."
        case .startupTimeout:
            "The local runtime did not become ready in time."
        case .startupFailed:
            "A required local process stopped during startup."
        case .missingEngineClient:
            "The local engine IPC connection is unavailable."
        }
    }
}

#if DEBUG
    public struct OwnedChildIdentity: Equatable, Sendable {
        public let processIdentifier: Int32
        public let generation: UUID

        public init(processIdentifier: Int32, generation: UUID) {
            self.processIdentifier = processIdentifier
            self.generation = generation
        }
    }
#endif

public actor ProcessSupervisor {
    public nonisolated let events: AsyncStream<RuntimeEvent>

    private let configuration: ProcessSupervisorConfiguration
    private let eventContinuation: AsyncStream<RuntimeEvent>.Continuation
    private var children: [RuntimeChild: OwnedProcess] = [:]
    private var observers: [RuntimeChild: Task<Void, Never>] = [:]
    private var restartTasks: [RuntimeChild: Task<Void, Never>] = [:]
    private var restartCounts: [RuntimeChild: Int] = [:]
    private var explicitStop = false
    private var hasStarted = false
    private var lastStopReport: ProcessSupervisorStopReport?
    private var installationLock: InstallationLock?
    private var engineClientValue: EngineClient?
    private let gracefulStopRequester: (any GracefulEngineStopRequesting)?
    private var stoppedStdoutTails: [RuntimeChild: String] = [:]
    private var stoppedStderrTails: [RuntimeChild: String] = [:]

    public init(
        configuration: ProcessSupervisorConfiguration,
        installationLock: InstallationLock? = nil,
        gracefulStopRequester: (any GracefulEngineStopRequesting)? = nil
    ) {
        let (events, continuation) = AsyncStream<RuntimeEvent>.makeStream()
        self.events = events
        eventContinuation = continuation
        self.configuration = configuration
        self.installationLock = installationLock
        self.gracefulStopRequester = gracefulStopRequester
    }

    public func start() async throws {
        guard !hasStarted else { throw ProcessSupervisorError.alreadyStarted }
        hasStarted = true
        explicitStop = false
        lastStopReport = nil
        eventContinuation.yield(.starting)

        do {
            for specification in configuration.children {
                try Task.checkCancellation()
                guard !explicitStop else { throw CancellationError() }
                let process = try await launch(specification)
                try await waitUntilReady(process, specification: specification)
            }
            let needsEngineStatus = configuration.children.contains { specification in
                guard specification.child == .engine else { return false }
                if case .engineStatus = specification.readiness { return true }
                return false
            }
            let identity: String?
            if needsEngineStatus {
                guard let engineClientValue else {
                    throw ProcessSupervisorError.missingEngineClient
                }
                identity = try await engineClientValue.status().instanceID
            } else {
                identity = nil
            }
            guard !explicitStop else { throw CancellationError() }
            eventContinuation.yield(.ready(instanceID: identity))
        } catch {
            await preserveOutputTails()
            await stopOwnedChildren()
            eventContinuation.yield(.degraded(code: "startup_failed"))
            hasStarted = false
            throw error
        }
    }

    @discardableResult
    public func stop(retainingInstallationLock: Bool = false) async -> ProcessSupervisorStopReport {
        if explicitStop, !hasStarted, let lastStopReport {
            if !retainingInstallationLock {
                installationLock?.release()
                installationLock = nil
            }
            return lastStopReport
        }
        explicitStop = true
        let scheduledRestarts = Array(restartTasks.values)
        for task in scheduledRestarts { task.cancel() }
        restartTasks.removeAll()
        var drainAcknowledgement: EngineDrainAcknowledgement = .noLiveEngine
        if engineClientValue != nil {
            do {
                if let gracefulStopRequester {
                    try await gracefulStopRequester.requestGracefulStop()
                } else {
                    try await engineClientValue?.stop()
                }
                drainAcknowledgement = .acknowledged
            } catch {
                drainAcknowledgement = .unconfirmed
            }
        }
        await preserveOutputTails()
        var forciblyStoppedChildren = await stopOwnedChildren()
        for task in scheduledRestarts { await task.value }
        await preserveOutputTails()
        forciblyStoppedChildren += await stopOwnedChildren()
        hasStarted = false
        if retainingInstallationLock {
            // StartupOwnership remains the sole lock owner through a generation switch.
            installationLock = nil
        } else {
            installationLock?.release()
            installationLock = nil
        }
        eventContinuation.yield(.stopped)
        let report = ProcessSupervisorStopReport(
            engineDrainAcknowledgement: drainAcknowledgement,
            forciblyStoppedChildren: Set(forciblyStoppedChildren).sorted { $0.rawValue < $1.rawValue }
        )
        lastStopReport = report
        return report
    }

    public func stderrTail(for child: RuntimeChild) async -> String {
        if let process = children[child] { return await process.stderrTail() }
        return stoppedStderrTails[child] ?? ""
    }

    public func stdoutTail(for child: RuntimeChild) async -> String {
        if let process = children[child] { return await process.stdoutTail() }
        return stoppedStdoutTails[child] ?? ""
    }

    public func isRunning(child: RuntimeChild) async -> Bool {
        await children[child]?.isRunning() ?? false
    }

    public func processIdentifier(for child: RuntimeChild) async -> Int32? {
        await children[child]?.processIdentifier()
    }

    #if DEBUG
        public func ownedChildIdentity(for child: RuntimeChild) async -> OwnedChildIdentity? {
            guard let process = children[child],
                let processID = await process.processIdentifier(),
                children[child] === process
            else { return nil }
            return OwnedChildIdentity(processIdentifier: processID, generation: process.generation)
        }

        public func terminateOwnedChildForTesting(
            _ child: RuntimeChild, expected identity: OwnedChildIdentity
        ) async throws {
            guard let process = children[child], process.generation == identity.generation,
                let processID = await process.processIdentifier(),
                processID == identity.processIdentifier,
                children[child] === process
            else { throw ProcessSupervisorError.startupFailed }
            await process.stop()
        }
    #endif

    public func engineClient() throws -> EngineClient {
        guard let engineClientValue else { throw ProcessSupervisorError.missingEngineClient }
        return engineClientValue
    }

    private func launch(_ specification: ProcessLaunchSpecification) async throws -> OwnedProcess {
        guard !explicitStop, !Task.isCancelled else { throw CancellationError() }
        let child = OwnedProcess(
            specification: specification,
            outputBufferLimit: configuration.outputBufferLimit
        )
        children[specification.child] = child
        stoppedStdoutTails.removeValue(forKey: specification.child)
        stoppedStderrTails.removeValue(forKey: specification.child)
        observers[specification.child]?.cancel()
        let events = child.events
        observers[specification.child] = Task { [weak self] in
            for await event in events {
                guard case .terminated(let status) = event else { continue }
                await self?.childTerminated(
                    specification: specification,
                    process: child,
                    status: status
                )
                return
            }
        }
        do {
            try await child.start()
            guard !explicitStop, !Task.isCancelled else { throw CancellationError() }
        } catch {
            if children[specification.child] === child {
                children.removeValue(forKey: specification.child)
                observers[specification.child]?.cancel()
            }
            await child.stop()
            if error is CancellationError { throw error }
            throw ProcessSupervisorError.startupFailed
        }
        if specification.stdoutIsIPC {
            engineClientValue = EngineClient(
                transport: child,
                requestTimeout: configuration.startupTimeout
            )
        }
        return child
    }

    private func waitUntilReady(
        _ child: OwnedProcess,
        specification: ProcessLaunchSpecification
    ) async throws {
        switch specification.readiness {
        case .processStarted:
            guard await child.isRunning() else { throw ProcessSupervisorError.startupFailed }
        case .engineStatus(let expectedInstanceID):
            guard let engineClient = engineClientValue else { throw ProcessSupervisorError.missingEngineClient }
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: configuration.startupTimeout)
            while clock.now < deadline {
                guard !explicitStop else { throw CancellationError() }
                guard await child.isRunning() else { throw ProcessSupervisorError.startupFailed }
                do {
                    let status = try await engineClient.status()
                    guard status.instanceID == expectedInstanceID else {
                        throw ProcessSupervisorError.startupFailed
                    }
                    if status.state == .running { return }
                } catch let error as ProcessSupervisorError {
                    throw error
                } catch {
                    // A status request can race engine initialization; retry inside the bounded deadline.
                }
                try await Task.sleep(for: .milliseconds(100))
            }
            throw ProcessSupervisorError.startupTimeout
        }
    }

    private func childTerminated(
        specification: ProcessLaunchSpecification,
        process: OwnedProcess,
        status: Int32
    ) async {
        guard children[specification.child] === process else { return }
        children.removeValue(forKey: specification.child)
        observers.removeValue(forKey: specification.child)
        if specification.child == .engine { engineClientValue = nil }
        stoppedStdoutTails[specification.child] = await process.stdoutTail()
        stoppedStderrTails[specification.child] = await process.stderrTail()
        guard !explicitStop else { return }

        let count = restartCounts[specification.child, default: 0]
        let shouldRestart =
            RestartTransitionPolicy.nextAttempt(
                attemptsUsed: count, maximumRestarts: configuration.maximumRestarts, explicitlyStopped: explicitStop
            ) != nil
        eventContinuation.yield(
            .childExited(
                child: specification.child,
                status: status,
                restarting: shouldRestart
            ))
        guard shouldRestart else {
            eventContinuation.yield(.degraded(code: "restart_limit_reached"))
            return
        }
        scheduleRestart(specification)
    }

    private func scheduleRestart(_ specification: ProcessLaunchSpecification) {
        let count = restartCounts[specification.child, default: 0]
        guard
            let nextAttempt = RestartTransitionPolicy.nextAttempt(
                attemptsUsed: count, maximumRestarts: configuration.maximumRestarts, explicitlyStopped: explicitStop
            )
        else {
            if !explicitStop { eventContinuation.yield(.degraded(code: "restart_limit_reached")) }
            return
        }
        restartCounts[specification.child] = nextAttempt
        restartTasks[specification.child]?.cancel()
        restartTasks[specification.child] = Task { [weak self] in
            do {
                try await Task.sleep(for: self?.configuration.restartDelay ?? .seconds(1))
                try Task.checkCancellation()
                await self?.restart(specification)
            } catch {
                return
            }
        }
    }

    private func restart(_ specification: ProcessLaunchSpecification) async {
        guard !explicitStop else { return }
        var launched: OwnedProcess?
        do {
            let process = try await launch(specification)
            launched = process
            try await waitUntilReady(process, specification: specification)
            guard !explicitStop, children[specification.child] === process else { return }
            var instanceID: String?
            if specification.child == .engine {
                instanceID = try await engineClientValue?.status().instanceID
            }
            guard !explicitStop, children[specification.child] === process else { return }
            restartTasks.removeValue(forKey: specification.child)
            eventContinuation.yield(.ready(instanceID: instanceID))
        } catch {
            guard !explicitStop else { return }
            if let launched {
                guard children[specification.child] === launched else { return }
                children.removeValue(forKey: specification.child)
                observers.removeValue(forKey: specification.child)?.cancel()
                if specification.child == .engine { engineClientValue = nil }
                stoppedStdoutTails[specification.child] = await launched.stdoutTail()
                stoppedStderrTails[specification.child] = await launched.stderrTail()
                await launched.stop()
            }
            guard !explicitStop else { return }
            eventContinuation.yield(.degraded(code: "child_restart_failed"))
            scheduleRestart(specification)
        }
    }

    @discardableResult
    private func stopOwnedChildren() async -> [RuntimeChild] {
        for task in observers.values { task.cancel() }
        observers.removeAll()
        let owned = Array(children)
        children.removeAll()
        var forciblyStoppedChildren: [RuntimeChild] = []
        for (runtimeChild, child) in owned {
            let wasRunning = await child.isRunning()
            let exitedGracefully = await child.stop()
            if wasRunning, !exitedGracefully { forciblyStoppedChildren.append(runtimeChild) }
        }
        engineClientValue = nil
        return forciblyStoppedChildren
    }

    private func preserveOutputTails() async {
        let current = Array(children)
        for (child, process) in current {
            stoppedStdoutTails[child] = await process.stdoutTail()
            stoppedStderrTails[child] = await process.stderrTail()
        }
    }
}
