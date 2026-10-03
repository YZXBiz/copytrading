import CryptoKit
import Darwin
import Foundation

@testable import DesktopCore
import Testing

private enum UpdateTestFailure: Error {
    case expectedFailure(String)
    case unexpectedRequest(URL)
    case signatureRejected
    case injectedInstallFailure
    case injectedRestartFailure
    case artifactTampered
    case unexpectedProcess(String)
}

private actor UpdateFixtureTransport: UpdateTransport {
    let releaseData: Data
    let manifestData: Data
    let artifactData: Data
    var failArtifactDownload = false
    /// Files GitHub answers with 404, by last path component ("latest" for the release lookup).
    var missing: Set<String> = []
    private(set) var requests: [URL] = []

    init(releaseData: Data, manifestData: Data, artifactData: Data) {
        self.releaseData = releaseData
        self.manifestData = manifestData
        self.artifactData = artifactData
    }

    func setArtifactDownloadFailure() { failArtifactDownload = true }

    func setMissing(_ names: Set<String>) { missing = names }

    func get(_ url: URL, maximumBytes: Int) async throws -> Data {
        requests.append(url)
        if missing.contains(url.lastPathComponent) { throw UpdateServiceError.noPublishedRelease }
        if url.path.hasSuffix("/latest") { return releaseData }
        if url.lastPathComponent == "CopyTrading-macos-arm64.update.json" { return manifestData }
        if url.lastPathComponent == "CopyTrading-macos-arm64.pkg" {
            if failArtifactDownload { throw CancellationError() }
            return artifactData
        }
        throw UpdateTestFailure.unexpectedRequest(url)
    }

    func requestURLs() -> [URL] { requests }
}

private struct UpdateFixtureSignatureVerifier: UpdateSignatureVerifier {
    var shouldReject = false
    var actualProductVersion = "2.4.0"

    func verify(
        _ artifact: URL,
        expectedTeamIdentifier: String,
        expectedVersion: String
    ) async throws {
        guard !shouldReject, actualProductVersion == expectedVersion else {
            throw UpdateTestFailure.signatureRejected
        }
        guard expectedTeamIdentifier == "TEAM123456" else { throw UpdateTestFailure.signatureRejected }
        guard FileManager.default.fileExists(atPath: artifact.path) else { throw UpdateTestFailure.signatureRejected }
    }
}

private final class UpdateFixtureLifecycle: UpdateRuntimeLifecycle, @unchecked Sendable {
    var stopped = false
    var started = false
    var terminated = false
    var finishedRecoveryFailure = false
    var failRestart = false
    private var startAttempts = 0

    func stopForUpdate() async throws { stopped = true }
    func startAfterUpdate() async throws {
        startAttempts += 1
        if failRestart && startAttempts == 1 { throw UpdateTestFailure.injectedRestartFailure }
        started = true
    }
    func finishAfterRecoveryFailure() async { finishedRecoveryFailure = true }
    func terminateCurrentApplication() async { terminated = true }
}

private final class UpdateFixtureInstaller: UpdateBundleInstaller, @unchecked Sendable {
    var installed = false
    var launchedReplacement = false
    var rolledBack = false
    var failInstall = false
    var failLaunch = false
    var hasRecovery = false
    var matchesPendingVersion = false
    var confirmedStartup = false
    var relaunchedRestoredApplication = false

    func verify(_ staged: StagedUpdate) async throws {
        let data = try Data(contentsOf: staged.artifactURL)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard data.count == staged.release.manifest.size,
            digest == staged.release.manifest.sha256
        else {
            throw UpdateServiceError.artifactIntegrityFailed
        }
    }

    func install(_ staged: StagedUpdate) async throws {
        if failInstall { throw UpdateTestFailure.injectedInstallFailure }
        installed = true
        hasRecovery = true
    }
    func launchReplacementApplication() async throws {
        if failLaunch { throw UpdateTestFailure.injectedRestartFailure }
        launchedReplacement = true
    }
    func rollback() async throws {
        rolledBack = true
        installed = false
        hasRecovery = false
    }
    func confirmSuccessfulStartup() async throws {
        confirmedStartup = true
        hasRecovery = false
    }
    func relaunchRestoredApplication() async throws {
        rolledBack = true
        relaunchedRestoredApplication = true
        hasRecovery = false
    }
    func hasPendingRecovery() async throws -> Bool { hasRecovery }
    func currentApplicationMatchesPendingVersion() async throws -> Bool { matchesPendingVersion }
}

private actor UpdateFixtureStartOutcomes {
    private var outcomes: [UpdateRuntimeStartOutcome]
    private var count = 0

    init(_ outcomes: [UpdateRuntimeStartOutcome]) {
        self.outcomes = outcomes
    }

    func next() -> UpdateRuntimeStartOutcome {
        defer { count += 1 }
        return outcomes[min(count, outcomes.count - 1)]
    }
}

