import CryptoKit
import Darwin
import Foundation

public struct UpdateReleaseManifest: Sendable, Equatable {
    public let schemaVersion: Int
    public let version: String
    public let platform: String
    public let architecture: String
    public let minimumOSVersion: String
    public let minimumEngineSchema: Int
    public let maximumEngineSchema: Int
    public let assetName: String
    public let size: Int
    public let sha256: String
    public let downloadURL: URL

    public init(
        schemaVersion: Int,
        version: String,
        platform: String,
        architecture: String,
        minimumOSVersion: String,
        minimumEngineSchema: Int,
        maximumEngineSchema: Int,
        assetName: String,
        size: Int,
        sha256: String,
        downloadURL: URL
    ) {
        self.schemaVersion = schemaVersion
        self.version = version
        self.platform = platform
        self.architecture = architecture
        self.minimumOSVersion = minimumOSVersion
        self.minimumEngineSchema = minimumEngineSchema
        self.maximumEngineSchema = maximumEngineSchema
        self.assetName = assetName
        self.size = size
        self.sha256 = sha256
        self.downloadURL = downloadURL
    }
}

public struct UpdateRelease: Sendable, Equatable {
    public let version: String
    public let notes: String
    public let manifest: UpdateReleaseManifest

    public init(version: String, notes: String, manifest: UpdateReleaseManifest) {
        self.version = version
        self.notes = notes
        self.manifest = manifest
    }
}

public struct StagedUpdate: Sendable, Equatable {
    public let release: UpdateRelease
    public let artifactURL: URL
    public let publisherVerified: Bool
    public let publisherTeamIdentifier: String?

    init(
        release: UpdateRelease,
        artifactURL: URL,
        publisherVerified: Bool,
        publisherTeamIdentifier: String?
    ) {
        self.release = release
        self.artifactURL = artifactURL
        self.publisherVerified = publisherVerified
        self.publisherTeamIdentifier = publisherTeamIdentifier
    }
}

public enum UpdateServiceError: Error, Equatable, LocalizedError, Sendable {
    case invalidRelease
    case operationalSchemaUnavailable
    case unsupportedPlatform
    case incompatibleSchema
    case downgrade
    case publisherIdentityUnavailable
    case artifactIntegrityFailed
    case signatureVerificationFailed
    case downloadTooLarge
    case transportRejected
    case noPublishedRelease
    case releaseServiceUnavailable
    case invalidStagingPath
    case updateRecoveryPending
    case stagingCleanupFailed

    public var errorDescription: String? {
        switch self {
        case .invalidRelease:
            "The GitHub release metadata is invalid or incomplete."
        case .operationalSchemaUnavailable:
            "The active operational database schema could not be read safely. Start CopyTrading and try again."
        case .unsupportedPlatform:
            "This release does not support the current macOS version and Apple Silicon architecture."
        case .incompatibleSchema:
            "This release does not support the installed operational data schema."
        case .downgrade:
            "Installing an older CopyTrading version is not supported."
        case .publisherIdentityUnavailable:
            "Installation is unavailable because this build has no pinned Developer ID publisher identity. A maintainer must provision and publish a notarized Developer ID release before installation can be enabled."
        case .artifactIntegrityFailed:
            "The downloaded update does not match the release manifest."
        case .signatureVerificationFailed:
            "The update did not pass the pinned publisher signature and notarization checks."
        case .downloadTooLarge:
            "The release response exceeds the configured size limit."
        case .transportRejected:
            "The release request was not served from an approved HTTPS GitHub origin."
        case .noPublishedRelease:
            "No CopyTrading release has been published on GitHub yet."
        case .releaseServiceUnavailable:
            "GitHub did not answer the release request. Try again later."
        case .invalidStagingPath:
            "The staged update is not stored in a valid app-managed update directory."
        case .updateRecoveryPending:
            "The staged update is retained while an update transaction is being recovered."
        case .stagingCleanupFailed:
            "The staged update could not be safely removed."
        }
    }
}

enum UpdateStagingArtifact {
    static let packageName = "CopyTrading-macos-arm64.pkg"
    static let recoveryMarkerName = "pending-update.json"

