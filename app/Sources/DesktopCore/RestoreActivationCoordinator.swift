import Foundation

public protocol RestoreCandidateEngine: Sendable {
    func prepareRestoreCandidate(stagingID: String) async throws -> String
    func restoreCandidateStatus() async throws -> PendingRestoreCandidateView?
    func abortRestoreCandidate(candidateID: String) async throws
    func restorePreflight(
        candidateID: String, accounts: [RestorePreflightAccount]
    ) async throws -> RestorePreflightView
    func completeRestoreCandidate(candidateID: String, completionToken: String) async throws
}

extension EngineActions: RestoreCandidateEngine {}

public protocol RestoreGenerationOwnership: Actor {
    func withReservedMaintenanceTransition<Prepared: Sendable, Result: Sendable>(
        prepare: @MainActor @Sendable () async throws -> Prepared,
        operation: @MainActor @Sendable (Prepared, MaintenanceTransition) async throws -> Result
    ) async throws -> Result

    func resolveActiveGeneration(
        from paths: RuntimePaths,
        during transition: MaintenanceTransition
    ) throws -> RuntimePaths

    func switchActiveGeneration(
        from paths: RuntimePaths,
        to candidateID: String,
        expectedCurrentGeneration: String,
        during transition: MaintenanceTransition
    ) throws -> String
}

extension StartupOwnership: RestoreGenerationOwnership {}

public enum RestoreActivationError: Error, Equatable, LocalizedError, Sendable {
    case candidateUnavailable
    case candidateConflict
    case candidateInvalid
    case candidateStartFailed
    case credentialsUnavailable
    case previousGenerationChanged
    case previousEngineDrainUnconfirmed
    case preflightBlocked([String])
    case completionUnconfirmed
    case rollbackIncomplete

    public var errorDescription: String? {
        switch self {
        case .candidateUnavailable:
            "The durable restore candidate could not be verified."
        case .candidateConflict:
            "A different restore candidate is already waiting for recovery."
        case .candidateInvalid:
            "The restore candidate failed its durable identity or content checks."
        case .candidateStartFailed:
            "The restore candidate could not start in the expected gated state."
        case .credentialsUnavailable:
            "Saved broker credentials for this restore are unavailable."
        case .previousGenerationChanged:
            "The active operational generation changed before restore activation."
        case .previousEngineDrainUnconfirmed:
            "The running engine did not confirm a clean stop, so restore activation was blocked."
        case .preflightBlocked(let blockers):
            "Read-only broker reconciliation blocked activation: \(blockers.joined(separator: ", "))."
        case .completionUnconfirmed:
            "The restore completion state could not be confirmed."
        case .rollbackIncomplete:
            "Restore rollback is incomplete. The installation lock remains held while the app preserves durable state for recovery."
        }
    }
}

public struct RestoreActivationOutcome: Equatable, Sendable {
    public let candidateID: String
    public let previousGeneration: String
    public let blockers: [String]

    public init(candidateID: String, previousGeneration: String, blockers: [String]) {
        self.candidateID = candidateID
        self.previousGeneration = previousGeneration
        self.blockers = blockers
    }
}

/// Owns the restore transition policy while the app supplies runtime restart and UI state hooks.
public struct RestoreActivationCoordinator: Sendable {
    public typealias RuntimeStarter =
        @MainActor @Sendable (
            MaintenanceTransition
        ) async throws -> any RestoreCandidateEngine
    public typealias RuntimeStopper =
        @MainActor @Sendable (
            MaintenanceTransition
        ) async throws -> Void

    private let ownership: any RestoreGenerationOwnership
    private let stablePaths: RuntimePaths

    public init(ownership: any RestoreGenerationOwnership, stablePaths: RuntimePaths) {
        self.ownership = ownership
        self.stablePaths = stablePaths
    }