private actor UpdateFixtureTermination {
    private(set) var terminated = false
    func terminate() { terminated = true }
}

private actor UpdateFixtureProcessRunner: UpdateProcessRunning {
    private let failDittoAfterPartialCopy: Bool
    private var processCalls: [(String, [String])] = []

    init(failDittoAfterPartialCopy: Bool = false) {
        self.failDittoAfterPartialCopy = failDittoAfterPartialCopy
    }

    func run(_ executable: String, arguments: [String]) async throws -> UpdateProcessResult {
        processCalls.append((executable, arguments))
        switch executable {
        case "/usr/bin/ditto":
            guard arguments.count == 4,
                arguments[0] == "--rsrc",
                arguments[1] == "--extattr"
            else {
                throw UpdateTestFailure.unexpectedProcess(executable)
            }
            let source = URL(filePath: arguments[2])
            let destination = URL(filePath: arguments[3])
            if failDittoAfterPartialCopy {
                try FileManager.default.createDirectory(
                    at: destination.appending(path: "Contents", directoryHint: .isDirectory),
                    withIntermediateDirectories: true
                )
                throw UpdateTestFailure.injectedInstallFailure
            }
            try FileManager.default.copyItem(at: source, to: destination)
            return UpdateProcessResult(status: 0, output: "")
        case "/usr/bin/codesign":
            return UpdateProcessResult(status: 0, output: "TeamIdentifier=TEAM123456\n")
        case "/usr/sbin/spctl":
            return UpdateProcessResult(status: 0, output: "")
        default:
            throw UpdateTestFailure.unexpectedProcess(executable)
        }
    }

    func calls() -> [(String, [String])] { processCalls }
}

private struct UpdateFixturePackageExpander: UpdatePackageExpanding {
    let productVersion: String

    func expand(_ packageURL: URL, into destinationURL: URL) async throws {
        let productURL = destinationURL.appending(path: "Payload/CopyTrading.app", directoryHint: .isDirectory)
        try writeUpdateApplicationInfo(at: productURL, version: productVersion)
    }
}

private final class UpdateFixtureBundleFileOperations: UpdateBundleFileOperations, @unchecked Sendable {
    private let failFirstExchange: Bool
    private var exchangeCount = 0

    init(failFirstExchange: Bool = false) {
        self.failFirstExchange = failFirstExchange
    }

    func exchange(_ firstURL: URL, with secondURL: URL) throws {
        exchangeCount += 1
        if failFirstExchange && exchangeCount == 1 {
            throw UpdateInstallError.installationFailed
        }
        guard
            Darwin.renameatx_np(
                AT_FDCWD,
                firstURL.path,
                AT_FDCWD,
                secondURL.path,
                UInt32(RENAME_SWAP)
            ) == 0
        else {
            throw UpdateInstallError.recoveryRequired
        }
    }
}

private actor UpdateFixtureApplicationLauncher: UpdateApplicationLaunching {
    private var launchRequests: [(URL, Bool)] = []

    func launch(_ applicationURL: URL, waitForOwnerLock: Bool) async throws {
        launchRequests.append((applicationURL, waitForOwnerLock))
    }

    func requests() -> [(URL, Bool)] { launchRequests }
}