    static func isGeneratedPath(_ artifactURL: URL, in stagingRoot: URL) -> Bool {
        let root = stagingRoot.standardizedFileURL
        let artifact = artifactURL.standardizedFileURL
        let directory = artifact.deletingLastPathComponent()
        let directoryName = directory.lastPathComponent
        let prefix = "update-"
        guard artifact.lastPathComponent == packageName,
            directory.deletingLastPathComponent().path == root.path,
            directoryName.hasPrefix(prefix)
        else {
            return false
        }
        let identifier = String(directoryName.dropFirst(prefix.count))
        return UUID(uuidString: identifier)?.uuidString == identifier
    }

    static func ensureNoPendingRecovery(in stagingRoot: URL) throws {
        let root = stagingRoot.standardizedFileURL
        var rootInfo = stat()
        let rootStatus = Darwin.lstat(root.path, &rootInfo)
        if rootStatus != 0 {
            guard errno == ENOENT else { throw UpdateServiceError.invalidStagingPath }
            return
        }
        guard (rootInfo.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR),
            rootInfo.st_uid == Darwin.getuid()
        else {
            throw UpdateServiceError.invalidStagingPath
        }

        let markerURL = root.appending(path: recoveryMarkerName)
        var markerInfo = stat()
        if Darwin.lstat(markerURL.path, &markerInfo) == 0 {
            throw UpdateServiceError.updateRecoveryPending
        }
        guard errno == ENOENT else { throw UpdateServiceError.invalidStagingPath }
    }

    static func discard(_ artifactURL: URL, in stagingRoot: URL) throws {
        let root = stagingRoot.standardizedFileURL
        let artifact = artifactURL.standardizedFileURL
        guard isGeneratedPath(artifact, in: root) else {
            throw UpdateServiceError.invalidStagingPath
        }
        try ensureNoPendingRecovery(in: root)

        var rootInfo = stat()
        guard Darwin.lstat(root.path, &rootInfo) == 0 else {
            if errno == ENOENT { return }
            throw UpdateServiceError.invalidStagingPath
        }
        let directory = artifact.deletingLastPathComponent()
        var directoryInfo = stat()
        guard Darwin.lstat(directory.path, &directoryInfo) == 0 else {
            if errno == ENOENT { return }
            throw UpdateServiceError.invalidStagingPath
        }
        guard (directoryInfo.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR),
            directoryInfo.st_uid == Darwin.getuid(),
            (directoryInfo.st_mode & mode_t(S_IRWXG | S_IRWXO)) == 0
        else {
            throw UpdateServiceError.invalidStagingPath
        }

        var artifactInfo = stat()
        guard Darwin.lstat(artifact.path, &artifactInfo) == 0 else {
            if errno == ENOENT { return }
            throw UpdateServiceError.invalidStagingPath
        }
        guard (artifactInfo.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
            artifactInfo.st_uid == Darwin.getuid()
        else {
            throw UpdateServiceError.invalidStagingPath
        }

        let contents: [String]
        do {
            contents = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        } catch {
            throw UpdateServiceError.invalidStagingPath
        }
        guard contents == [packageName] else { throw UpdateServiceError.invalidStagingPath }
        do {
            try FileManager.default.removeItem(at: directory)
        } catch {
            throw UpdateServiceError.stagingCleanupFailed
        }

        let descriptor = Darwin.open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw UpdateServiceError.stagingCleanupFailed }
        defer { Darwin.close(descriptor) }
        guard Darwin.fsync(descriptor) == 0 else { throw UpdateServiceError.stagingCleanupFailed }
    }
}

protocol UpdateTransport: Sendable {
    func get(_ url: URL, maximumBytes: Int) async throws -> Data
}

protocol UpdateSignatureVerifier: Sendable {
    func verify(
        _ artifact: URL,
        expectedTeamIdentifier: String,
        expectedVersion: String
    ) async throws
}

public protocol UpdateRuntimeLifecycle: Sendable {
    func stopForUpdate() async throws
    func startAfterUpdate() async throws
    func finishAfterRecoveryFailure() async
    func terminateCurrentApplication() async
}

public protocol UpdateBundleInstaller: Sendable {
    func verify(_ staged: StagedUpdate) async throws
    func install(_ staged: StagedUpdate) async throws
    func launchReplacementApplication() async throws
    func rollback() async throws
    func confirmSuccessfulStartup() async throws
    func relaunchRestoredApplication() async throws
    func hasPendingRecovery() async throws -> Bool
    func currentApplicationMatchesPendingVersion() async throws -> Bool
}