    public func activate(
        preview: RestorePreviewView?,
        knownPendingCandidateID: String?,
        expectedPreviousGeneration: String?,
        engine: any RestoreCandidateEngine,
        credentialStore: TradingConfigurationStore?,
        startRuntime: @escaping RuntimeStarter,
        stopRuntime: @escaping RuntimeStopper
    ) async throws -> RestoreActivationOutcome {
        try await ownership.withReservedMaintenanceTransition(
            prepare: {
                let existing = try await engine.restoreCandidateStatus()
                if let existing {
                    guard knownPendingCandidateID == existing.candidateID else {
                        throw RestoreActivationError.candidateConflict
                    }
                    return existing
                }
                guard let preview,
                    preview.matchesInstallation,
                    let expectedPreviousGeneration
                else {
                    throw RestoreActivationError.candidateUnavailable
                }

                var requestedCandidateID: String?
                do {
                    requestedCandidateID = try await engine.prepareRestoreCandidate(
                        stagingID: preview.stagingID
                    )
                    guard let pending = try await engine.restoreCandidateStatus(),
                        pending.candidateID == requestedCandidateID,
                        pending.previousGeneration == expectedPreviousGeneration
                    else {
                        throw RestoreActivationError.candidateUnavailable
                    }
                    return pending
                } catch {
                    // Preparation may have persisted its marker before the IPC reply was lost.
                    if let recovered = try? await engine.restoreCandidateStatus(),
                        requestedCandidateID == nil || recovered.candidateID == requestedCandidateID,
                        recovered.previousGeneration == expectedPreviousGeneration
                    {
                        return recovered
                    }
                    throw error
                }
            },
            operation: { [ownership, stablePaths] pending, transition in
                try await Self.activatePrepared(
                    pending,
                    expectedPreviousGeneration: expectedPreviousGeneration,
                    ownership: ownership,
                    stablePaths: stablePaths,
                    credentialStore: credentialStore,
                    transition: transition,
                    startRuntime: startRuntime,
                    stopRuntime: stopRuntime
                )
            }
        )
    }

    public func rollback(
        knownPendingCandidateID: String?,
        engine: (any RestoreCandidateEngine)?,
        startRuntime: @escaping RuntimeStarter,
        stopRuntime: @escaping RuntimeStopper
    ) async throws {
        try await ownership.withReservedMaintenanceTransition(
            prepare: { () async throws -> PendingRestoreCandidateView? in
                guard let engine else { return nil }
                guard let pending = try await engine.restoreCandidateStatus(),
                    knownPendingCandidateID == nil || knownPendingCandidateID == pending.candidateID
                else {
                    throw RestoreActivationError.candidateUnavailable
                }
                return pending
            },
            operation: { [ownership, stablePaths] (prepared: PendingRestoreCandidateView?, transition) in
                let pending: PendingRestoreCandidateView
                if let prepared {
                    pending = prepared
                } else {
                    let activeEngine = try await startRuntime(transition)
                    guard let recovered = try await activeEngine.restoreCandidateStatus(),
                        knownPendingCandidateID == nil
                            || knownPendingCandidateID == recovered.candidateID
                    else {
                        throw RestoreActivationError.candidateUnavailable
                    }
                    pending = recovered
                }
                try await Self.rollbackGatedCandidate(
                    pending,
                    ownership: ownership,
                    stablePaths: stablePaths,
                    transition: transition,
                    startRuntime: startRuntime,
                    stopRuntime: stopRuntime
                )
            }
        )
    }