func runUpdateServiceTests() async throws {
    do {
        _ = try await UpdateService().latestRelease()
        throw UpdateTestFailure.expectedFailure("release lookup must fail closed without the installed schema")
    } catch let error as UpdateServiceError {
        try #require(
            error == .operationalSchemaUnavailable,
            "release lookup must not substitute a hardcoded compatibility schema")
    }

    let artifact = Data("signed package bytes".utf8)
    let digest = SHA256.hash(data: artifact).map { String(format: "%02x", $0) }.joined()
    let releaseData = Data(
        """
        {
          "tag_name": "v2.4.0",
          "body": "Security and reliability updates.",
          "assets": [
            {"name":"CopyTrading-macos-arm64.update.json","size":300,"browser_download_url":"https://github.com/YZXBiz/copytrading/releases/download/v2.4.0/CopyTrading-macos-arm64.update.json"},
            {"name":"CopyTrading-macos-arm64.pkg","size":20,"browser_download_url":"https://github.com/YZXBiz/copytrading/releases/download/v2.4.0/CopyTrading-macos-arm64.pkg"}
          ]
        }
        """.utf8)
    let manifestData = Data(
        """
        {"schema_version":1,"version":"2.4.0","platform":"macos","architecture":"arm64","minimum_os_version":"26.0","minimum_engine_schema":4,"maximum_engine_schema":4,"asset_name":"CopyTrading-macos-arm64.pkg","size":\(artifact.count),"sha256":"\(digest)"}
        """.utf8)

    let transport = UpdateFixtureTransport(releaseData: releaseData, manifestData: manifestData, artifactData: artifact)
    let service = UpdateService(
        transport: transport,
        signatureVerifier: UpdateFixtureSignatureVerifier(),
        publisherTeamIdentifier: "TEAM123456",
        currentVersion: "2.3.0",
        currentEngineSchema: 4,
        platform: "macos",
        architecture: "arm64"
    )
    let release = try await service.latestRelease()
    try #require(release.version == "2.4.0", "latest release version must come from the pinned GitHub project")

    await transport.setMissing(["latest"])
    do {
        _ = try await service.latestRelease()
        throw UpdateTestFailure.expectedFailure("a repository without releases must say so")
    } catch let error as UpdateServiceError {
        try #require(
            error == .noPublishedRelease,
            "a missing release must read as not published, not as an origin violation")
    }
    await transport.setMissing(["CopyTrading-macos-arm64.update.json"])
    do {
        _ = try await service.latestRelease()
        throw UpdateTestFailure.expectedFailure("a release without its manifest must be rejected")
    } catch let error as UpdateServiceError {
        try #require(error == .invalidRelease, "a missing manifest makes the release incomplete")
    }
    await transport.setMissing([])
    try #require(release.notes == "Security and reliability updates.", "release notes must be available to the native System UI")
    let requests = await transport.requestURLs()
    try #require(requests.allSatisfy { $0.scheme == "https" }, "release lookup must use HTTPS")
    try #require(
        requests.allSatisfy { $0.host == "api.github.com" || $0.host == "github.com" },
        "release lookup must stay on approved GitHub origins")
    try #require(requests.allSatisfy { $0.query == nil }, "release requests must not include account, activity, or credential parameters")

    let temporaryRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
        "update-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporaryRoot) }
    let supersededStage = try await service.stage(release, in: temporaryRoot)
    let staged = try await service.stage(release, in: temporaryRoot)
    try #require(
        FileManager.default.fileExists(atPath: supersededStage.artifactURL.path)
            && FileManager.default.fileExists(atPath: staged.artifactURL.path),
        "each verified download must have an independent generated staging directory"
    )
    try service.discard(supersededStage, in: temporaryRoot)
    try #require(
        !FileManager.default.fileExists(atPath: supersededStage.artifactURL.path)
            && FileManager.default.fileExists(atPath: staged.artifactURL.path),
        "discarding a superseded package must remove only its own generated directory"
    )
    try #require(FileManager.default.fileExists(atPath: staged.artifactURL.path), "verified update must be staged before any runtime stop")
    try #require(staged.publisherVerified, "staged update must carry publisher verification evidence")

    let pendingStage = try await service.stage(release, in: temporaryRoot)
    let pendingMarker = temporaryRoot.appending(path: "pending-update.json")
    try Data("pending".utf8).write(to: pendingMarker)
    var preservedPendingStage = true
    do {
        try service.discard(pendingStage, in: temporaryRoot)
        preservedPendingStage = false
    } catch {}
    try #require(
        preservedPendingStage
            && FileManager.default.fileExists(atPath: pendingStage.artifactURL.path),
        "staged evidence must remain while an update recovery marker is present"
    )
    try FileManager.default.removeItem(at: pendingMarker)
    try service.discard(pendingStage, in: temporaryRoot)
    try #require(
        !FileManager.default.fileExists(atPath: pendingStage.artifactURL.path),
        "a staged package may be removed after its update recovery marker is absent"
    )

    let mismatchedVersionService = UpdateService(
        transport: transport,
        signatureVerifier: UpdateFixtureSignatureVerifier(actualProductVersion: "2.3.9"),
        publisherTeamIdentifier: "TEAM123456",
        currentVersion: "2.3.0",
        currentEngineSchema: 4,
        platform: "macos",
        architecture: "arm64"
    )
    let mismatchedVersionDirectory = temporaryRoot.appending(path: "mismatched-version")
    try FileManager.default.createDirectory(at: mismatchedVersionDirectory, withIntermediateDirectories: true)
    try await verifyUpdateError(
        .signatureVerificationFailed,
        message: "a trusted package with a product version different from its release manifest must be rejected"
    ) {
        _ = try await mismatchedVersionService.stage(release, in: mismatchedVersionDirectory)
    }
    let mismatchedFiles = try FileManager.default.contentsOfDirectory(
        atPath: mismatchedVersionDirectory.path
    )
    try #require(mismatchedFiles.isEmpty, "a mislabeled package must leave no staged artifact")

    let rejectingService = UpdateService(
        transport: transport,
        signatureVerifier: UpdateFixtureSignatureVerifier(shouldReject: true),
        publisherTeamIdentifier: "TEAM123456",
        currentVersion: "2.3.0",
        currentEngineSchema: 4,
        platform: "macos",
        architecture: "arm64"
    )
    try await verifyUpdateError(.signatureVerificationFailed, message: "update staging must reject an untrusted publisher signature") {
        _ = try await rejectingService.stage(release, in: temporaryRoot)
    }

    let successfulLifecycle = UpdateFixtureLifecycle()
    let successfulInstaller = UpdateFixtureInstaller()
    let successfulCoordinator = UpdateInstallCoordinator(
        lifecycle: successfulLifecycle,
        installer: successfulInstaller
    )
    try await successfulCoordinator.install(staged)
    try #require(
        successfulInstaller.launchedReplacement,
        "a successful package install must launch the replacement application executable"
    )
    try #require(
        successfulLifecycle.terminated && !successfulLifecycle.started,
        "successful replacement must terminate the old UI instead of restarting its engine"
    )

    let tamperedURL = temporaryRoot.appending(path: "tampered.pkg")
    try Data("altered package bytes".utf8).write(to: tamperedURL)
    let tampered = StagedUpdate(
        release: staged.release,
        artifactURL: tamperedURL,
        publisherVerified: true,
        publisherTeamIdentifier: "TEAM123456"
    )
    var rejectedUnsafeCleanup = false
    do {
        try service.discard(tampered, in: temporaryRoot)
    } catch {
        rejectedUnsafeCleanup = true
    }
    try #require(
        rejectedUnsafeCleanup && FileManager.default.fileExists(atPath: tamperedURL.path),
        "cleanup must reject a package path outside the exact generated staging layout"
    )
    let tamperedLifecycle = UpdateFixtureLifecycle()
    let tamperedInstaller = UpdateFixtureInstaller()
    do {
        try await UpdateInstallCoordinator(
            lifecycle: tamperedLifecycle,
            installer: tamperedInstaller
        ).install(tampered)
        throw UpdateTestFailure.expectedFailure("a modified staged package must fail before installation")
    } catch let error as UpdateServiceError {
        try #require(error == .artifactIntegrityFailed, "a staged package change must be rejected by its original manifest hash")
    }
    try #require(
        !tamperedLifecycle.stopped && !tamperedInstaller.installed && !tamperedInstaller.launchedReplacement,
        "tampering must be rejected before runtime stop, installation, or replacement launch"
    )

    try await runMacOSUpdateInstallerTests(staged: staged, updateRoot: temporaryRoot)

    let downgrade = UpdateRelease(
        version: "2.2.0", notes: "old", manifest: release.manifest
    )
    try await verifyUpdateError(.downgrade, message: "update service must reject version downgrades") {
        _ = try await service.stage(downgrade, in: temporaryRoot)
    }

    let incompatibleManifest = UpdateReleaseManifest(
        schemaVersion: 1, version: "2.5.0", platform: "macos", architecture: "arm64",
        minimumOSVersion: "26.0", minimumEngineSchema: 3, maximumEngineSchema: 3, assetName: "CopyTrading-macos-arm64.pkg",
        size: artifact.count, sha256: digest, downloadURL: release.manifest.downloadURL
    )
    let incompatible = UpdateRelease(version: "2.5.0", notes: "schema mismatch", manifest: incompatibleManifest)
    try await verifyUpdateError(.incompatibleSchema, message: "update service must reject incompatible operational schemas") {
        _ = try await service.stage(incompatible, in: temporaryRoot)
    }

    let noTrust = UpdateService(
        transport: transport,
        signatureVerifier: UpdateFixtureSignatureVerifier(),
        publisherTeamIdentifier: nil,
        currentVersion: "2.3.0",
        currentEngineSchema: 4,
        platform: "macos",
        architecture: "arm64"
    )
    do {
        _ = try await noTrust.stage(release, in: temporaryRoot)
        throw UpdateTestFailure.expectedFailure("local install must fail without a configured Developer ID publisher identity")
    } catch let error as UpdateServiceError {
        try #require(error == .publisherIdentityUnavailable, "missing trust must name the concrete publisher identity prerequisite")
    }

    let cancellingTransport = UpdateFixtureTransport(releaseData: releaseData, manifestData: manifestData, artifactData: artifact)
    await cancellingTransport.setArtifactDownloadFailure()
    let cancellableService = UpdateService(
        transport: cancellingTransport,
        signatureVerifier: UpdateFixtureSignatureVerifier(),
        publisherTeamIdentifier: "TEAM123456",
        currentVersion: "2.3.0",
        currentEngineSchema: 4,
        platform: "macos",
        architecture: "arm64"
    )
    let cancelledDirectory = temporaryRoot.appendingPathComponent("cancelled", isDirectory: true)
    try FileManager.default.createDirectory(at: cancelledDirectory, withIntermediateDirectories: true)
    do {
        _ = try await cancellableService.stage(release, in: cancelledDirectory)
        throw UpdateTestFailure.expectedFailure("cancelled downloads must not become staged updates")
    } catch is CancellationError {}
    let cancelledFiles = try FileManager.default.contentsOfDirectory(atPath: cancelledDirectory.path)
    try #require(cancelledFiles.isEmpty, "cancelled download must remove partial staging files")

    let lifecycle = UpdateFixtureLifecycle()
    let installer = UpdateFixtureInstaller()
    installer.failLaunch = true
    let coordinator = UpdateInstallCoordinator(lifecycle: lifecycle, installer: installer)
    do {
        try await coordinator.install(staged)
        throw UpdateTestFailure.expectedFailure("restart failure must fail the update transition")
    } catch let error as UpdateInstallError {
        try #require(error == .rolledBack, "failed restart must expose successful rollback state")
    }
    try #require(
        lifecycle.stopped && lifecycle.started && !lifecycle.terminated,
        "replacement launch failure restarts the old runtime without terminating the current UI")
    try #require(
        installer.installed == false && installer.rolledBack,
        "replacement launch failure must restore the known-good bundle")

    try verifySignedPackageProductVersion()
    try await verifyRealPackageExpansionUsesAbsentDestination()
    try await runUpdateStartupRecoveryTests()
}