public enum UpdateInstallError: Error, Equatable, LocalizedError, Sendable {
    case unverifiedArtifact
    case installationFailed
    case replacementLaunchFailed
    case handoffTimedOut
    case rolledBack
    case recoveryRequired

    public var errorDescription: String? {
        switch self {
        case .unverifiedArtifact: "The update has no verified publisher identity."
        case .installationFailed: "The signed update could not replace the installed application."
        case .replacementLaunchFailed: "The replacement application could not be launched. The previous application was restored."
        case .handoffTimedOut:
            "The replacement application is still waiting for the current installation to close. Its rollback copy is retained for recovery."
        case .rolledBack: "The update could not start, so the previous application bundle was restored."
        case .recoveryRequired:
            "The update failed and automatic rollback could not restore the previous application. Open the original application bundle and contact support."
        }
    }
}

public struct UpdateInstallCoordinator: Sendable {
    private let lifecycle: any UpdateRuntimeLifecycle
    private let installer: any UpdateBundleInstaller

    public init(lifecycle: any UpdateRuntimeLifecycle, installer: any UpdateBundleInstaller) {
        self.lifecycle = lifecycle
        self.installer = installer
    }

    public func install(_ staged: StagedUpdate) async throws {
        guard staged.publisherVerified,
            staged.publisherTeamIdentifier != nil,
            staged.artifactURL.pathExtension == "pkg",
            FileManager.default.fileExists(atPath: staged.artifactURL.path)
        else { throw UpdateInstallError.unverifiedArtifact }
        try await installer.verify(staged)
        try await lifecycle.stopForUpdate()
        do {
            try await installer.install(staged)
            try await installer.launchReplacementApplication()
        } catch {
            do {
                try await installer.rollback()
                try await lifecycle.startAfterUpdate()
            } catch {
                await lifecycle.finishAfterRecoveryFailure()
                throw UpdateInstallError.recoveryRequired
            }
            throw UpdateInstallError.rolledBack
        }
        await lifecycle.terminateCurrentApplication()
    }
}

public enum UpdateRuntimeStartOutcome: Sendable, Equatable {
    case ready
    case ownerLockBusy
    case failed
}

public struct UpdateStartupRecoveryCoordinator: Sendable {
    private let installer: any UpdateBundleInstaller
    private let maximumAttempts: Int
    private let retryInterval: Duration

    public init(
        installer: any UpdateBundleInstaller,
        maximumAttempts: Int = 80,
        retryInterval: Duration = .milliseconds(500)
    ) {
        self.installer = installer
        self.maximumAttempts = max(1, maximumAttempts)
        self.retryInterval = retryInterval
    }

    /// Resolves the durable app-replacement marker before normal startup. A lock timeout keeps
    /// the marker and backup intact so a later launch can retry safely.
    public func recoverPendingUpdate(
        startRuntime: @escaping @Sendable () async -> UpdateRuntimeStartOutcome,
        terminateCurrentApplication: @escaping @Sendable () async -> Void
    ) async throws -> Bool {
        guard try await installer.hasPendingRecovery() else { return false }
        let candidateMatches: Bool
        do {
            candidateMatches = try await installer.currentApplicationMatchesPendingVersion()
        } catch {
            try await installer.rollback()
            return false
        }
        guard candidateMatches else {
            try await installer.rollback()
            return false
        }
        for attempt in 0..<maximumAttempts {
            switch await startRuntime() {
            case .ready:
                try await installer.confirmSuccessfulStartup()
                return true
            case .ownerLockBusy:
                guard attempt + 1 < maximumAttempts else { throw UpdateInstallError.handoffTimedOut }
                try await Task.sleep(for: retryInterval)
            case .failed:
                try await installer.relaunchRestoredApplication()
                await terminateCurrentApplication()
                return true
            }
        }
        throw UpdateInstallError.handoffTimedOut
    }
}

public struct UpdateService: Sendable {
    private static let apiURL = URL(string: "https://api.github.com/repos/YZXBiz/copytrading/releases/latest")!
    private static let manifestName = "CopyTrading-macos-arm64.update.json"
    private static let artifactName = "CopyTrading-macos-arm64.pkg"
    private static let maxReleaseBytes = 2 * 1024 * 1024
    private static let maxManifestBytes = 64 * 1024
    private static let maxArtifactBytes = 512 * 1024 * 1024