    private static func activatePrepared(
        _ pending: PendingRestoreCandidateView,
        expectedPreviousGeneration: String?,
        ownership: any RestoreGenerationOwnership,
        stablePaths: RuntimePaths,
        credentialStore: TradingConfigurationStore?,
        transition: MaintenanceTransition,
        startRuntime: RuntimeStarter,
        stopRuntime: RuntimeStopper
    ) async throws -> RestoreActivationOutcome {
        guard pending.installationID == (try stablePaths.installationIdentity()),
            expectedPreviousGeneration == nil
                || expectedPreviousGeneration == pending.previousGeneration
        else {
            throw RestoreActivationError.previousGenerationChanged
        }

        var gateCleared = false
        do {
            guard
                transition.stopReport.engineDrainAcknowledgement == .acknowledged
                    || transition.stopReport.engineDrainAcknowledgement == .noLiveEngine
            else {
                throw RestoreActivationError.previousEngineDrainUnconfirmed
            }
            let selected = try await ownership.resolveActiveGeneration(
                from: stablePaths,
                during: transition
            )
            if selected.activeGenerationID == pending.previousGeneration {
                _ = try await ownership.switchActiveGeneration(
                    from: stablePaths,
                    to: pending.candidateID,
                    expectedCurrentGeneration: pending.previousGeneration,
                    during: transition
                )
            } else if selected.activeGenerationID != pending.candidateID {
                throw RestoreActivationError.previousGenerationChanged
            }
            guard pending.candidateValid else { throw RestoreActivationError.candidateInvalid }

            let candidateEngine = try await startRuntime(transition)
            guard let runningCandidate = try await candidateEngine.restoreCandidateStatus(),
                runningCandidate.candidateID == pending.candidateID,
                runningCandidate.activeGeneration == pending.candidateID,
                runningCandidate.candidateValid
            else {
                throw RestoreActivationError.candidateStartFailed
            }
            let accounts = try resolvePreflightAccounts(
                for: runningCandidate,
                stablePaths: stablePaths,
                credentialStore: credentialStore
            )
            let preflight = try await candidateEngine.restorePreflight(
                candidateID: pending.candidateID,
                accounts: accounts
            )
            guard preflight.candidateID == pending.candidateID else {
                throw RestoreActivationError.candidateInvalid
            }
            guard preflight.eligible, let completionToken = preflight.completionToken else {
                throw RestoreActivationError.preflightBlocked(preflight.blockers)
            }

            do {
                try await candidateEngine.completeRestoreCandidate(
                    candidateID: pending.candidateID,
                    completionToken: completionToken
                )
                gateCleared = true
            } catch {
                // Completion stops the gated process. Stop and inspect durable owner state under
                // the retained lock, then restart to distinguish a lost reply from a live gate.
                try await stopRuntime(transition)
                if try !stablePaths.restoreManualDisabledGateIsPresent() {
                    gateCleared = true
                    let restarted = try await startRuntime(transition)
                    guard try await restarted.restoreCandidateStatus() == nil else {
                        throw RestoreActivationError.completionUnconfirmed
                    }
                    return RestoreActivationOutcome(
                        candidateID: pending.candidateID,
                        previousGeneration: pending.previousGeneration,
                        blockers: []
                    )
                }
                let gatedRestart = try await startRuntime(transition)
                guard let durablePending = try await gatedRestart.restoreCandidateStatus(),
                    durablePending.candidateID == pending.candidateID
                else {
                    throw RestoreActivationError.completionUnconfirmed
                }
                throw RestoreActivationError.completionUnconfirmed
            }

            try await stopRuntime(transition)
            let writableCandidate = try await startRuntime(transition)
            guard try await writableCandidate.restoreCandidateStatus() == nil else {
                throw RestoreActivationError.candidateStartFailed
            }
            return RestoreActivationOutcome(
                candidateID: pending.candidateID,
                previousGeneration: pending.previousGeneration,
                blockers: []
            )
        } catch {
            do {
                if !gateCleared {
                    gateCleared = try !stablePaths.restoreManualDisabledGateIsPresent()
                }
                if gateCleared {
                    try await rollbackAfterGateClear(
                        pending,
                        ownership: ownership,
                        stablePaths: stablePaths,
                        transition: transition,
                        startRuntime: startRuntime,
                        stopRuntime: stopRuntime
                    )
                } else {
                    try await rollbackGatedCandidate(
                        pending,
                        ownership: ownership,
                        stablePaths: stablePaths,
                        transition: transition,
                        startRuntime: startRuntime,
                        stopRuntime: stopRuntime
                    )
                }
            } catch {
                throw RestoreActivationError.rollbackIncomplete
            }
            throw error
        }
    }