private func runUpdateStartupRecoveryTests() async throws {
    let recoveredInstaller = UpdateFixtureInstaller()
    recoveredInstaller.hasRecovery = true
    recoveredInstaller.matchesPendingVersion = true
    let delayedReady = UpdateFixtureStartOutcomes([.ownerLockBusy, .ownerLockBusy, .ready])
    let terminated = UpdateFixtureTermination()
    let recovered = try await UpdateStartupRecoveryCoordinator(
        installer: recoveredInstaller,
        maximumAttempts: 3,
        retryInterval: .milliseconds(1)
    ).recoverPendingUpdate(
        startRuntime: { await delayedReady.next() },
        terminateCurrentApplication: { await terminated.terminate() }
    )
    try #require(
        recovered && recoveredInstaller.confirmedStartup && !recoveredInstaller.hasRecovery,
        "a replacement is confirmed only after its runtime reports ready and then clears durable recovery evidence"
    )
    let healthyLeftTerminated = await terminated.terminated
    try #require(
        !healthyLeftTerminated,
        "a healthy replacement remains open after lock handoff"
    )

    let timedOutInstaller = UpdateFixtureInstaller()
    timedOutInstaller.hasRecovery = true
    timedOutInstaller.matchesPendingVersion = true
    let busyOutcomes = UpdateFixtureStartOutcomes([.ownerLockBusy, .ownerLockBusy])
    do {
        _ = try await UpdateStartupRecoveryCoordinator(
            installer: timedOutInstaller,
            maximumAttempts: 2,
            retryInterval: .milliseconds(1)
        ).recoverPendingUpdate(
            startRuntime: { await busyOutcomes.next() },
            terminateCurrentApplication: {}
        )
        throw UpdateTestFailure.expectedFailure("a replacement must not be called healthy from launcher acceptance alone")
    } catch let error as UpdateInstallError {
        try #require(error == .handoffTimedOut, "owner-lock handoff must use a bounded retry window")
    }
    try #require(
        timedOutInstaller.hasRecovery && !timedOutInstaller.confirmedStartup && !timedOutInstaller.rolledBack,
        "handoff timeout keeps the update marker and backup for the next launch"
    )

    let failedInstaller = UpdateFixtureInstaller()
    failedInstaller.hasRecovery = true
    failedInstaller.matchesPendingVersion = true
    let failedOutcome = UpdateFixtureStartOutcomes([.failed])
    let failedTermination = UpdateFixtureTermination()
    let failureWasRecovered = try await UpdateStartupRecoveryCoordinator(
        installer: failedInstaller,
        maximumAttempts: 1,
        retryInterval: .milliseconds(1)
    ).recoverPendingUpdate(
        startRuntime: { await failedOutcome.next() },
        terminateCurrentApplication: { await failedTermination.terminate() }
    )
    let failedInstanceTerminated = await failedTermination.terminated
    try #require(
        failureWasRecovered && failedInstaller.relaunchedRestoredApplication && failedInstanceTerminated,
        "failed replacement startup relaunches the restored application before terminating the failed instance"
    )
}