    private let transport: any UpdateTransport
    private let signatureVerifier: any UpdateSignatureVerifier
    private let publisherTeamIdentifier: String?
    private let currentVersion: String
    private let currentEngineSchema: Int?
    private let platform: String
    private let architecture: String
    private let currentOSVersion: String

    init(
        transport: any UpdateTransport,
        signatureVerifier: any UpdateSignatureVerifier,
        publisherTeamIdentifier: String?,
        currentVersion: String,
        currentEngineSchema: Int,
        platform: String,
        architecture: String,
        currentOSVersion: String = ProcessInfo.processInfo.operatingSystemVersionString
    ) {
        self.transport = transport
        self.signatureVerifier = signatureVerifier
        self.publisherTeamIdentifier = publisherTeamIdentifier
        self.currentVersion = currentVersion
        self.currentEngineSchema = currentEngineSchema
        self.platform = platform
        self.architecture = architecture
        self.currentOSVersion = Self.normalizedOSVersion(currentOSVersion)
    }

    public init() {
        let info = Bundle.main.infoDictionary ?? [:]
        currentVersion = info["CFBundleShortVersionString"] as? String ?? "0.0.0"
        currentEngineSchema = nil
        platform = "macos"
        architecture = Self.currentArchitecture
        currentOSVersion = Self.normalizedOSVersion(ProcessInfo.processInfo.operatingSystemVersionString)
        transport = GitHubUpdateTransport()
        signatureVerifier = MacOSPackageSignatureVerifier()
        // A pinned Developer ID Team ID must be added only after the publisher provisions it.
        publisherTeamIdentifier = nil
    }

    /// A missing manifest or artifact means the release is incomplete, not that none exists.
    private static func releaseFile(
        _ transport: any UpdateTransport, _ url: URL, maximumBytes: Int
    ) async throws -> Data {
        do {
            return try await transport.get(url, maximumBytes: maximumBytes)
        } catch UpdateServiceError.noPublishedRelease {
            throw UpdateServiceError.invalidRelease
        }
    }

    public func latestRelease() async throws -> UpdateRelease {
        guard let currentEngineSchema else { throw UpdateServiceError.operationalSchemaUnavailable }
        return try await latestRelease(currentEngineSchema: currentEngineSchema)
    }

    public func latestRelease(currentEngineSchema: Int) async throws -> UpdateRelease {
        let releaseData = try await transport.get(Self.apiURL, maximumBytes: Self.maxReleaseBytes)
        guard releaseData.count <= Self.maxReleaseBytes else { throw UpdateServiceError.downloadTooLarge }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let releaseResponse: GitHubReleaseResponse
        do {
            releaseResponse = try decoder.decode(GitHubReleaseResponse.self, from: releaseData)
        } catch {
            throw UpdateServiceError.invalidRelease
        }
        guard let version = Self.normalizedVersion(releaseResponse.tagName),
            Self.releaseVersionComponents(version) != nil,
            (releaseResponse.body ?? "").utf8.count <= 64 * 1024,
            releaseResponse.assets.count <= 100
        else { throw UpdateServiceError.invalidRelease }

        let manifestAssets = releaseResponse.assets.filter { $0.name == Self.manifestName }
        let artifactAssets = releaseResponse.assets.filter { $0.name == Self.artifactName }
        guard manifestAssets.count == 1,
            artifactAssets.count == 1,
            manifestAssets[0].size > 0,
            manifestAssets[0].size <= Self.maxManifestBytes,
            artifactAssets[0].size > 0,
            artifactAssets[0].size <= Self.maxArtifactBytes,
            Self.isApprovedReleaseURL(manifestAssets[0].browserDownloadUrl, filename: Self.manifestName),
            Self.isApprovedReleaseURL(artifactAssets[0].browserDownloadUrl, filename: Self.artifactName)
        else { throw UpdateServiceError.invalidRelease }

        let manifestData = try await Self.releaseFile(
            transport,
            manifestAssets[0].browserDownloadUrl,
            maximumBytes: Self.maxManifestBytes
        )
        guard manifestData.count <= Self.maxManifestBytes else { throw UpdateServiceError.downloadTooLarge }
        let manifest: GitHubUpdateManifest
        do {
            manifest = try decoder.decode(GitHubUpdateManifest.self, from: manifestData)
        } catch {
            throw UpdateServiceError.invalidRelease
        }
        let parsed = UpdateReleaseManifest(
            schemaVersion: manifest.schemaVersion,
            version: manifest.version,
            platform: manifest.platform,
            architecture: manifest.architecture,
            minimumOSVersion: manifest.minimumOsVersion,
            minimumEngineSchema: manifest.minimumEngineSchema,
            maximumEngineSchema: manifest.maximumEngineSchema,
            assetName: manifest.assetName,
            size: manifest.size,
            sha256: manifest.sha256.lowercased(),
            downloadURL: artifactAssets[0].browserDownloadUrl
        )
        let release = UpdateRelease(version: version, notes: releaseResponse.body ?? "", manifest: parsed)
        try validate(release, currentEngineSchema: currentEngineSchema)
        guard artifactAssets[0].size == parsed.size else { throw UpdateServiceError.invalidRelease }
        return release
    }

