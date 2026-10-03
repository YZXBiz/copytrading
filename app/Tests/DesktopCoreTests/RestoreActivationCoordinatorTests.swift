import DesktopCore
import Foundation
import Testing

func runRestoreActivationCoordinatorTests() async throws {
    try await testRestoreActivationCompletesAfterLostReply()
    try await testRestoreActivationRollsBackBrokerBlocker()
    try await testRestoreRecoveryUsesRecordedPreviousGeneration()
    try await testRestoreRollbackCanReopenGatedEngine()
    try await testRestoreRollbackCompletesAfterLostAbortReply()
    try await testRestoreActivationRecoversLostPreparationReply()
    try await testRestoreActivationAbortsWhenPointerSwitchFails()
}

private func testRestoreActivationCompletesAfterLostReply() async throws {
    let fixture = try RestoreActivationFixture(
        activeCandidateOnStartup: false,
        preflightEligible: true,
        loseCompletionReply: true
    )
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let events = RestoreRuntimeEvents()
    let coordinator = RestoreActivationCoordinator(
        ownership: fixture.ownership,
        stablePaths: fixture.stablePaths
    )

    let outcome = try await coordinator.activate(
        preview: fixture.preview,
        knownPendingCandidateID: nil,
        expectedPreviousGeneration: fixture.previousGeneration,
        engine: fixture.engine,
        credentialStore: nil,
        startRuntime: fixture.starter(events),
        stopRuntime: fixture.stopper(events)
    )

    let selected = try fixture.stablePaths.resolveActiveGeneration(whileHolding: fixture.lock)
    try #require(
        outcome.candidateID == fixture.candidateID,
        "activation returned a different candidate after a lost completion reply")
    try #require(
        outcome.previousGeneration == fixture.previousGeneration,
        "activation lost the original generation after a lost completion reply")
    try #require(
        selected.activeGenerationID == fixture.candidateID,
        "activation did not retain the candidate generation after durable completion")
    let gatePresent = try fixture.stablePaths.restoreManualDisabledGateIsPresent()
    try #require(
        !gatePresent,
        "lost completion reply left a gate after durable completion")
    let pending = try await fixture.engine.restoreCandidateStatus()
    try #require(
        pending == nil,
        "writable candidate restart retained pending restore state")
    let starts = await events.starts
    let stops = await events.stops
    try #require(
        starts == 2 && stops == 1,
        "lost completion recovery did not stop and restart the candidate once")
    _ = await fixture.ownership.stop()
}

private func testRestoreActivationRollsBackBrokerBlocker() async throws {
    let fixture = try RestoreActivationFixture(
        activeCandidateOnStartup: false,
        preflightEligible: false,
        loseCompletionReply: false
    )
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let events = RestoreRuntimeEvents()
    let coordinator = RestoreActivationCoordinator(
        ownership: fixture.ownership,
        stablePaths: fixture.stablePaths
    )

    do {
        _ = try await coordinator.activate(
            preview: fixture.preview,
            knownPendingCandidateID: nil,
            expectedPreviousGeneration: fixture.previousGeneration,
            engine: fixture.engine,
            credentialStore: nil,
            startRuntime: fixture.starter(events),
            stopRuntime: fixture.stopper(events)
        )
        throw VerificationFailure(description: "broker blocker unexpectedly activated restore")
    } catch RestoreActivationError.preflightBlocked(let blockers) {
        try #require(
            blockers == ["broker_state_mismatch"],
            "preflight blockers were changed before returning to the app")
    }

    let selected = try fixture.stablePaths.resolveActiveGeneration(whileHolding: fixture.lock)
    try #require(
        selected.activeGenerationID == fixture.previousGeneration,
        "preflight rejection did not restore the original active generation")
    let gatePresent = try fixture.stablePaths.restoreManualDisabledGateIsPresent()
    try #require(
        !gatePresent,
        "preflight rollback did not clear the durable gate")
    let pending = try await fixture.engine.restoreCandidateStatus()
    try #require(
        pending == nil,
        "preflight rollback left a pending candidate intent")
    _ = await fixture.ownership.stop()
}