private func runMacOSUpdateInstallerTests(staged: StagedUpdate, updateRoot: URL) async throws {
    let applicationBundleURL =
        updateRoot
        .appending(path: "installed/CopyTrading.app", directoryHint: .isDirectory)
    try writeUpdateApplicationInfo(at: applicationBundleURL, version: "2.3.0")
    let packageExpander = UpdateFixturePackageExpander(productVersion: staged.release.version)
    let tamperedArtifactURL = updateRoot.appending(path: "tampered-CopyTrading.pkg")
    try Data("modified package".utf8).write(to: tamperedArtifactURL)
    let tamperedStaged = StagedUpdate(
        release: staged.release,
        artifactURL: tamperedArtifactURL,
        publisherVerified: true,
        publisherTeamIdentifier: staged.publisherTeamIdentifier
    )
    let tamperedProcessRunner = UpdateFixtureProcessRunner()
    let tamperedInstaller = MacOSUpdateBundleInstaller(
        applicationBundleURL: applicationBundleURL,
        updateRootURL: updateRoot,
        processRunner: tamperedProcessRunner,
        signatureVerifier: UpdateFixtureSignatureVerifier(),
        packageExpander: packageExpander,
        applicationLauncher: UpdateFixtureApplicationLauncher()
    )
    try await verifyUpdateError(
        .artifactIntegrityFailed,
        message: "the concrete installer must recheck staged bytes against the verified release manifest"
    ) {
        try await tamperedInstaller.verify(tamperedStaged)
    }
    let tamperedProcessCalls = await tamperedProcessRunner.calls()
    try #require(
        tamperedProcessCalls.isEmpty,
        "tampered bytes must not reach any system install or launch process"
    )

    let processRunner = UpdateFixtureProcessRunner()
    let launcher = UpdateFixtureApplicationLauncher()
    let installer = MacOSUpdateBundleInstaller(
        applicationBundleURL: applicationBundleURL,
        updateRootURL: updateRoot,
        processRunner: processRunner,
        signatureVerifier: UpdateFixtureSignatureVerifier(),
        packageExpander: packageExpander,
        applicationLauncher: launcher
    )

    do {
        try await installer.verify(staged)
    } catch {
        throw VerificationFailure(description: "concrete update verification failed before stop: \(error)")
    }
    do {
        try await installer.install(staged)
    } catch {
        let calls = await processRunner.calls()
        let siblings = try? FileManager.default.contentsOfDirectory(
            atPath: applicationBundleURL.deletingLastPathComponent().path
        )
        throw VerificationFailure(
            description:
                "concrete bundle replacement failed: \(String(describing: error)); calls=\(calls.map { $0.0 }); siblings=\(siblings ?? [])"
        )
    }
    let pendingAfterInstall = try await installer.hasPendingRecovery()
    try #require(pendingAfterInstall, "a replaced app must retain rollback evidence until the new runtime is healthy")
    let matchesPendingVersion = try await installer.currentApplicationMatchesPendingVersion()
    try #require(
        matchesPendingVersion,
        "the installed bundle version must match the release that was staged"
    )
    let siblingNames = try FileManager.default.contentsOfDirectory(
        atPath: applicationBundleURL.deletingLastPathComponent().path
    )
    let replacementSiblingName = siblingNames.first(where: { $0.contains("copytrading-update-replacement-") })
    try #require(
        FileManager.default.fileExists(atPath: applicationBundleURL.path),
        "atomic bundle exchange must keep the normal app launch path present")
    try #require(
        replacementSiblingName != nil,
        "the previous application must remain beside the selected bundle until startup health is confirmed")
    if let replacementSiblingName {
        let previousBundle = applicationBundleURL.deletingLastPathComponent()
            .appending(path: replacementSiblingName, directoryHint: .isDirectory)
        try #require(
            updateApplicationVersion(at: previousBundle) == "2.3.0",
            "the durable sibling path must hold the previous app until new runtime readiness"
        )
    }
    try await installer.launchReplacementApplication()

    let calls = await processRunner.calls()
    try #require(
        !calls.contains(where: { ["/usr/sbin/installer", "/bin/rm"].contains($0.0) }),
        "bundle replacement must not require a privileged system installer or delete-before-copy rollback"
    )
    let initialLaunchRequests = await launcher.requests()
    try #require(
        initialLaunchRequests.map(\.1) == [true],
        "replacement launch must create a fresh app instance that waits for the old installation lock"
    )

    let restartedInstaller = MacOSUpdateBundleInstaller(
        applicationBundleURL: applicationBundleURL,
        updateRootURL: updateRoot,
        processRunner: processRunner,
        signatureVerifier: UpdateFixtureSignatureVerifier(),
        packageExpander: packageExpander,
        applicationLauncher: launcher
    )
    let pendingAfterRestart = try await restartedInstaller.hasPendingRecovery()
    try #require(pendingAfterRestart, "pending update recovery must survive installer object/process replacement")
    try await restartedInstaller.relaunchRestoredApplication()
    let pendingAfterRollback = try await restartedInstaller.hasPendingRecovery()
    try #require(!pendingAfterRollback, "successful rollback must clear its durable recovery marker")
    try #require(
        FileManager.default.fileExists(atPath: staged.artifactURL.path),
        "rollback must retain the staged package so the operator can retry"
    )
    try #require(
        updateApplicationVersion(at: applicationBundleURL) == "2.3.0",
        "startup recovery must restore the previous application bundle"
    )
    let launchRequestsAfterRollback = await launcher.requests()
    try #require(
        launchRequestsAfterRollback.map(\.1) == [true, false],
        "recovery must launch the restored bundle without another update lock handoff"
    )

    let interruptedBundleURL =
        updateRoot
        .appending(path: "interrupted/CopyTrading.app", directoryHint: .isDirectory)
    try writeUpdateApplicationInfo(at: interruptedBundleURL, version: "2.3.0")
    let interruptedFiles = UpdateFixtureBundleFileOperations(failFirstExchange: true)
    let interruptedInstaller = MacOSUpdateBundleInstaller(
        applicationBundleURL: interruptedBundleURL,
        updateRootURL: updateRoot,
        processRunner: processRunner,
        signatureVerifier: UpdateFixtureSignatureVerifier(),
        packageExpander: packageExpander,
        applicationLauncher: UpdateFixtureApplicationLauncher(),
        bundleFiles: interruptedFiles
    )
    let interruptedLifecycle = UpdateFixtureLifecycle()
    do {
        try await UpdateInstallCoordinator(
            lifecycle: interruptedLifecycle,
            installer: interruptedInstaller
        ).install(staged)
        throw UpdateTestFailure.expectedFailure("an injected atomic exchange failure must roll back")
    } catch let error as UpdateInstallError {
        try #require(error == .rolledBack, "the durable marker must recover an interrupted atomic replacement")
    }
    try #require(
        updateApplicationVersion(at: interruptedBundleURL) == "2.3.0",
        "failed replacement must keep the old bundle launchable at its original path"
    )
    let interruptedMarkerRemains = try await interruptedInstaller.hasPendingRecovery()
    try #require(
        !interruptedMarkerRemains && interruptedLifecycle.started,
        "successful interrupted-install recovery clears its marker and restarts the existing runtime"
    )

    let partialBundleURL =
        updateRoot
        .appending(path: "partial/CopyTrading.app", directoryHint: .isDirectory)
    try writeUpdateApplicationInfo(at: partialBundleURL, version: "2.3.0")
    let partialInstaller = MacOSUpdateBundleInstaller(
        applicationBundleURL: partialBundleURL,
        updateRootURL: updateRoot,
        processRunner: UpdateFixtureProcessRunner(failDittoAfterPartialCopy: true),
        signatureVerifier: UpdateFixtureSignatureVerifier(),
        packageExpander: packageExpander,
        applicationLauncher: UpdateFixtureApplicationLauncher()
    )
    let partialLifecycle = UpdateFixtureLifecycle()
    do {
        try await UpdateInstallCoordinator(
            lifecycle: partialLifecycle,
            installer: partialInstaller
        ).install(staged)
        throw UpdateTestFailure.expectedFailure("a partial app copy must fail before bundle exchange")
    } catch let error as UpdateInstallError {
        try #require(error == .rolledBack, "an old app plus incomplete staged sibling must recover safely")
    }
    try #require(
        updateApplicationVersion(at: partialBundleURL) == "2.3.0",
        "a partial candidate copy must leave the old app available at its normal launch path"
    )
    let partialMarkerRemains = try await partialInstaller.hasPendingRecovery()
    try #require(
        !partialMarkerRemains,
        "recovering an incomplete candidate copy must clear the update marker"
    )

    let confirmationDirectory = updateRoot.appending(
        path: "update-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(
        at: confirmationDirectory,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: NSNumber(value: 0o700)]
    )
    let confirmationArtifactURL = confirmationDirectory.appending(path: "CopyTrading-macos-arm64.pkg")
    try FileManager.default.copyItem(at: staged.artifactURL, to: confirmationArtifactURL)
    let confirmationStage = StagedUpdate(
        release: staged.release,
        artifactURL: confirmationArtifactURL,
        publisherVerified: true,
        publisherTeamIdentifier: staged.publisherTeamIdentifier
    )
    let unrelatedFile = updateRoot.appending(path: "preserve-update-state.txt")
    try Data("keep".utf8).write(to: unrelatedFile)
    let confirmedBundleURL =
        updateRoot
        .appending(path: "confirmed/CopyTrading.app", directoryHint: .isDirectory)
    try writeUpdateApplicationInfo(at: confirmedBundleURL, version: "2.3.0")
    let confirmedInstaller = MacOSUpdateBundleInstaller(
        applicationBundleURL: confirmedBundleURL,
        updateRootURL: updateRoot,
        processRunner: UpdateFixtureProcessRunner(),
        signatureVerifier: UpdateFixtureSignatureVerifier(),
        packageExpander: packageExpander,
        applicationLauncher: UpdateFixtureApplicationLauncher()
    )
    try await confirmedInstaller.install(confirmationStage)
    try #require(
        FileManager.default.fileExists(atPath: confirmationArtifactURL.path),
        "the staged package must remain available while the replacement is awaiting readiness"
    )
    try await confirmedInstaller.confirmSuccessfulStartup()
    let confirmedRecoveryRemains = try await confirmedInstaller.hasPendingRecovery()
    try #require(
        !confirmedRecoveryRemains
            && !FileManager.default.fileExists(atPath: confirmationArtifactURL.path),
        "successful startup confirmation must clear recovery evidence and its consumed package"
    )
    try #require(
        FileManager.default.fileExists(atPath: staged.artifactURL.path)
            && FileManager.default.fileExists(atPath: unrelatedFile.path),
        "consumed-package cleanup must preserve unrelated and retryable staged data"
    )
}