    public func stage(_ release: UpdateRelease, in stagingRoot: URL) async throws -> StagedUpdate {
        guard let currentEngineSchema else { throw UpdateServiceError.operationalSchemaUnavailable }
        return try await stage(release, in: stagingRoot, currentEngineSchema: currentEngineSchema)
    }

    /// Removes one package that this service staged in the supplied app-managed update root.
    /// Pending replacement transactions retain their package until startup confirmation.
    public func discard(_ staged: StagedUpdate, in stagingRoot: URL) throws {
        guard staged.release.manifest.assetName == Self.artifactName else {
            throw UpdateServiceError.invalidStagingPath
        }
        try UpdateStagingArtifact.discard(staged.artifactURL, in: stagingRoot)
    }

    public func stage(
        _ release: UpdateRelease,
        in stagingRoot: URL,
        currentEngineSchema: Int
    ) async throws -> StagedUpdate {
        try validate(release, currentEngineSchema: currentEngineSchema)
        try UpdateStagingArtifact.ensureNoPendingRecovery(in: stagingRoot)
        guard let teamIdentifier = publisherTeamIdentifier,
            teamIdentifier.count == 10,
            teamIdentifier.allSatisfy({ $0.isASCII && ($0.isUppercase || $0.isNumber) })
        else { throw UpdateServiceError.publisherIdentityUnavailable }
        guard release.manifest.size <= Self.maxArtifactBytes else { throw UpdateServiceError.downloadTooLarge }

        let directory = stagingRoot.appending(path: "update-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: 0o700)]
        )
        var retainDirectory = false
        defer {
            if !retainDirectory { try? FileManager.default.removeItem(at: directory) }
        }
        let partialURL = directory.appending(path: "CopyTrading-macos-arm64.partial.pkg")
        let stagedURL = directory.appending(path: Self.artifactName)
        try Task.checkCancellation()
        let artifact = try await Self.releaseFile(
            transport, release.manifest.downloadURL, maximumBytes: Self.maxArtifactBytes
        )
        try Task.checkCancellation()
        guard artifact.count == release.manifest.size,
            Self.sha256(artifact) == release.manifest.sha256.lowercased()
        else { throw UpdateServiceError.artifactIntegrityFailed }
        try artifact.write(to: partialURL, options: [.atomic])
        do {
            try await signatureVerifier.verify(
                partialURL,
                expectedTeamIdentifier: teamIdentifier,
                expectedVersion: release.version
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw UpdateServiceError.signatureVerificationFailed
        }
        try Task.checkCancellation()
        try FileManager.default.moveItem(at: partialURL, to: stagedURL)
        retainDirectory = true
        return StagedUpdate(
            release: release,
            artifactURL: stagedURL,
            publisherVerified: true,
            publisherTeamIdentifier: teamIdentifier
        )
    }

    private func validate(_ release: UpdateRelease, currentEngineSchema: Int) throws {
        guard let current = Self.releaseVersionComponents(currentVersion),
            let requested = Self.releaseVersionComponents(release.version),
            let manifestVersion = Self.releaseVersionComponents(release.manifest.version),
            requested == manifestVersion,
            Self.isVersion(requested, greaterThan: current)
        else { throw UpdateServiceError.downgrade }
        let manifest = release.manifest
        guard manifest.schemaVersion == 1,
            manifest.platform == platform,
            manifest.architecture == architecture,
            manifest.assetName == Self.artifactName,
            Self.isApprovedReleaseURL(manifest.downloadURL, filename: Self.artifactName),
            manifest.minimumEngineSchema > 0,
            manifest.maximumEngineSchema >= manifest.minimumEngineSchema,
            (manifest.minimumEngineSchema...manifest.maximumEngineSchema).contains(currentEngineSchema),
            Self.versionComponents(manifest.minimumOSVersion) != nil,
            let osVersion = Self.versionComponents(currentOSVersion),
            let minimumOS = Self.versionComponents(manifest.minimumOSVersion),
            Self.isVersion(osVersion, atLeast: minimumOS)
        else {
            if manifest.platform != platform || manifest.architecture != architecture
                || Self.versionComponents(manifest.minimumOSVersion).map({ minimum in
                    Self.versionComponents(currentOSVersion).map { !Self.isVersion($0, atLeast: minimum) } ?? true
                }) == true
            {
                throw UpdateServiceError.unsupportedPlatform
            }
            throw UpdateServiceError.incompatibleSchema
        }
        guard manifest.size > 0,
            manifest.size <= Self.maxArtifactBytes,
            manifest.sha256.count == 64,
            manifest.sha256.allSatisfy(\.isHexDigit),
            !release.notes.contains("\0")
        else { throw UpdateServiceError.invalidRelease }
    }

    private static func normalizedVersion(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("v") ? String(trimmed.dropFirst()) : trimmed
    }

    private static func versionComponents(_ value: String) -> [Int]? {
        let normalized = normalizedVersion(value) ?? ""
        let parts = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3,
            parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) })
        else { return nil }
        let components = parts.compactMap { Int($0) }
        guard components.count == parts.count else { return nil }
        return components.count == 2 ? components + [0] : components
    }

    private static func releaseVersionComponents(_ value: String) -> [Int]? {
        guard (normalizedVersion(value) ?? "").split(separator: ".", omittingEmptySubsequences: false).count == 3 else {
            return nil
        }
        return versionComponents(value)
    }

    private static func isVersion(_ left: [Int], greaterThan right: [Int]) -> Bool {
        for (lhs, rhs) in zip(left, right) where lhs != rhs { return lhs > rhs }
        return false
    }

    private static func isVersion(_ left: [Int], atLeast right: [Int]) -> Bool {
        left == right || isVersion(left, greaterThan: right)
    }

    private static func normalizedOSVersion(_ value: String) -> String {
        let numeric = value.split(whereSeparator: { !$0.isNumber && $0 != "." }).first.map(String.init) ?? value
        let parts = numeric.split(separator: ".")
        guard !parts.isEmpty else { return "0.0.0" }
        return (Array(parts.prefix(3)) + Array(repeating: Substring("0"), count: max(0, 3 - parts.count))).joined(separator: ".")
    }

    private static func isApprovedReleaseURL(_ url: URL, filename: String) -> Bool {
        url.scheme == "https"
            && url.host == "github.com"
            && url.port == nil
            && url.user == nil
            && url.password == nil
            && url.path.hasPrefix("/YZXBiz/copytrading/releases/download/")
            && url.lastPathComponent == filename
            && url.query == nil
            && url.fragment == nil
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static var currentArchitecture: String {
        #if arch(arm64)
            "arm64"
        #elseif arch(x86_64)
            "x86_64"
        #else
            "unknown"
        #endif
    }
}