private func testRestoreRecoveryUsesRecordedPreviousGeneration() async throws {
    let fixture = try RestoreActivationFixture(
        activeCandidateOnStartup: true,
        preflightEligible: true,
        loseCompletionReply: false
    )
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let events = RestoreRuntimeEvents()
    let coordinator = RestoreActivationCoordinator(
        ownership: fixture.ownership,
        stablePaths: fixture.stablePaths
    )
    let outcome = try await coordinator.activate(
        preview: nil,
        knownPendingCandidateID: fixture.candidateID,
        expectedPreviousGeneration: nil,
        engine: fixture.engine,
        credentialStore: nil,
        startRuntime: fixture.starter(events),
        stopRuntime: fixture.stopper(events)
    )

    let selected = try fixture.stablePaths.resolveActiveGeneration(whileHolding: fixture.lock)
    try #require(
        outcome.previousGeneration == fixture.previousGeneration,
        "recovery replaced the intent's previous generation with the active candidate")
    try #require(
        selected.activeGenerationID == fixture.candidateID,
        "recovered candidate was not kept active after preflight completion")
    let gatePresent = try fixture.stablePaths.restoreManualDisabledGateIsPresent()
    try #require(
        !gatePresent,
        "recovered candidate remained gated after successful completion")
    _ = await fixture.ownership.stop()
}

private func testRestoreRollbackCanReopenGatedEngine() async throws {
    let fixture = try RestoreActivationFixture(
        activeCandidateOnStartup: true,
        preflightEligible: true,
        loseCompletionReply: false
    )
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let events = RestoreRuntimeEvents()
    let coordinator = RestoreActivationCoordinator(
        ownership: fixture.ownership,
        stablePaths: fixture.stablePaths
    )

    try await coordinator.rollback(
        knownPendingCandidateID: fixture.candidateID,
        engine: nil,
        startRuntime: fixture.starter(events),
        stopRuntime: fixture.stopper(events)
    )

    let selected = try fixture.stablePaths.resolveActiveGeneration(whileHolding: fixture.lock)
    try #require(
        selected.activeGenerationID == fixture.previousGeneration,
        "recovery could not roll back when the gated engine had not started")
    let gatePresent = try fixture.stablePaths.restoreManualDisabledGateIsPresent()
    try #require(!gatePresent, "recovery left the stable restore gate after rollback")
    let pending = try await fixture.engine.restoreCandidateStatus()
    try #require(pending == nil, "reopened gated engine did not clear its candidate after rollback")
    _ = await fixture.ownership.stop()
}

private func testRestoreRollbackCompletesAfterLostAbortReply() async throws {
    let fixture = try RestoreActivationFixture(
        activeCandidateOnStartup: true,
        preflightEligible: true,
        loseCompletionReply: false,
        loseAbortReply: true
    )
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let events = RestoreRuntimeEvents()
    let coordinator = RestoreActivationCoordinator(
        ownership: fixture.ownership,
        stablePaths: fixture.stablePaths
    )

    try await coordinator.rollback(
        knownPendingCandidateID: fixture.candidateID,
        engine: fixture.engine,
        startRuntime: fixture.starter(events),
        stopRuntime: fixture.stopper(events)
    )

    let selected = try fixture.stablePaths.resolveActiveGeneration(whileHolding: fixture.lock)
    let gatePresent = try fixture.stablePaths.restoreManualDisabledGateIsPresent()
    let pending = try await fixture.engine.restoreCandidateStatus()
    try #require(
        selected.activeGenerationID == fixture.previousGeneration,
        "lost abort reply changed the recovered previous generation")
    try #require(
        !gatePresent,
        "lost abort reply left the durable restore gate set")
    try #require(
        pending == nil,
        "lost abort reply did not restart a writable previous generation")
    let starts = await events.starts
    let stops = await events.stops
    try #require(
        starts == 2 && stops == 2,
        "lost abort reply did not finish the selected previous-generation restart")
    _ = await fixture.ownership.stop()
}

private func testRestoreActivationRecoversLostPreparationReply() async throws {
    let fixture = try RestoreActivationFixture(
        activeCandidateOnStartup: false,
        preflightEligible: true,
        loseCompletionReply: false,
        losePrepareReply: true
    )
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let events = RestoreRuntimeEvents()
    let coordinator = RestoreActivationCoordinator(
        ownership: fixture.ownership,
        stablePaths: fixture.stablePaths
    )

    let outcome = try await coordinator.activate(
        preview: fixture.preview,
        knownPendingCandidateID: nil,
        expectedPreviousGeneration: fixture.previousGeneration,
        engine: fixture.engine,
        credentialStore: nil,
        startRuntime: fixture.starter(events),
        stopRuntime: fixture.stopper(events)
    )

    try #require(
        outcome.candidateID == fixture.candidateID,
        "durable candidate was not recovered after preparation response loss")
    let gatePresent = try fixture.stablePaths.restoreManualDisabledGateIsPresent()
    try #require(!gatePresent, "recovered preparation did not finish the gated transition")
    _ = await fixture.ownership.stop()
}