private func verifyRealPackageExpansionUsesAbsentDestination() async throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "pkgutil-expansion-fixture-\(UUID().uuidString)", directoryHint: .isDirectory)
    let payloadURL = root.appending(path: "payload", directoryHint: .isDirectory)
    let packageURL = root.appending(path: "fixture.pkg")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    try FileManager.default.createDirectory(at: payloadURL, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    try writeUpdateApplicationInfo(
        at: payloadURL.appending(path: "CopyTrading.app", directoryHint: .isDirectory),
        version: "2.4.0"
    )

    let processRunner = SystemUpdateProcessRunner()
    let build = try await processRunner.run(
        "/usr/bin/pkgbuild",
        arguments: [
            "--root", payloadURL.path,
            "--identifier", "dev.copytrading.pkgutil-fixture",
            "--version", "2.4.0",
            "--install-location", "/Applications",
            packageURL.path,
        ]
    )
    try #require(build.status == 0, "pkgbuild must create the disposable package fixture")

    let workspace = try PackageExpansionWorkspace.create()
    defer { workspace.cleanup() }
    try #require(
        !FileManager.default.fileExists(atPath: workspace.expandedPackageURL.path),
        "pkgutil expansion must receive an absent destination path"
    )
    try await SystemUpdatePackageExpander(processRunner: processRunner).expand(
        packageURL,
        into: workspace.expandedPackageURL
    )
    let product = try SignedPackageProductVerifier.applicationBundle(
        in: workspace.expandedPackageURL,
        expectedVersion: "2.4.0"
    )
    try #require(
        product.lastPathComponent == "CopyTrading.app",
        "the real pkgutil output must contain the uniquely identified app product"
    )
}