    private static func rollbackGatedCandidate(
        _ pending: PendingRestoreCandidateView,
        ownership: any RestoreGenerationOwnership,
        stablePaths: RuntimePaths,
        transition: MaintenanceTransition,
        startRuntime: RuntimeStarter,
        stopRuntime: RuntimeStopper
    ) async throws {
        try await stopRuntime(transition)
        let selected = try await ownership.resolveActiveGeneration(from: stablePaths, during: transition)
        if selected.activeGenerationID == pending.candidateID {
            _ = try await ownership.switchActiveGeneration(
                from: stablePaths,
                to: pending.previousGeneration,
                expectedCurrentGeneration: pending.candidateID,
                during: transition
            )
        } else if selected.activeGenerationID != pending.previousGeneration {
            throw RestoreActivationError.previousGenerationChanged
        }

        let gatedPrevious = try await startRuntime(transition)
        guard let durablePending = try await gatedPrevious.restoreCandidateStatus(),
            durablePending.candidateID == pending.candidateID,
            durablePending.activeGeneration == pending.previousGeneration
        else {
            throw RestoreActivationError.candidateUnavailable
        }
        do {
            try await gatedPrevious.abortRestoreCandidate(candidateID: pending.candidateID)
        } catch {
            // The engine clears the durable candidate before sending this reply. Under the
            // retained installation lock, resolve the gate and generation before treating
            // a lost reply as a completed abort.
            let gatePresent = try stablePaths.restoreManualDisabledGateIsPresent()
            let selectedAfterAbort = try await ownership.resolveActiveGeneration(
                from: stablePaths,
                during: transition
            )
            guard !gatePresent,
                selectedAfterAbort.activeGenerationID == pending.previousGeneration
            else {
                throw RestoreActivationError.rollbackIncomplete
            }
        }
        try await stopRuntime(transition)
        let writablePrevious = try await startRuntime(transition)
        guard try await writablePrevious.restoreCandidateStatus() == nil else {
            throw RestoreActivationError.rollbackIncomplete
        }
    }

    private static func rollbackAfterGateClear(
        _ pending: PendingRestoreCandidateView,
        ownership: any RestoreGenerationOwnership,
        stablePaths: RuntimePaths,
        transition: MaintenanceTransition,
        startRuntime: RuntimeStarter,
        stopRuntime: RuntimeStopper
    ) async throws {
        try await stopRuntime(transition)
        let selected = try await ownership.resolveActiveGeneration(from: stablePaths, during: transition)
        if selected.activeGenerationID == pending.candidateID {
            _ = try await ownership.switchActiveGeneration(
                from: stablePaths,
                to: pending.previousGeneration,
                expectedCurrentGeneration: pending.candidateID,
                during: transition
            )
        } else if selected.activeGenerationID != pending.previousGeneration {
            throw RestoreActivationError.previousGenerationChanged
        }
        let writablePrevious = try await startRuntime(transition)
        guard try await writablePrevious.restoreCandidateStatus() == nil else {
            throw RestoreActivationError.rollbackIncomplete
        }
    }

    private static func resolvePreflightAccounts(
        for pending: PendingRestoreCandidateView,
        stablePaths: RuntimePaths,
        credentialStore: TradingConfigurationStore?
    ) throws -> [RestorePreflightAccount] {
        guard pending.candidateValid,
            pending.installationID == (try stablePaths.installationIdentity())
        else {
            throw RestoreActivationError.candidateInvalid
        }
        let environments = try Dictionary(
            pending.environmentIDs.map { value -> (String, TradingEnvironment) in
                let parts = value.split(separator: ":", maxSplits: 1)
                guard parts.count == 2,
                    let environment = TradingEnvironment(rawValue: String(parts[0]))
                else {
                    throw RestoreActivationError.candidateInvalid
                }
                return (String(parts[1]), environment)
            },
            uniquingKeysWith: { first, _ in first }
        )
        guard Set(environments.keys) == Set(pending.accountIDs),
            environments.count == pending.environmentIDs.count
        else {
            throw RestoreActivationError.candidateInvalid
        }
        if pending.accountIDs.isEmpty {
            guard pending.credentialReferences.isEmpty else {
                throw RestoreActivationError.credentialsUnavailable
            }
            return []
        }
        guard pending.credentialReferences.count == 1,
            let reference = pending.credentialReferences.first,
            let credentialStore,
            let secrets = try credentialStore.loadCredentialRevision(reference)
        else {
            throw RestoreActivationError.credentialsUnavailable
        }
        var credentialsByAccount: [String: TradingBrokerCredentials] = [:]
        for credential in secrets.brokers {
            guard credentialsByAccount.updateValue(credential, forKey: credential.accountID) == nil else {
                throw RestoreActivationError.credentialsUnavailable
            }
        }
        guard Set(credentialsByAccount.keys) == Set(pending.accountIDs) else {
            throw RestoreActivationError.credentialsUnavailable
        }
        return try pending.accountIDs.sorted().map { accountID in
            guard let credential = credentialsByAccount[accountID],
                let environment = environments[accountID]
            else {
                throw RestoreActivationError.credentialsUnavailable
            }
            return RestorePreflightAccount(
                accountID: accountID,
                environment: environment,
                key: credential.key,
                secret: credential.secret
            )
        }
    }
}
