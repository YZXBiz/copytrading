import AppKit
import CryptoKit
import Darwin
import Foundation

struct UpdateProcessResult: Sendable {
    let status: Int32
    let output: String
}

protocol UpdateProcessRunning: Sendable {
    func run(_ executable: String, arguments: [String]) async throws -> UpdateProcessResult
}

protocol UpdatePackageExpanding: Sendable {
    func expand(_ packageURL: URL, into destinationURL: URL) async throws
}

struct PackageExpansionWorkspace: Sendable {
    let parentURL: URL
    let expandedPackageURL: URL

    static func create() throws -> Self {
        let parentURL = FileManager.default.temporaryDirectory
            .appending(path: "copytrading-package-\(UUID().uuidString)", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(
                at: parentURL,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: NSNumber(value: 0o700)]
            )
        } catch {
            throw UpdateInstallError.installationFailed
        }
        return Self(
            parentURL: parentURL,
            expandedPackageURL: parentURL.appending(path: "expanded", directoryHint: .isDirectory)
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: parentURL)
    }
}

protocol UpdateApplicationLaunching: Sendable {
    func launch(_ applicationURL: URL, waitForOwnerLock: Bool) async throws
}

protocol UpdateBundleFileOperations: Sendable {
    func exchange(_ firstURL: URL, with secondURL: URL) throws
}

struct SystemUpdateProcessRunner: UpdateProcessRunning {
    func run(_ executable: String, arguments: [String]) async throws -> UpdateProcessResult {
        try await Task.detached(priority: .utility) {
            let process = Process()
            let capturesOutput = executable == "/usr/bin/codesign"
            let output = capturesOutput ? Pipe() : nil
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = output ?? FileHandle.nullDevice
            process.standardError = output ?? FileHandle.nullDevice
            try process.run()
            let data = output?.fileHandleForReading.readDataToEndOfFile() ?? Data()
            process.waitUntilExit()
            return UpdateProcessResult(
                status: process.terminationStatus,
                output: String(decoding: data, as: UTF8.self)
            )
        }.value
    }
}

struct SystemUpdatePackageExpander: UpdatePackageExpanding {
    let processRunner: any UpdateProcessRunning

    func expand(_ packageURL: URL, into destinationURL: URL) async throws {
        guard !FileManager.default.fileExists(atPath: destinationURL.path) else {
            throw UpdateInstallError.installationFailed
        }
        let result = try await processRunner.run(
            "/usr/sbin/pkgutil",
            arguments: ["--expand-full", packageURL.path, destinationURL.path]
        )
        guard result.status == 0 else { throw UpdateInstallError.installationFailed }
    }
}

private struct SystemUpdateApplicationLauncher: UpdateApplicationLaunching {
    func launch(_ applicationURL: URL, waitForOwnerLock: Bool) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.arguments = waitForOwnerLock ? ["--copytrading-update-relaunch"] : []
        try await withCheckedThrowingContinuation { continuation in
            NSWorkspace.shared.openApplication(at: applicationURL, configuration: configuration) { app, error in
                if app != nil, error == nil {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: UpdateInstallError.replacementLaunchFailed)
                }
            }
        }
    }
}

