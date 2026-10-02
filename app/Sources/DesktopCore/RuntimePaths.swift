import Darwin
import Foundation

public struct RuntimePaths: Sendable {
    /// Stable installation root. The owner lock, installation identity, and logs live here.
    public let ownerSupportDirectory: URL
    /// Operational paths resolve to one immutable generation after the owner lock is held.
    public let applicationSupportDirectory: URL
    public let activeGenerationID: String?
    public let runtimeRoot: URL
    public let engineSourceRoot: URL

    public var databaseURL: URL {
        applicationSupportDirectory.appending(path: "application.db")
    }

    public var installationIdentityURL: URL {
        ownerSupportDirectory.appending(path: "installation-id")
    }

    public var lockURL: URL {
        ownerSupportDirectory.appending(path: ".app.lock")
    }

    public var generationPointerURL: URL {
        ownerSupportDirectory.appending(path: "active-generation")
    }

    public var generationsDirectory: URL {
        ownerSupportDirectory.appending(path: "generations", directoryHint: .isDirectory)
    }

    /// The engine's private diagnostics journal and the owner's log settings.
    public var logsDirectory: URL {
        ownerSupportDirectory.appending(path: "logs", directoryHint: .isDirectory)
    }

    public var restoreManualDisabledURL: URL {
        ownerSupportDirectory.appending(path: ".restore-manual-disabled")
    }

    public init(
        applicationSupportDirectory: URL,
        runtimeRoot: URL,
        engineSourceRoot: URL
    ) {
        let root = applicationSupportDirectory.standardizedFileURL
        ownerSupportDirectory = root
        self.applicationSupportDirectory = root
        activeGenerationID = nil
        self.runtimeRoot = runtimeRoot
        self.engineSourceRoot = engineSourceRoot
    }

    private init(
        ownerSupportDirectory: URL,
        applicationSupportDirectory: URL,
        activeGenerationID: String,
        runtimeRoot: URL,
        engineSourceRoot: URL
    ) {
        self.ownerSupportDirectory = ownerSupportDirectory
        self.applicationSupportDirectory = applicationSupportDirectory
        self.activeGenerationID = activeGenerationID
        self.runtimeRoot = runtimeRoot
        self.engineSourceRoot = engineSourceRoot
    }