private func testRestoreActivationAbortsWhenPointerSwitchFails() async throws {
    let fixture = try RestoreActivationFixture(
        activeCandidateOnStartup: false,
        preflightEligible: true,
        loseCompletionReply: false,
        publishCandidateDirectory: false
    )
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let events = RestoreRuntimeEvents()
    let coordinator = RestoreActivationCoordinator(
        ownership: fixture.ownership,
        stablePaths: fixture.stablePaths
    )

    do {
        _ = try await coordinator.activate(
            preview: fixture.preview,
            knownPendingCandidateID: nil,
            expectedPreviousGeneration: fixture.previousGeneration,
            engine: fixture.engine,
            credentialStore: nil,
            startRuntime: fixture.starter(events),
            stopRuntime: fixture.stopper(events)
        )
        throw VerificationFailure(description: "pointer switch failure unexpectedly activated restore")
    } catch let error as RuntimePathsError {
        try #require(
            error == .invalidGeneration,
            "pointer switch failure returned an unexpected error")
    }
    let selected = try fixture.stablePaths.resolveActiveGeneration(whileHolding: fixture.lock)
    try #require(
        selected.activeGenerationID == fixture.previousGeneration,
        "failed pointer switch changed the selected generation")
    let gatePresent = try fixture.stablePaths.restoreManualDisabledGateIsPresent()
    try #require(!gatePresent, "failed pointer switch left a durable gate after safe abort")
    _ = await fixture.ownership.stop()
}

private actor RestoreRuntimeEvents {
    private(set) var starts = 0
    private(set) var stops = 0

    func recordStart() { starts += 1 }
    func recordStop() { stops += 1 }
}

private actor FakeRestoreCandidateEngine: RestoreCandidateEngine {
    private let stablePaths: RuntimePaths
    private let installationID: String
    private let candidateID: String
    private let previousGeneration: String
    private let preflightEligible: Bool
    private let loseCompletionReply: Bool
    private let loseAbortReply: Bool
    private let losePrepareReply: Bool
    private let publishCandidateDirectory: Bool
    private var pending: PendingRestoreCandidateView?

    init(
        stablePaths: RuntimePaths,
        installationID: String,
        candidateID: String,
        previousGeneration: String,
        preflightEligible: Bool,
        loseCompletionReply: Bool,
        loseAbortReply: Bool = false,
        losePrepareReply: Bool,
        publishCandidateDirectory: Bool,
        pending: PendingRestoreCandidateView? = nil
    ) {
        self.stablePaths = stablePaths
        self.installationID = installationID
        self.candidateID = candidateID
        self.previousGeneration = previousGeneration
        self.preflightEligible = preflightEligible
        self.loseCompletionReply = loseCompletionReply
        self.loseAbortReply = loseAbortReply
        self.losePrepareReply = losePrepareReply
        self.publishCandidateDirectory = publishCandidateDirectory
        self.pending = pending
    }

    func prepareRestoreCandidate(stagingID: String) async throws -> String {
        if publishCandidateDirectory {
            try FileManager.default.createDirectory(
                at: stablePaths.generationsDirectory.appending(path: candidateID, directoryHint: .isDirectory),
                withIntermediateDirectories: true
            )
            try FileManager.default.setAttributes(
                [.posixPermissions: NSNumber(value: 0o700)],
                ofItemAtPath: stablePaths.generationsDirectory.appending(path: candidateID).path
            )
        }
        try Data("durable candidate gate".utf8).write(to: stablePaths.restoreManualDisabledURL)
        pending = PendingRestoreCandidateView(
            candidateID: candidateID,
            previousGeneration: previousGeneration,
            activeGeneration: previousGeneration,
            installationID: installationID,
            environmentIDs: [],
            accountIDs: [],
            credentialReferences: [],
            candidateValid: true
        )
        if losePrepareReply { throw RestorePreparationReplyLost() }
        return candidateID
    }

    func restoreCandidateStatus() async throws -> PendingRestoreCandidateView? { pending }

    func abortRestoreCandidate(candidateID: String) async throws {
        guard pending?.candidateID == candidateID else {
            throw RestoreActivationError.candidateUnavailable
        }
        try FileManager.default.removeItem(at: stablePaths.restoreManualDisabledURL)
        let candidate = stablePaths.generationsDirectory.appending(path: candidateID)
        if FileManager.default.fileExists(atPath: candidate.path) {
            try FileManager.default.removeItem(at: candidate)
        }
        pending = nil
        if loseAbortReply { throw RestoreAbortReplyLost() }
    }

    func restorePreflight(
        candidateID: String,
        accounts: [RestorePreflightAccount]
    ) async throws -> RestorePreflightView {
        RestorePreflightView(
            candidateID: candidateID,
            eligible: preflightEligible,
            checkedAccountCount: accounts.count,
            blockers: preflightEligible ? [] : ["broker_state_mismatch"],
            completionToken: preflightEligible ? "test-completion-token" : nil
        )
    }

    func completeRestoreCandidate(candidateID: String, completionToken: String) async throws {
        guard pending?.candidateID == candidateID, completionToken == "test-completion-token" else {
            throw RestoreActivationError.candidateUnavailable
        }
        try FileManager.default.removeItem(at: stablePaths.restoreManualDisabledURL)
        pending = nil
        if loseCompletionReply { throw RestoreCompletionReplyLost() }
    }

    func selectActiveGeneration(_ generation: String) {
        guard let pending else { return }
        self.pending = PendingRestoreCandidateView(
            candidateID: pending.candidateID,
            previousGeneration: pending.previousGeneration,
            activeGeneration: generation,
            installationID: pending.installationID,
            environmentIDs: pending.environmentIDs,
            accountIDs: pending.accountIDs,
            credentialReferences: pending.credentialReferences,
            candidateValid: pending.candidateValid
        )
    }
}