private struct GitHubReleaseResponse: Decodable {
    let tagName: String
    let body: String?
    let assets: [GitHubReleaseAsset]
}

private struct GitHubReleaseAsset: Decodable {
    let name: String
    let size: Int
    let browserDownloadUrl: URL
}

private struct GitHubUpdateManifest: Decodable {
    let schemaVersion: Int
    let version: String
    let platform: String
    let architecture: String
    let minimumOsVersion: String
    let minimumEngineSchema: Int
    let maximumEngineSchema: Int
    let assetName: String
    let size: Int
    let sha256: String
}

private struct GitHubUpdateTransport: UpdateTransport {
    func get(_ url: URL, maximumBytes: Int) async throws -> Data {
        guard URLSessionUpdateRequest.isApproved(url),
            maximumBytes > 0,
            maximumBytes <= 512 * 1024 * 1024
        else { throw UpdateServiceError.transportRejected }
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 120)
        return try await URLSessionUpdateRequest(request: request, maximumBytes: maximumBytes).fetch()
    }
}

private final class URLSessionUpdateRequest: NSObject, URLSessionDataDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    private static let approvedHosts: Set<String> = [
        "api.github.com", "github.com", "release-assets.githubusercontent.com",
        "objects.githubusercontent.com", "github-releases.githubusercontent.com",
    ]

    private let request: URLRequest
    private let maximumBytes: Int
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data, any Error>?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var buffer = Data()
    private var responseAccepted = false
    private var finished = false

    init(request: URLRequest, maximumBytes: Int) {
        self.request = request
        self.maximumBytes = maximumBytes
    }

    func fetch() async throws -> Data {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                self.continuation = continuation
                lock.unlock()
                let configuration = URLSessionConfiguration.ephemeral
                configuration.urlCache = nil
                configuration.httpCookieStorage = nil
                configuration.httpShouldSetCookies = false
                var request = self.request
                request.httpShouldHandleCookies = false
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
                request.setValue("CopyTradingDesktop", forHTTPHeaderField: "User-Agent")
                let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
                let task = session.dataTask(with: request)
                lock.lock()
                self.session = session
                self.task = task
                lock.unlock()
                task.resume()
            }
        } onCancel: {
            self.cancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        let failure: UpdateServiceError? =
            if let response = response as? HTTPURLResponse {
                if !Self.isApproved(response.url) {
                    .transportRejected
                } else if response.statusCode == 404 {
                    .noPublishedRelease
                } else if response.statusCode != 200 {
                    .releaseServiceUnavailable
                } else if response.expectedContentLength > Int64(maximumBytes) {
                    .downloadTooLarge
                } else {
                    nil
                }
            } else {
                .invalidRelease
            }
        if let failure {
            completionHandler(.cancel)
            finish(.failure(failure))
            return
        }
        responseAccepted = true
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        let exceedsLimit = buffer.count + data.count > maximumBytes
        if !exceedsLimit { buffer.append(data) }
        let task = self.task
        lock.unlock()
        if exceedsLimit {
            task?.cancel()
            finish(.failure(UpdateServiceError.downloadTooLarge))
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url, Self.isApproved(url) else {
            completionHandler(nil)
            finish(.failure(UpdateServiceError.transportRejected))
            return
        }
        completionHandler(request)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        if let error {
            finish(.failure(error))
            return
        }
        lock.lock()
        let accepted = responseAccepted
        let data = buffer
        lock.unlock()
        guard accepted else {
            finish(.failure(UpdateServiceError.invalidRelease))
            return
        }
        finish(.success(data))
    }

    private func cancel() {
        lock.lock()
        let task = self.task
        lock.unlock()
        task?.cancel()
        finish(.failure(CancellationError()))
    }

    private func finish(_ result: Result<Data, any Error>) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        let continuation = self.continuation
        self.continuation = nil
        let session = self.session
        self.session = nil
        lock.unlock()
        continuation?.resume(with: result)
        session?.finishTasksAndInvalidate()
    }

    fileprivate static func isApproved(_ url: URL?) -> Bool {
        guard let url else { return false }
        return isApproved(url)
    }

    fileprivate static func isApproved(_ url: URL) -> Bool {
        url.scheme == "https"
            && url.host.map(approvedHosts.contains) == true
            && (url.port == nil || url.port == 443)
            && url.user == nil
            && url.password == nil
    }
}