private struct SystemUpdateBundleFileOperations: UpdateBundleFileOperations {
    func exchange(_ firstURL: URL, with secondURL: URL) throws {
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

private struct PendingUpdateRecovery: Codable, Equatable, Sendable {
    let applicationBundlePath: String
    let replacementBundlePath: String
    let previousVersion: String
    let expectedVersion: String
    let publisherTeamIdentifier: String
    let stagedArtifactPath: String?
}

private struct UpdateRecoveryStore: Sendable {
    private let rootURL: URL
    private let applicationBundleURL: URL
    private let markerURL: URL

    init(updateRootURL: URL, applicationBundleURL: URL) {
        rootURL = updateRootURL.standardizedFileURL
        self.applicationBundleURL = applicationBundleURL.standardizedFileURL
        markerURL = rootURL.appending(path: "pending-update.json")
    }

    func begin(_ record: PendingUpdateRecovery) throws {
        try ensurePrivateDirectory(rootURL)
        guard isAllowed(record), try pending() == nil else {
            throw UpdateInstallError.recoveryRequired
        }
        let data = try JSONEncoder().encode(record)
        guard data.count <= 8192 else { throw UpdateInstallError.recoveryRequired }
        let temporaryURL = rootURL.appending(path: ".pending-update-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        do {
            try data.write(to: temporaryURL, options: [.atomic])
        } catch {
            throw UpdateInstallError.recoveryRequired
        }
        guard Darwin.chmod(temporaryURL.path, mode_t(S_IRUSR | S_IWUSR)) == 0 else {
            throw UpdateInstallError.recoveryRequired
        }
        let fileDescriptor = Darwin.open(temporaryURL.path, O_RDONLY | O_NOFOLLOW)
        guard fileDescriptor >= 0 else { throw UpdateInstallError.recoveryRequired }
        let fileSyncStatus = Darwin.fsync(fileDescriptor)
        Darwin.close(fileDescriptor)
        guard fileSyncStatus == 0,
            Darwin.rename(temporaryURL.path, markerURL.path) == 0
        else {
            throw UpdateInstallError.recoveryRequired
        }
        try synchronizeDirectory(rootURL)
    }

    func pending() throws -> PendingUpdateRecovery? {
        try ensurePrivateDirectory(rootURL)
        var info = stat()
        guard Darwin.lstat(markerURL.path, &info) == 0 else {
            if errno == ENOENT { return nil }
            throw UpdateInstallError.recoveryRequired
        }
        guard (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
            info.st_uid == Darwin.getuid(),
            info.st_size > 0,
            info.st_size <= 8192,
            (info.st_mode & mode_t(S_IRWXG | S_IRWXO)) == 0
        else {
            throw UpdateInstallError.recoveryRequired
        }
        let record: PendingUpdateRecovery
        do {
            let data = try Data(contentsOf: markerURL, options: .mappedIfSafe)
            record = try JSONDecoder().decode(PendingUpdateRecovery.self, from: data)
        } catch {
            throw UpdateInstallError.recoveryRequired
        }
        guard isAllowed(record) else { throw UpdateInstallError.recoveryRequired }
        return record
    }

    func complete(_ record: PendingUpdateRecovery, cleanStagedArtifact: Bool = false) throws {
        guard try pending() == record else { throw UpdateInstallError.recoveryRequired }
        guard Darwin.unlink(markerURL.path) == 0 else { throw UpdateInstallError.recoveryRequired }
        try synchronizeDirectory(rootURL)
        removeGeneratedBundleIfPresent(at: URL(filePath: record.replacementBundlePath))
        if cleanStagedArtifact, let path = record.stagedArtifactPath {
            try? UpdateStagingArtifact.discard(URL(filePath: path), in: rootURL)
        }
    }

    private func isAllowed(_ record: PendingUpdateRecovery) -> Bool {
        let appURL = URL(filePath: record.applicationBundlePath).standardizedFileURL
        let replacementURL = URL(filePath: record.replacementBundlePath).standardizedFileURL
        let parentURL = applicationBundleURL.deletingLastPathComponent()
        let appName = applicationBundleURL.lastPathComponent
        let replacementPrefix = ".\(appName).copytrading-update-replacement-"
        let allowed =
            appURL.path == applicationBundleURL.path
            && appURL.pathExtension == "app"
            && replacementURL.deletingLastPathComponent().path == parentURL.path
            && replacementURL.lastPathComponent.hasPrefix(replacementPrefix)
            && replacementURL.pathExtension == "app"
            && (record.stagedArtifactPath.map {
                UpdateStagingArtifact.isGeneratedPath(URL(filePath: $0), in: rootURL)
            } ?? true)
            && !record.previousVersion.isEmpty
            && !record.expectedVersion.isEmpty
            && record.publisherTeamIdentifier.count == 10
            && record.publisherTeamIdentifier.allSatisfy {
                $0.isASCII && ($0.isUppercase || $0.isNumber)
            }
        return allowed
    }

    private func ensurePrivateDirectory(_ url: URL) throws {
        do {
            try FileManager.default.createDirectory(
                at: url,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: NSNumber(value: 0o700)]
            )
        } catch {
            throw UpdateInstallError.recoveryRequired
        }
        var info = stat()
        guard Darwin.lstat(url.path, &info) == 0,
            (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR),
            info.st_uid == Darwin.getuid(),
            Darwin.chmod(url.path, mode_t(S_IRWXU)) == 0
        else {
            throw UpdateInstallError.recoveryRequired
        }
    }

    private func synchronizeDirectory(_ url: URL) throws {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw UpdateInstallError.recoveryRequired }
        defer { Darwin.close(descriptor) }
        guard Darwin.fsync(descriptor) == 0 else { throw UpdateInstallError.recoveryRequired }
    }

    private func removeGeneratedBundleIfPresent(at url: URL) {
        var info = stat()
        guard Darwin.lstat(url.path, &info) == 0,
            (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR)
        else {
            return
        }
        try? FileManager.default.removeItem(at: url)
    }
}

/// Replaces only the app bundle containing the running executable. The transaction marker lives
/// in stable application support, while candidate and rollback bundles stay beside that app so
/// their renames are same-volume operations.
public struct MacOSUpdateBundleInstaller: UpdateBundleInstaller, Sendable {
    private let applicationBundleURL: URL
    private let updateRootURL: URL
    private let recoveryStore: UpdateRecoveryStore
    private let processRunner: any UpdateProcessRunning
    private let signatureVerifier: any UpdateSignatureVerifier
    private let packageExpander: any UpdatePackageExpanding
    private let applicationLauncher: any UpdateApplicationLaunching
    private let bundleFiles: any UpdateBundleFileOperations