private func writeUpdateApplicationInfo(at applicationURL: URL, version: String) throws {
    let infoURL = applicationURL.appending(path: "Contents/Info.plist")
    try FileManager.default.createDirectory(
        at: infoURL.deletingLastPathComponent(),
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: NSNumber(value: 0o700)]
    )
    let info: [String: Any] = [
        "CFBundleIdentifier": "dev.copytrading.app",
        "CFBundleShortVersionString": version,
    ]
    let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
    try data.write(to: infoURL)
}

private func updateApplicationVersion(at applicationURL: URL) -> String? {
    let infoURL = applicationURL.appending(path: "Contents/Info.plist")
    guard let data = try? Data(contentsOf: infoURL),
        let info = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
    else {
        return nil
    }
    return info["CFBundleShortVersionString"] as? String
}

private func verifySignedPackageProductVersion() throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "signed-package-version-\(UUID().uuidString)", directoryHint: .isDirectory)
    let infoURL = root.appending(path: "Payload/CopyTrading.app/Contents/Info.plist")
    try FileManager.default.createDirectory(
        at: infoURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let info: [String: Any] = [
        "CFBundleIdentifier": "dev.copytrading.app",
        "CFBundleShortVersionString": "2.4.0",
    ]
    let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
    try plist.write(to: infoURL)
    try SignedPackageProductVerifier.verifyProductVersion(in: root, expectedVersion: "2.4.0")
    try verifyThrows(
        { try SignedPackageProductVerifier.verifyProductVersion(in: root, expectedVersion: "2.4.1") },
        matching: { $0 as? UpdateServiceError == .signatureVerificationFailed },
        "signed product version mismatch must fail publisher verification"
    )

    let secondInfoURL = root.appending(path: "Payload/Second.app/Contents/Info.plist")
    try FileManager.default.createDirectory(
        at: secondInfoURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try plist.write(to: secondInfoURL)
    try verifyThrows(
        { try SignedPackageProductVerifier.verifyProductVersion(in: root, expectedVersion: "2.4.0") },
        matching: { $0 as? UpdateServiceError == .signatureVerificationFailed },
        "ambiguous signed product app identities must fail publisher verification"
    )

    try FileManager.default.removeItem(at: secondInfoURL.deletingLastPathComponent().deletingLastPathComponent())
    try FileManager.default.removeItem(at: infoURL)
    try verifyThrows(
        { try SignedPackageProductVerifier.verifyProductVersion(in: root, expectedVersion: "2.4.0") },
        matching: { $0 as? UpdateServiceError == .signatureVerificationFailed },
        "a signed package missing its product app must fail publisher verification"
    )
}

private func verifyUpdateError(
    _ expected: UpdateServiceError,
    message: String,
    operation: () async throws -> Void
) async throws {
    do {
        try await operation()
    } catch let error as UpdateServiceError {
        try #require(error == expected, Comment(rawValue: message))
        return
    }
    throw VerificationFailure(description: message)
}