struct MacOSPackageSignatureVerifier: UpdateSignatureVerifier {
    func verify(
        _ artifact: URL,
        expectedTeamIdentifier: String,
        expectedVersion: String
    ) async throws {
        guard artifact.pathExtension == "pkg" else { throw UpdateServiceError.signatureVerificationFailed }
        let packageCheck = try run("/usr/sbin/pkgutil", arguments: ["--check-signature", artifact.path])
        guard packageCheck.status == 0,
            packageCheck.output.contains("(\(expectedTeamIdentifier))"),
            packageCheck.output.localizedCaseInsensitiveContains("signed by a certificate trusted")
        else { throw UpdateServiceError.signatureVerificationFailed }
        let gatekeeper = try run("/usr/sbin/spctl", arguments: ["--assess", "--type", "install", "--verbose=4", artifact.path])
        guard gatekeeper.status == 0 else { throw UpdateServiceError.signatureVerificationFailed }
        let expansionWorkspace: PackageExpansionWorkspace
        do {
            expansionWorkspace = try PackageExpansionWorkspace.create()
        } catch {
            throw UpdateServiceError.signatureVerificationFailed
        }
        defer { expansionWorkspace.cleanup() }
        do {
            try await SystemUpdatePackageExpander(processRunner: SystemUpdateProcessRunner()).expand(
                artifact,
                into: expansionWorkspace.expandedPackageURL
            )
            try SignedPackageProductVerifier.verifyProductVersion(
                in: expansionWorkspace.expandedPackageURL,
                expectedVersion: expectedVersion
            )
        } catch {
            throw UpdateServiceError.signatureVerificationFailed
        }
    }