    public init() {
        let stateRoot =
            ProcessInfo.processInfo.environment["COPYTRADING_STATE_ROOT"].map {
                URL(filePath: $0, directoryHint: .isDirectory)
            } ?? URL.applicationSupportDirectory.appending(path: "CopyTrading", directoryHint: .isDirectory)
        let processRunner = SystemUpdateProcessRunner()
        let applicationBundleURL = Bundle.main.bundleURL.standardizedFileURL
        let updateRootURL = stateRoot.appending(path: ".updates", directoryHint: .isDirectory)
        self.init(
            applicationBundleURL: applicationBundleURL,
            updateRootURL: updateRootURL,
            processRunner: processRunner,
            signatureVerifier: MacOSPackageSignatureVerifier(),
            packageExpander: SystemUpdatePackageExpander(processRunner: processRunner),
            applicationLauncher: SystemUpdateApplicationLauncher(),
            bundleFiles: SystemUpdateBundleFileOperations()
        )
    }

    init(
        applicationBundleURL: URL,
        updateRootURL: URL,
        processRunner: any UpdateProcessRunning,
        signatureVerifier: any UpdateSignatureVerifier,
        packageExpander: any UpdatePackageExpanding,
        applicationLauncher: any UpdateApplicationLaunching,
        bundleFiles: any UpdateBundleFileOperations = SystemUpdateBundleFileOperations()
    ) {
        self.applicationBundleURL = applicationBundleURL.standardizedFileURL
        self.updateRootURL = updateRootURL.standardizedFileURL
        recoveryStore = UpdateRecoveryStore(
            updateRootURL: updateRootURL,
            applicationBundleURL: applicationBundleURL
        )
        self.processRunner = processRunner
        self.signatureVerifier = signatureVerifier
        self.packageExpander = packageExpander
        self.applicationLauncher = applicationLauncher
        self.bundleFiles = bundleFiles
    }