private struct RestoreCompletionReplyLost: Error {}
private struct RestoreAbortReplyLost: Error {}
private struct RestorePreparationReplyLost: Error {}

private struct RestoreActivationFixture {
    let root: URL
    let lock: InstallationLock
    let stablePaths: RuntimePaths
    let ownership: StartupOwnership
    let previousGeneration: String
    let candidateID: String
    let installationID: String
    let preview: RestorePreviewView
    let engine: FakeRestoreCandidateEngine

    init(
        activeCandidateOnStartup: Bool,
        preflightEligible: Bool,
        loseCompletionReply: Bool,
        loseAbortReply: Bool = false,
        losePrepareReply: Bool = false,
        publishCandidateDirectory: Bool = true
    ) throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "copytrading-restore-coordinator-\(UUID().uuidString)", directoryHint: .isDirectory)
        let rawPaths = RuntimePaths(
            applicationSupportDirectory: root,
            runtimeRoot: root.appending(path: "Runtime", directoryHint: .isDirectory),
            engineSourceRoot: root.appending(path: "Engine", directoryHint: .isDirectory)
        )
        installationID = try rawPaths.installationIdentity()
        lock = try rawPaths.acquireInstallationLock()
        let initial = try rawPaths.resolveActiveGeneration(whileHolding: lock)
        guard let activeGenerationID = initial.activeGenerationID else {
            throw VerificationFailure(description: "test fixture has no initial generation")
        }
        previousGeneration = activeGenerationID
        stablePaths = rawPaths
        candidateID = UUID().uuidString.lowercased()
        if activeCandidateOnStartup {
            try FileManager.default.createDirectory(
                at: stablePaths.generationsDirectory.appending(path: candidateID, directoryHint: .isDirectory),
                withIntermediateDirectories: true
            )
            try FileManager.default.setAttributes(
                [.posixPermissions: NSNumber(value: 0o700)],
                ofItemAtPath: stablePaths.generationsDirectory.appending(path: candidateID).path
            )
            try Data("durable candidate gate".utf8).write(to: stablePaths.restoreManualDisabledURL)
            _ = try rawPaths.switchActiveGeneration(
                to: candidateID,
                expectedCurrentGeneration: previousGeneration,
                whileHolding: lock
            )
        }
        ownership = StartupOwnership(lock: lock)
        preview = RestorePreviewView(
            formatVersion: 1,
            createdAt: "2026-09-27T00:00:00Z",
            installationID: installationID,
            matchesInstallation: true,
            environmentIDs: [],
            accountIDs: [],
            credentialReferences: [],
            stagingID: "test-staging-id",
            members: []
        )
        let pending =
            activeCandidateOnStartup
            ? PendingRestoreCandidateView(
                candidateID: candidateID,
                previousGeneration: previousGeneration,
                activeGeneration: candidateID,
                installationID: installationID,
                environmentIDs: [],
                accountIDs: [],
                credentialReferences: [],
                candidateValid: true
            )
            : nil
        engine = FakeRestoreCandidateEngine(
            stablePaths: stablePaths,
            installationID: installationID,
            candidateID: candidateID,
            previousGeneration: previousGeneration,
            preflightEligible: preflightEligible,
            loseCompletionReply: loseCompletionReply,
            loseAbortReply: loseAbortReply,
            losePrepareReply: losePrepareReply,
            publishCandidateDirectory: publishCandidateDirectory,
            pending: pending
        )
    }

    func starter(_ events: RestoreRuntimeEvents) -> RestoreActivationCoordinator.RuntimeStarter {
        { transition in
            let selected = try await ownership.resolveActiveGeneration(
                from: stablePaths,
                during: transition
            )
            if let generation = selected.activeGenerationID {
                await engine.selectActiveGeneration(generation)
            }
            await events.recordStart()
            return engine
        }
    }

    func stopper(_ events: RestoreRuntimeEvents) -> RestoreActivationCoordinator.RuntimeStopper {
        { _ in await events.recordStop() }
    }
}