    private func run(_ executable: String, arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}

enum SignedPackageProductVerifier {
    static func verifyProductVersion(in expandedPackage: URL, expectedVersion: String) throws {
        _ = try applicationBundle(in: expandedPackage, expectedVersion: expectedVersion)
    }

    static func applicationBundle(in expandedPackage: URL, expectedVersion: String) throws -> URL {
        var rootInfo = stat()
        guard Darwin.lstat(expandedPackage.path, &rootInfo) == 0,
            (rootInfo.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR),
            rootInfo.st_uid == Darwin.getuid()
        else { throw UpdateServiceError.signatureVerificationFailed }

        var pendingDirectories = [expandedPackage]
        var visited = 0
        var infoPlists: [URL] = []
        while let directory = pendingDirectories.popLast() {
            let children: [URL]
            do {
                children = try FileManager.default.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )
            } catch {
                throw UpdateServiceError.signatureVerificationFailed
            }
            for child in children {
                visited += 1
                guard visited <= 100_000 else { throw UpdateServiceError.signatureVerificationFailed }
                var info = stat()
                guard Darwin.lstat(child.path, &info) == 0 else {
                    throw UpdateServiceError.signatureVerificationFailed
                }
                let kind = info.st_mode & mode_t(S_IFMT)
                if kind == mode_t(S_IFLNK) { continue }
                if kind == mode_t(S_IFDIR) {
                    pendingDirectories.append(child)
                } else if kind == mode_t(S_IFREG),
                    child.lastPathComponent == "Info.plist",
                    child.deletingLastPathComponent().lastPathComponent == "Contents",
                    child.deletingLastPathComponent().deletingLastPathComponent().pathExtension == "app"
                {
                    guard info.st_size > 0, info.st_size <= 1024 * 1024 else {
                        throw UpdateServiceError.signatureVerificationFailed
                    }
                    infoPlists.append(child)
                }
                guard infoPlists.count <= 128 else {
                    throw UpdateServiceError.signatureVerificationFailed
                }
            }
        }

        var productBundles: [(URL, String)] = []
        for infoURL in infoPlists {
            let data: Data
            do {
                data = try Data(contentsOf: infoURL, options: .mappedIfSafe)
            } catch {
                throw UpdateServiceError.signatureVerificationFailed
            }
            let propertyList: Any
            do {
                propertyList = try PropertyListSerialization.propertyList(
                    from: data,
                    options: [],
                    format: nil
                )
            } catch {
                throw UpdateServiceError.signatureVerificationFailed
            }
            guard let dictionary = propertyList as? [String: Any] else {
                throw UpdateServiceError.signatureVerificationFailed
            }
            if dictionary["CFBundleIdentifier"] as? String == "dev.copytrading.app" {
                guard let version = dictionary["CFBundleShortVersionString"] as? String else {
                    throw UpdateServiceError.signatureVerificationFailed
                }
                productBundles.append((infoURL.deletingLastPathComponent().deletingLastPathComponent(), version))
            }
        }
        guard productBundles.count == 1, productBundles[0].1 == expectedVersion else {
            throw UpdateServiceError.signatureVerificationFailed
        }
        return productBundles[0].0
    }
}