    public func verify(_ staged: StagedUpdate) async throws {
        guard staged.publisherVerified,
            let teamIdentifier = staged.publisherTeamIdentifier,
            Self.validTeamIdentifier(teamIdentifier),
            staged.artifactURL.pathExtension == "pkg",
            staged.artifactURL.standardizedFileURL.path.hasPrefix(updateRootURL.path + "/")
        else {
            throw UpdateInstallError.unverifiedArtifact
        }
        try Self.ensurePrivateDirectory(updateRootURL)
        var info = stat()
        guard Darwin.lstat(staged.artifactURL.path, &info) == 0,
            (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
            info.st_uid == Darwin.getuid(),
            info.st_size == staged.release.manifest.size
        else {
            throw UpdateServiceError.artifactIntegrityFailed
        }
        let digest = try Self.sha256(at: staged.artifactURL)
        guard digest == staged.release.manifest.sha256.lowercased() else {
            throw UpdateServiceError.artifactIntegrityFailed
        }
        guard try recoveryStore.pending() == nil else {
            throw UpdateInstallError.recoveryRequired
        }
        try Self.probeWritableApplicationParent(applicationBundleURL)
        let installedVersion = Self.bundleVersion(at: applicationBundleURL)
        guard Self.bundleIdentifier(at: applicationBundleURL) == "dev.copytrading.app",
            let installedVersion
        else {
            throw UpdateInstallError.installationFailed
        }
        try await verifyBundle(
            at: applicationBundleURL,
            version: installedVersion,
            teamIdentifier: teamIdentifier
        )
        try await signatureVerifier.verify(
            staged.artifactURL,
            expectedTeamIdentifier: teamIdentifier,
            expectedVersion: staged.release.version
        )
    }

    public func install(_ staged: StagedUpdate) async throws {
        try await verify(staged)
        guard let teamIdentifier = staged.publisherTeamIdentifier,
            let previousVersion = Self.bundleVersion(at: applicationBundleURL),
            Self.bundleIdentifier(at: applicationBundleURL) == "dev.copytrading.app"
        else {
            throw UpdateInstallError.installationFailed
        }

        let parentURL = applicationBundleURL.deletingLastPathComponent()
        let token = UUID().uuidString
        let replacementURL = parentURL.appending(
            path: ".\(applicationBundleURL.lastPathComponent).copytrading-update-replacement-\(token).app",
            directoryHint: .isDirectory
        )
        guard !FileManager.default.fileExists(atPath: replacementURL.path) else {
            throw UpdateInstallError.installationFailed
        }
        let record = PendingUpdateRecovery(
            applicationBundlePath: applicationBundleURL.path,
            replacementBundlePath: replacementURL.path,
            previousVersion: previousVersion,
            expectedVersion: staged.release.version,
            publisherTeamIdentifier: teamIdentifier,
            stagedArtifactPath: staged.artifactURL.standardizedFileURL.path
        )

        let expansionWorkspace = try PackageExpansionWorkspace.create()
        defer { expansionWorkspace.cleanup() }

        do {
            try await packageExpander.expand(staged.artifactURL, into: expansionWorkspace.expandedPackageURL)
            let productURL = try SignedPackageProductVerifier.applicationBundle(
                in: expansionWorkspace.expandedPackageURL,
                expectedVersion: staged.release.version
            )
            try recoveryStore.begin(record)
            try await copyBundle(at: productURL, to: replacementURL)
            try await verifyBundle(
                at: replacementURL,
                version: staged.release.version,
                teamIdentifier: teamIdentifier
            )
            try bundleFiles.exchange(applicationBundleURL, with: replacementURL)
            try Self.synchronizeDirectory(parentURL)
            try await verifyBundle(
                at: applicationBundleURL,
                version: staged.release.version,
                teamIdentifier: teamIdentifier
            )
        } catch let error as UpdateInstallError {
            throw error
        } catch {
            throw UpdateInstallError.installationFailed
        }
    }

    public func launchReplacementApplication() async throws {
        guard let recovery = try recoveryStore.pending(),
            recovery.applicationBundlePath == applicationBundleURL.path,
            Self.bundleVersion(at: applicationBundleURL) == recovery.expectedVersion
        else {
            throw UpdateInstallError.recoveryRequired
        }
        try await verifyBundle(
            at: applicationBundleURL,
            version: recovery.expectedVersion,
            teamIdentifier: recovery.publisherTeamIdentifier
        )
        do {
            try await applicationLauncher.launch(applicationBundleURL, waitForOwnerLock: true)
        } catch {
            throw UpdateInstallError.replacementLaunchFailed
        }
    }

    public func rollback() async throws {
        guard let recovery = try recoveryStore.pending() else { return }
        guard recovery.applicationBundlePath == applicationBundleURL.path else {
            throw UpdateInstallError.recoveryRequired
        }
        let appVersion = Self.bundleVersion(at: applicationBundleURL)
        let replacementURL = URL(filePath: recovery.replacementBundlePath)
        let replacementVersion = Self.bundleVersion(at: replacementURL)
        let appExists = Self.isDirectory(at: applicationBundleURL)
        let replacementExists = Self.isDirectory(at: replacementURL)

        if appExists, appVersion == recovery.previousVersion {
            if replacementExists,
                let replacementVersion,
                replacementVersion != recovery.expectedVersion
            {
                throw UpdateInstallError.recoveryRequired
            }
            try await verifyBundle(
                at: applicationBundleURL,
                version: recovery.previousVersion,
                teamIdentifier: recovery.publisherTeamIdentifier
            )
            try recoveryStore.complete(recovery)
            return
        }

        if appExists,
            appVersion == recovery.expectedVersion,
            replacementExists,
            replacementVersion == recovery.previousVersion
        {
            try bundleFiles.exchange(applicationBundleURL, with: replacementURL)
            try Self.synchronizeDirectory(applicationBundleURL.deletingLastPathComponent())
        } else {
            throw UpdateInstallError.recoveryRequired
        }

        try await verifyBundle(
            at: applicationBundleURL,
            version: recovery.previousVersion,
            teamIdentifier: recovery.publisherTeamIdentifier
        )
        try recoveryStore.complete(recovery)
    }

    public func confirmSuccessfulStartup() async throws {
        guard let recovery = try recoveryStore.pending(),
            Self.bundleVersion(at: applicationBundleURL) == recovery.expectedVersion
        else {
            throw UpdateInstallError.recoveryRequired
        }
        try await verifyBundle(
            at: applicationBundleURL,
            version: recovery.expectedVersion,
            teamIdentifier: recovery.publisherTeamIdentifier
        )
        try recoveryStore.complete(recovery, cleanStagedArtifact: true)
    }

    public func relaunchRestoredApplication() async throws {
        try await rollback()
        do {
            try await applicationLauncher.launch(applicationBundleURL, waitForOwnerLock: false)
        } catch {
            throw UpdateInstallError.recoveryRequired
        }
    }

    public func hasPendingRecovery() async throws -> Bool {
        try recoveryStore.pending() != nil
    }

    public func currentApplicationMatchesPendingVersion() async throws -> Bool {
        guard let recovery = try recoveryStore.pending(),
            Self.bundleVersion(at: applicationBundleURL) == recovery.expectedVersion
        else {
            return false
        }
        try await verifyBundle(
            at: applicationBundleURL,
            version: recovery.expectedVersion,
            teamIdentifier: recovery.publisherTeamIdentifier
        )
        return true
    }

    private func copyBundle(at sourceURL: URL, to destinationURL: URL) async throws {
        let result = try await processRunner.run(
            "/usr/bin/ditto",
            arguments: ["--rsrc", "--extattr", sourceURL.path, destinationURL.path]
        )
        guard result.status == 0,
            Self.bundleIdentifier(at: destinationURL) == "dev.copytrading.app"
        else {
            throw UpdateInstallError.installationFailed
        }
    }

    private func verifyBundle(at bundleURL: URL, version: String, teamIdentifier: String) async throws {
        guard Self.bundleIdentifier(at: bundleURL) == "dev.copytrading.app",
            Self.bundleVersion(at: bundleURL) == version,
            Self.validTeamIdentifier(teamIdentifier)
        else {
            throw UpdateInstallError.installationFailed
        }
        let signature = try await processRunner.run(
            "/usr/bin/codesign",
            arguments: ["--verify", "--deep", "--strict", "--verbose=2", bundleURL.path]
        )
        guard signature.status == 0 else { throw UpdateServiceError.signatureVerificationFailed }
        let details = try await processRunner.run(
            "/usr/bin/codesign",
            arguments: ["-dv", "--verbose=4", bundleURL.path]
        )
        guard details.status == 0,
            details.output.contains("TeamIdentifier=\(teamIdentifier)")
        else {
            throw UpdateServiceError.signatureVerificationFailed
        }
        let assessment = try await processRunner.run(
            "/usr/sbin/spctl",
            arguments: ["--assess", "--type", "execute", "--verbose=4", bundleURL.path]
        )
        guard assessment.status == 0 else { throw UpdateServiceError.signatureVerificationFailed }
    }

    private static func bundleIdentifier(at url: URL) -> String? {
        bundleInfo(at: url)?["CFBundleIdentifier"] as? String
    }

    private static func bundleVersion(at url: URL) -> String? {
        bundleInfo(at: url)?["CFBundleShortVersionString"] as? String
    }

    private static func bundleInfo(at url: URL) -> [String: Any]? {
        let infoURL = url.appending(path: "Contents/Info.plist")
        guard let data = try? Data(contentsOf: infoURL),
            let value = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        else {
            return nil
        }
        return value as? [String: Any]
    }

    private static func isDirectory(at url: URL) -> Bool {
        var info = stat()
        return Darwin.lstat(url.path, &info) == 0
            && (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR)
    }

    private static func validTeamIdentifier(_ value: String) -> Bool {
        value.count == 10 && value.allSatisfy { $0.isASCII && ($0.isUppercase || $0.isNumber) }
    }

    private static func ensurePrivateDirectory(_ url: URL) throws {
        do {
            try FileManager.default.createDirectory(
                at: url,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: NSNumber(value: 0o700)]
            )
        } catch {
            throw UpdateInstallError.recoveryRequired
        }
        var info = stat()
        guard Darwin.lstat(url.path, &info) == 0,
            (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR),
            info.st_uid == Darwin.getuid(),
            Darwin.chmod(url.path, mode_t(S_IRWXU)) == 0
        else {
            throw UpdateInstallError.recoveryRequired
        }
    }