    public static func discover(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> RuntimePaths {
        let supportRoot =
            environment["COPYTRADING_STATE_ROOT"].map {
                URL(filePath: $0, directoryHint: .isDirectory)
            }
            ?? URL.applicationSupportDirectory
            .appending(path: "CopyTrading", directoryHint: .isDirectory)
        let runtimeRoot =
            environment["COPYTRADING_RUNTIME_ROOT"].map {
                URL(filePath: $0, directoryHint: .isDirectory)
            } ?? bundle.resourceURL?.appending(path: "Runtime", directoryHint: .isDirectory)
        let engineRoot =
            environment["COPYTRADING_ENGINE_ROOT"].map {
                URL(filePath: $0, directoryHint: .isDirectory)
            } ?? bundle.resourceURL?.appending(path: "Engine", directoryHint: .isDirectory)
        guard let runtimeRoot, let engineRoot else {
            throw RuntimePathsError.runtimeResourcesUnavailable
        }
        return RuntimePaths(
            applicationSupportDirectory: supportRoot,
            runtimeRoot: runtimeRoot,
            engineSourceRoot: engineRoot
        )
    }

    public func installationIdentity() throws -> String {
        try ensurePrivateDirectory(ownerSupportDirectory)
        var existing = stat()
        let lookup = Darwin.lstat(installationIdentityURL.path, &existing)
        if lookup == 0 {
            guard (existing.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else {
                throw RuntimePathsError.invalidInstallationIdentity
            }
            let saved: String
            do {
                saved = try String(contentsOf: installationIdentityURL, encoding: .utf8)
            } catch {
                throw RuntimePathsError.storageUnavailable
            }
            let identity = saved.trimmingCharacters(in: .whitespacesAndNewlines)
            guard UUID(uuidString: identity) != nil else {
                throw RuntimePathsError.invalidInstallationIdentity
            }
            return identity
        }
        guard errno == ENOENT else { throw RuntimePathsError.storageUnavailable }

        let identity = UUID().uuidString.lowercased()
        do {
            try Data(identity.utf8).write(to: installationIdentityURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: NSNumber(value: 0o600)],
                ofItemAtPath: installationIdentityURL.path
            )
            return identity
        } catch {
            throw RuntimePathsError.storageUnavailable
        }
    }

    /// A present or unreadable marker keeps operational startup behind the restore gate.
    public func restoreManualDisabledGateIsPresent() throws -> Bool {
        var metadata = stat()
        if Darwin.lstat(restoreManualDisabledURL.path, &metadata) == 0 {
            return true
        }
        guard errno == ENOENT else { throw RuntimePathsError.storageUnavailable }
        return false
    }

    public func acquireInstallationLock() throws -> InstallationLock {
        try ensurePrivateDirectory(ownerSupportDirectory)
        let descriptor = Darwin.open(
            lockURL.path,
            O_CREAT | O_RDWR | O_EXLOCK | O_NONBLOCK | O_NOFOLLOW,
            S_IRUSR | S_IWUSR
        )
        if descriptor < 0 {
            throw errno == EWOULDBLOCK ? RuntimePathsError.alreadyRunning : .storageUnavailable
        }
        var lockInfo = stat()
        guard Darwin.fstat(descriptor, &lockInfo) == 0,
            (lockInfo.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
            lockInfo.st_uid == Darwin.getuid(),
            Darwin.fchmod(descriptor, mode_t(S_IRUSR | S_IWUSR)) == 0
        else {
            Darwin.close(descriptor)
            throw RuntimePathsError.storageUnavailable
        }
        return InstallationLock(descriptor: descriptor, url: lockURL)
    }

    /// Resolve the generation pointer only while the stable app-support owner lock is held.
    public func resolveActiveGeneration(whileHolding lock: InstallationLock) throws -> RuntimePaths {
        try requireOwnerLock(lock)
        try ensurePrivateDirectory(ownerSupportDirectory)
        var identifier: String
        do {
            identifier = try readGenerationPointer()
            try ensurePrivateDirectory(generationsDirectory)
        } catch is GenerationPointerMissingError {
            try ensurePrivateDirectory(generationsDirectory)
            do {
                guard
                    try FileManager.default.contentsOfDirectory(
                        atPath: generationsDirectory.path
                    ).isEmpty
                else {
                    throw RuntimePathsError.invalidGeneration
                }
            } catch let error as RuntimePathsError {
                throw error
            } catch {
                throw RuntimePathsError.storageUnavailable
            }
            let newIdentifier = UUID().uuidString.lowercased()
            try ensurePrivateDirectory(generationURL(newIdentifier))
            try writeGenerationPointer(newIdentifier)
            identifier = newIdentifier
        }
        let selected = try validatedGenerationDirectory(identifier)
        return RuntimePaths(
            ownerSupportDirectory: ownerSupportDirectory,
            applicationSupportDirectory: selected,
            activeGenerationID: identifier,
            runtimeRoot: runtimeRoot,
            engineSourceRoot: engineSourceRoot
        )
    }

    /// Atomically select an already staged generation and return its rollback target.
    public func switchActiveGeneration(
        to candidateID: String,
        expectedCurrentGeneration: String,
        whileHolding lock: InstallationLock
    ) throws -> String {
        try requireOwnerLock(lock)
        guard Self.isCanonicalGenerationID(candidateID) else {
            throw RuntimePathsError.invalidGeneration
        }
        let current = try readGenerationPointer()
        guard current == expectedCurrentGeneration else {
            throw RuntimePathsError.activeGenerationChanged
        }
        _ = try validatedGenerationDirectory(candidateID)
        try writeGenerationPointer(candidateID)
        return current
    }

    private func requireOwnerLock(_ lock: InstallationLock) throws {
        guard lock.isHeld, lock.url.standardizedFileURL == lockURL.standardizedFileURL else {
            throw RuntimePathsError.installationLockRequired
        }
    }

    private func readGenerationPointer() throws -> String {
        let descriptor = Darwin.open(generationPointerURL.path, O_RDONLY | O_NOFOLLOW)
        if descriptor < 0 {
            if errno == ENOENT { throw GenerationPointerMissingError() }
            throw RuntimePathsError.invalidGeneration
        }
        defer { Darwin.close(descriptor) }
        var info = stat()
        guard Darwin.fstat(descriptor, &info) == 0,
            (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
            info.st_uid == Darwin.getuid(),
            info.st_size > 0,
            info.st_size <= 64
        else { throw RuntimePathsError.invalidGeneration }
        var bytes = [UInt8](repeating: 0, count: 65)
        let count = Darwin.read(descriptor, &bytes, bytes.count)
        guard count > 0, count <= 64 else { throw RuntimePathsError.invalidGeneration }
        let raw = String(decoding: bytes.prefix(count), as: UTF8.self)
        let identifier = raw.hasSuffix("\n") ? String(raw.dropLast()) : raw
        guard Self.isCanonicalGenerationID(identifier) else {
            throw RuntimePathsError.invalidGeneration
        }
        return identifier
    }

    private func validatedGenerationDirectory(_ identifier: String) throws -> URL {
        guard Self.isCanonicalGenerationID(identifier) else {
            throw RuntimePathsError.invalidGeneration
        }
        var parentInfo = stat()
        guard Darwin.lstat(generationsDirectory.path, &parentInfo) == 0,
            (parentInfo.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR),
            parentInfo.st_uid == Darwin.getuid()
        else { throw RuntimePathsError.invalidGeneration }
        let directory = generationURL(identifier)
        var info = stat()
        guard Darwin.lstat(directory.path, &info) == 0,
            (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR),
            info.st_uid == Darwin.getuid(),
            info.st_mode & mode_t(0o077) == 0
        else { throw RuntimePathsError.invalidGeneration }
        return directory
    }

    private func generationURL(_ identifier: String) -> URL {
        generationsDirectory.appending(path: identifier, directoryHint: .isDirectory)
    }

    private func writeGenerationPointer(_ identifier: String) throws {
        guard Self.isCanonicalGenerationID(identifier) else {
            throw RuntimePathsError.invalidGeneration
        }
        let temporary = ownerSupportDirectory.appending(
            path: ".active-generation-\(UUID().uuidString).tmp"
        )
        let descriptor = Darwin.open(
            temporary.path,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else { throw RuntimePathsError.storageUnavailable }
        var shouldRemoveTemporary = true
        defer {
            Darwin.close(descriptor)
            if shouldRemoveTemporary { _ = Darwin.unlink(temporary.path) }
        }
        let data = Data("\(identifier)\n".utf8)
        try data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { throw RuntimePathsError.storageUnavailable }
            var written = 0
            while written < rawBuffer.count {
                let result = Darwin.write(
                    descriptor,
                    base.advanced(by: written),
                    rawBuffer.count - written
                )
                guard result > 0 else { throw RuntimePathsError.storageUnavailable }
                written += Int(result)
            }
        }
        guard Darwin.fsync(descriptor) == 0,
            Darwin.rename(temporary.path, generationPointerURL.path) == 0
        else { throw RuntimePathsError.storageUnavailable }
        shouldRemoveTemporary = false
        try syncDirectory(ownerSupportDirectory)
    }

    private func syncDirectory(_ directory: URL) throws {
        let descriptor = Darwin.open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw RuntimePathsError.storageUnavailable }
        defer { Darwin.close(descriptor) }
        guard Darwin.fsync(descriptor) == 0 else { throw RuntimePathsError.storageUnavailable }
    }

    private static func isCanonicalGenerationID(_ value: String) -> Bool {
        guard let uuid = UUID(uuidString: value) else { return false }
        return uuid.uuidString.lowercased() == value
    }

    /// Fail closed if a prior app owner left an engine running in this installation's directory.
    /// Process IDs are inspected only; no process is ever terminated here. Called while holding the
    /// installation lock, so a live engine here was orphaned by an app process that crashed or was
    /// force-quit, and it may still be draining trading work.
    public func rejectOrphanedEngine() throws {
        let support = applicationSupportDirectory.resolvingSymlinksInPath().path
        for (_, directory) in try engineProcesses() where directory == support {
            throw RuntimePathsError.staleRuntimeChild
        }
    }

    /// Processes running the bundled Python runtime, with their resolved working directory.
    private func engineProcesses() throws -> [(pid_t, String)] {
        let byteCount = Darwin.proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard byteCount > 0 else { throw RuntimePathsError.storageUnavailable }
        let capacity = max(Int(byteCount) / MemoryLayout<pid_t>.size + 64, 128)
        var identifiers = [pid_t](repeating: 0, count: capacity)
        let returned = identifiers.withUnsafeMutableBytes { bytes in
            Darwin.proc_listpids(UInt32(PROC_ALL_PIDS), 0, bytes.baseAddress, Int32(bytes.count))
        }
        guard returned > 0, Int(returned) < capacity * MemoryLayout<pid_t>.size else {
            throw RuntimePathsError.storageUnavailable
        }
        var found: [(pid_t, String)] = []
        for pid in identifiers.prefix(Int(returned) / MemoryLayout<pid_t>.size) where pid > 0 {
            var executableBytes = [CChar](repeating: 0, count: 4_096)
            let pathLength = Darwin.proc_pidpath(pid, &executableBytes, UInt32(executableBytes.count))
            guard pathLength > 0 else { continue }
            let executable = String(
                decoding: executableBytes.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) },
                as: UTF8.self
            )
            guard executable.hasSuffix("/Runtime/cpython/python/bin/python3.14") else { continue }
            var vnode = proc_vnodepathinfo()
            let infoSize = Int32(MemoryLayout<proc_vnodepathinfo>.size)
            let read = Darwin.proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &vnode, infoSize)
            guard read == infoSize else {
                if Darwin.kill(pid, 0) == 0 { throw RuntimePathsError.storageUnavailable }
                continue
            }
            let directory = withUnsafeBytes(of: vnode.pvi_cdir.vip_path) { bytes in
                String(decoding: bytes.prefix(while: { $0 != 0 }), as: UTF8.self)
            }
            found.append((pid, URL(filePath: directory).resolvingSymlinksInPath().path))
        }
        return found
    }

    private func ensurePrivateDirectory(_ directory: URL) throws {
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: NSNumber(value: 0o700)]
            )
            var info = stat()
            guard Darwin.lstat(directory.path, &info) == 0,
                (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR),
                info.st_uid == Darwin.getuid()
            else { throw RuntimePathsError.storageUnavailable }
            guard Darwin.chmod(directory.path, mode_t(0o700)) == 0 else {
                throw RuntimePathsError.storageUnavailable
            }
            try syncDirectory(directory)
        } catch {
            if let pathError = error as? RuntimePathsError { throw pathError }
            throw RuntimePathsError.storageUnavailable
        }
    }
}

private struct GenerationPointerMissingError: Error {}

public enum RuntimePathsError: Error, Equatable, LocalizedError, Sendable {
    case alreadyRunning
    case invalidInstallationIdentity
    case installationLockRequired
    case runtimeResourcesUnavailable
    case storageUnavailable
    case staleRuntimeChild
    case invalidGeneration
    case activeGenerationChanged

    public var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            "CopyTrading is already running."
        case .invalidInstallationIdentity:
            "The local installation identity is invalid."
        case .installationLockRequired:
            "The app-support owner lock must be held to access operational generations."
        case .runtimeResourcesUnavailable:
            "The local runtime resources could not be found."
        case .storageUnavailable:
            "CopyTrading could not access its private local storage."
        case .staleRuntimeChild:
            "A previous engine process is still finishing work for this installation. Wait a moment, then start again."
        case .invalidGeneration:
            "The selected operational generation is invalid or incomplete."
        case .activeGenerationChanged:
            "The active operational generation changed during recovery; no switch was applied."
        }
    }
}
