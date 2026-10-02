import Foundation

public struct StartupAttemptToken: Equatable, Sendable {
    fileprivate let generation: UInt64

    fileprivate init(generation: UInt64) {
        self.generation = generation
    }
}

public struct MaintenanceTransition: Equatable, Sendable {
    fileprivate let id: UUID
    public let stopReport: ProcessSupervisorStopReport

    fileprivate init(id: UUID, stopReport: ProcessSupervisorStopReport) {
        self.id = id
        self.stopReport = stopReport
    }
}

public struct MaintenanceReservation: Equatable, Sendable {
    fileprivate let id: UUID

    fileprivate init(id: UUID) {
        self.id = id
    }
}

public enum StartupOwnershipError: Error, Equatable, Sendable {
    case terminalStopWon
    case maintenanceInProgress
    case staleStartupAttempt
    case staleMaintenanceTransition
}

/// Keeps the installation lock attached to one startup attempt across actor suspensions.
public actor StartupOwnership {
    private let lock: InstallationLock
    private var supervisor: ProcessSupervisor?
    private var stopped = false
    private var terminalStopRequested = false
    private var startupGeneration: UInt64 = 0
    private var stopReport: ProcessSupervisorStopReport?
    private var stopTask: Task<ProcessSupervisorStopReport, Never>?
    private var maintenanceTransitionID: UUID?
    private var maintenancePauseTask: Task<ProcessSupervisorStopReport, Never>?
    private var maintenanceWaiters: [CheckedContinuation<Void, Never>] = []
    private let onConcurrentStop: (@Sendable () async -> Void)?

    public init(lock: InstallationLock) {
        self.lock = lock
        self.onConcurrentStop = nil
    }

    init(lock: InstallationLock, onConcurrentStop: @escaping @Sendable () async -> Void) {
        self.lock = lock
        self.onConcurrentStop = onConcurrentStop
    }

    /// Starts a generation-bound startup attempt. A later start or maintenance transition
    /// invalidates this token before any suspended startup work can transfer ownership.
    public func beginStartupAttempt() throws -> StartupAttemptToken {
        guard !terminalStopRequested, !stopped else { throw StartupOwnershipError.terminalStopWon }
        guard maintenanceTransitionID == nil else { throw StartupOwnershipError.maintenanceInProgress }
        startupGeneration &+= 1
        return StartupAttemptToken(generation: startupGeneration)
    }

    /// Transfers a supervisor only while its startup attempt still owns the current generation.
    @discardableResult
    public func adopt(_ candidate: ProcessSupervisor, for attempt: StartupAttemptToken) async -> Bool {
        guard !terminalStopRequested, !stopped,
            maintenanceTransitionID == nil,
            attempt.generation == startupGeneration
        else {
            _ = await candidate.stop(retainingInstallationLock: true)
            return false
        }
        supervisor = candidate
        return true
    }

    /// Stops the current runtime while keeping the stable installation lock owned by this actor.
    /// Stop/Quit calls wait until the returned transition is finished.
    public func beginMaintenanceTransition() async throws -> MaintenanceTransition {
        let reservation = try await beginMaintenanceReservation()
        return try await beginMaintenanceTransition(using: reservation)
    }

    /// Reserves maintenance before durable preparation that still needs the live engine.
    /// Stop/Quit and suspended startup adoption wait until this reservation is finished.
    public func beginMaintenanceReservation() async throws -> MaintenanceReservation {
        guard !terminalStopRequested, !stopped else {
            if let stopTask { _ = await stopTask.value }
            throw StartupOwnershipError.terminalStopWon
        }
        guard maintenanceTransitionID == nil else {
            throw StartupOwnershipError.maintenanceInProgress
        }
        startupGeneration &+= 1
        let transitionID = UUID()
        maintenanceTransitionID = transitionID
        return MaintenanceReservation(id: transitionID)
    }

    /// Drains the old runtime after reservation work succeeds, retaining the same lock.
    public func beginMaintenanceTransition(
        using reservation: MaintenanceReservation
    ) async throws -> MaintenanceTransition {
        guard !stopped, maintenanceTransitionID == reservation.id else {
            throw StartupOwnershipError.staleMaintenanceTransition
        }
        let ownedSupervisor = supervisor
        supervisor = nil
        let task = Task.detached(priority: nil) { () -> ProcessSupervisorStopReport in
            let report: ProcessSupervisorStopReport
            if let ownedSupervisor {
                report = await ownedSupervisor.stop(retainingInstallationLock: true)
            } else {
                report = .noLiveEngine
            }
            return report
        }
        maintenancePauseTask = task
        let report = await task.value
        if maintenanceTransitionID == reservation.id {
            maintenancePauseTask = nil
        }
        return MaintenanceTransition(id: reservation.id, stopReport: report)
    }

    /// Builds a replacement supervisor attached to the lock retained throughout maintenance.
    public func makeSupervisor(
        configuration: ProcessSupervisorConfiguration,
        during transition: MaintenanceTransition
    ) throws -> ProcessSupervisor {
        guard !stopped, maintenanceTransitionID == transition.id else {
            throw StartupOwnershipError.staleMaintenanceTransition
        }
        return ProcessSupervisor(configuration: configuration, installationLock: lock)
    }

    /// Resolves the selected operational generation using the lock retained for maintenance.
    public func resolveActiveGeneration(
        from paths: RuntimePaths,
        during transition: MaintenanceTransition
    ) throws -> RuntimePaths {
        guard !stopped, maintenanceTransitionID == transition.id else {
            throw StartupOwnershipError.staleMaintenanceTransition
        }
        return try paths.resolveActiveGeneration(whileHolding: lock)
    }

    /// Switches the durable generation pointer while this owner retains the installation lock.
    public func switchActiveGeneration(
        from paths: RuntimePaths,
        to candidateID: String,
        expectedCurrentGeneration: String,
        during transition: MaintenanceTransition
    ) throws -> String {
        guard !stopped, maintenanceTransitionID == transition.id else {
            throw StartupOwnershipError.staleMaintenanceTransition
        }
        return try paths.switchActiveGeneration(
            to: candidateID,
            expectedCurrentGeneration: expectedCurrentGeneration,
            whileHolding: lock
        )
    }

    /// Drains a replacement generation while retaining the stable installation lock.
    public func stopReplacementForMaintenance(
        during transition: MaintenanceTransition
    ) async throws -> ProcessSupervisorStopReport {
        guard !stopped, maintenanceTransitionID == transition.id else {
            throw StartupOwnershipError.staleMaintenanceTransition
        }
        let ownedSupervisor = supervisor
        supervisor = nil
        let report: ProcessSupervisorStopReport
        if let ownedSupervisor {
            report = await ownedSupervisor.stop(retainingInstallationLock: true)
        } else {
            report = .noLiveEngine
        }
        return report
    }

    /// Transfers a replacement supervisor only to the currently active maintenance transition.
    @discardableResult
    public func adopt(_ candidate: ProcessSupervisor, during transition: MaintenanceTransition) async -> Bool {
        guard !stopped, maintenanceTransitionID == transition.id else {
            _ = await candidate.stop(retainingInstallationLock: true)
            return false
        }
        supervisor = candidate
        return true
    }

    /// Runs maintenance with guaranteed waiter release, including when the operation throws.
    public func withMaintenanceTransition<T: Sendable>(
        _ operation: @MainActor @Sendable (MaintenanceTransition) async throws -> T
    ) async throws -> T {
        try await withReservedMaintenanceTransition(
            prepare: { () },
            operation: { _, transition in try await operation(transition) }
        )
    }

    /// Serializes live-engine preparation, owned-runtime drain, and maintenance as one window.
    public func withReservedMaintenanceTransition<Prepared: Sendable, Result: Sendable>(
        prepare: @MainActor @Sendable () async throws -> Prepared,
        operation: @MainActor @Sendable (Prepared, MaintenanceTransition) async throws -> Result
    ) async throws -> Result {
        let reservation = try await beginMaintenanceReservation()
        var transition: MaintenanceTransition?
        do {
            let prepared = try await prepare()
            let started = try await beginMaintenanceTransition(using: reservation)
            transition = started
            let result = try await operation(prepared, started)
            await finishMaintenanceTransition(started)
            return result
        } catch {
            if let transition {
                await finishMaintenanceTransition(transition)
            } else {
                cancelMaintenanceReservation(reservation)
            }
            throw error
        }
    }

    /// Releases a reservation when live-engine preparation failed before the drain began.
    public func cancelMaintenanceReservation(_ reservation: MaintenanceReservation) {
        guard maintenanceTransitionID == reservation.id, maintenancePauseTask == nil else { return }
        maintenanceTransitionID = nil
        let waiters = maintenanceWaiters
        maintenanceWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }

    @discardableResult
    public func stop() async -> ProcessSupervisorStopReport {
        terminalStopRequested = true
        while maintenanceTransitionID != nil {
            await withCheckedContinuation { continuation in
                maintenanceWaiters.append(continuation)
                if let onConcurrentStop {
                    Task { await onConcurrentStop() }
                }
            }
        }
        if let stopTask {
            await onConcurrentStop?()
            return await stopTask.value
        }
        if stopped {
            let report = stopReport ?? .noLiveEngine
            await onConcurrentStop?()
            return report
        }

        stopped = true
        startupGeneration &+= 1
        let ownedSupervisor = supervisor
        supervisor = nil
        let ownedLock = lock
        let task = Task.detached(priority: nil) { () -> ProcessSupervisorStopReport in
            let report: ProcessSupervisorStopReport
            if let ownedSupervisor {
                report = await ownedSupervisor.stop()
            } else {
                report = .noLiveEngine
            }
            ownedLock.release()
            return report
        }
        stopTask = task
        let report = await task.value
        stopReport = report
        return report
    }

    /// Completes the matching maintenance window and lets waiting Stop or Quit calls run.
    public func finishMaintenanceTransition(_ transition: MaintenanceTransition) async {
        guard maintenanceTransitionID == transition.id else { return }
        if let maintenancePauseTask {
            _ = await maintenancePauseTask.value
        }
        maintenanceTransitionID = nil
        let waiters = maintenanceWaiters
        maintenanceWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }
}