    private static func probeWritableApplicationParent(_ applicationURL: URL) throws {
        let parentURL = applicationURL.deletingLastPathComponent()
        guard isDirectory(at: parentURL) else { throw UpdateInstallError.installationFailed }
        let probeURL = parentURL.appending(path: ".copytrading-write-probe-\(UUID().uuidString)")
        let descriptor = Darwin.open(
            probeURL.path,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW,
            mode_t(S_IRUSR | S_IWUSR)
        )
        guard descriptor >= 0 else { throw UpdateInstallError.installationFailed }
        let syncStatus = Darwin.fsync(descriptor)
        Darwin.close(descriptor)
        guard syncStatus == 0, Darwin.unlink(probeURL.path) == 0 else {
            try? FileManager.default.removeItem(at: probeURL)
            throw UpdateInstallError.installationFailed
        }

        let firstURL = parentURL.appending(path: ".copytrading-swap-probe-a-\(UUID().uuidString)")
        let secondURL = parentURL.appending(path: ".copytrading-swap-probe-b-\(UUID().uuidString)")
        guard Darwin.mkdir(firstURL.path, mode_t(S_IRWXU)) == 0 else {
            throw UpdateInstallError.installationFailed
        }
        guard Darwin.mkdir(secondURL.path, mode_t(S_IRWXU)) == 0 else {
            try? FileManager.default.removeItem(at: firstURL)
            throw UpdateInstallError.installationFailed
        }
        let swapStatus = Darwin.renameatx_np(
            AT_FDCWD,
            firstURL.path,
            AT_FDCWD,
            secondURL.path,
            UInt32(RENAME_SWAP)
        )
        let firstIsDirectory = isDirectory(at: firstURL)
        let secondIsDirectory = isDirectory(at: secondURL)
        try? FileManager.default.removeItem(at: firstURL)
        try? FileManager.default.removeItem(at: secondURL)
        guard swapStatus == 0, firstIsDirectory, secondIsDirectory else {
            throw UpdateInstallError.installationFailed
        }
        try synchronizeDirectory(parentURL)
    }

    private static func synchronizeDirectory(_ url: URL) throws {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw UpdateInstallError.recoveryRequired }
        defer { Darwin.close(descriptor) }
        guard Darwin.fsync(descriptor) == 0 else { throw UpdateInstallError.recoveryRequired }
    }

    private static func sha256(at url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 64 * 1024), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
