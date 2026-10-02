import Darwin
import Foundation

/// The file commit is the only step that changes which credentials are active.
public struct TradingConfigurationStore: Sendable {
    public let url: URL
    private let secrets: any TradingSecretRevisionStore
    private let writer: any TradingConfigurationWriter

    public init(
        url: URL,
        secrets: any TradingSecretRevisionStore,
        writer: any TradingConfigurationWriter = AtomicTradingConfigurationWriter()
    ) {
        self.url = url
        self.secrets = secrets
        self.writer = writer
    }

    public func load() throws -> (configuration: TradingConfiguration, secrets: TradingSecrets)? {
        guard let saved = try loadEnvelope() else { return nil }
        let stableRevision = saved.pendingActivation?.previous
        guard
            let credentials = try secrets.load(
                revision: stableRevision?.secretRevision ?? saved.secretRevision
            )
        else {
            if stableRevision == nil, saved.pendingActivation != nil { return nil }
            throw TradingConfigurationStoreError.missingSecrets
        }
        return (stableRevision?.configuration ?? saved.configuration, credentials)
    }

    public func save(
        configuration: TradingConfiguration,
        revision engineRevision: String,
        secrets credentials: TradingSecrets,
        when state: TradingRunState
    ) throws {
        guard state == .paused else { throw TradingConfigurationStoreError.activeProcessing }
        guard configuration.version == TradingConfiguration.currentVersion, Self.isRevision(engineRevision) else {
            throw TradingConfigurationStoreError.invalidConfiguration
        }
        let previous = try loadEnvelope()
        guard previous?.pendingActivation == nil else {
            throw TradingConfigurationStoreError.activationPending
        }
        let revision = UUID()
        let data = try encode(
            SavedTradingConfiguration(
                version: 1, configuration: configuration, revision: engineRevision, secretRevision: revision
            ))
        try secrets.save(credentials, for: revision)
        do {
            try writer.write(data, to: url)
        } catch {
            let committedReference = (try? loadEnvelope())?.secretRevision == revision
            if !committedReference { try? secrets.delete(revision: revision) }
            throw TradingConfigurationStoreError.unavailable
        }
        if let previousRevision = previous?.secretRevision {
            try? secrets.delete(revision: previousRevision)
        }
    }

    /// Persist the candidate and its rollback reference before sending Start.
    /// `engineRevision` is the revision the engine reported when it validated `configuration`;
    /// the app never computes one, so the engine's activation journal always matches it.
    public func stageValidatedActivation(
        configuration: TradingConfiguration,
        revision engineRevision: String,
        secrets credentials: TradingSecrets,
        activationID: String,
        when state: TradingRunState
    ) throws {
        guard state == .paused else { throw TradingConfigurationStoreError.activeProcessing }
        guard configuration.version == TradingConfiguration.currentVersion, Self.isRevision(engineRevision) else {
            throw TradingConfigurationStoreError.invalidConfiguration
        }
        let previousEnvelope = try loadEnvelope()
        guard previousEnvelope?.pendingActivation == nil else {
            throw TradingConfigurationStoreError.activationPending
        }
        guard let canonicalID = UUID(uuidString: activationID)?.uuidString.lowercased() else {
            throw TradingConfigurationStoreError.invalidConfiguration
        }
        let revision = UUID()
        let pending = SavedTradingActivation(
            activationID: canonicalID,
            candidateRevision: engineRevision,
            previous: previousEnvelope.map {
                SavedTradingConfigurationRevision(
                    configuration: $0.configuration, revision: $0.revision,
                    secretRevision: $0.secretRevision
                )
            }
        )
        let data = try encode(
            SavedTradingConfiguration(
                version: 1,
                configuration: configuration,
                revision: engineRevision,
                secretRevision: revision,
                pendingActivation: pending
            ))
        try secrets.save(credentials, for: revision)
        do {
            try writer.write(data, to: url)
        } catch {
            // A post-rename directory-sync failure is ambiguous. Keep credentials if the
            // config pointer reached disk so startup reconciliation can recover safely.
            let candidateIsReferenced = (try? loadEnvelope())?.secretRevision == revision
            if !candidateIsReferenced { try? secrets.delete(revision: revision) }
            throw TradingConfigurationStoreError.unavailable
        }
    }

    /// Journal a fresh Start of the already saved revision without rotating its secret.
    public func stageSavedResume(activationID: String, when state: TradingRunState) throws {
        guard state == .paused else { throw TradingConfigurationStoreError.activeProcessing }
        guard let saved = try loadEnvelope() else {
            throw TradingConfigurationStoreError.missingSecrets
        }
        guard saved.pendingActivation == nil else {
            throw TradingConfigurationStoreError.activationPending
        }
        guard let canonicalID = UUID(uuidString: activationID)?.uuidString.lowercased() else {
            throw TradingConfigurationStoreError.invalidConfiguration
        }
        let pending = SavedTradingActivation(
            activationID: canonicalID,
            candidateRevision: saved.revision,
            previous: SavedTradingConfigurationRevision(
                configuration: saved.configuration, revision: saved.revision,
                secretRevision: saved.secretRevision
            )
        )
        try writer.write(
            try encode(
                SavedTradingConfiguration(
                    version: saved.version,
                    configuration: saved.configuration,
                    revision: saved.revision,
                    secretRevision: saved.secretRevision,
                    pendingActivation: pending
                )), to: url)
    }

    /// Remove pending metadata only after the engine durably commits this exact revision.
    public func finalizeValidatedActivation(activationID: String) throws {
        guard let saved = try loadEnvelope(),
            let pending = saved.pendingActivation,
            pending.activationID == activationID
        else {
            throw TradingConfigurationStoreError.activationJournalMismatch
        }
        try writer.write(
            try encode(
                SavedTradingConfiguration(
                    version: saved.version,
                    configuration: saved.configuration,
                    revision: saved.revision,
                    secretRevision: saved.secretRevision
                )), to: url)
        if let previousRevision = pending.previous?.secretRevision,
            previousRevision != saved.secretRevision
        {
            try? secrets.delete(revision: previousRevision)
        }
    }

    /// Restore the prior config pointer before deleting the candidate secret.
    public func rollbackValidatedActivation(activationID: String) throws {
        guard let saved = try loadEnvelope(),
            let pending = saved.pendingActivation,
            pending.activationID == activationID
        else {
            throw TradingConfigurationStoreError.activationJournalMismatch
        }
        do {
            if let previous = pending.previous {
                try writer.write(
                    try encode(
                        SavedTradingConfiguration(
                            version: saved.version,
                            configuration: previous.configuration,
                            revision: previous.revision,
                            secretRevision: previous.secretRevision
                        )), to: url)
            } else {
                try writer.remove(url)
            }
        } catch {
            throw TradingConfigurationStoreError.rollbackUnavailable
        }
        if let previousRevision = pending.previous?.secretRevision,
            previousRevision == saved.secretRevision
        {
            return
        }
        try? secrets.delete(revision: saved.secretRevision)
    }

    /// A setup saved by an older CopyTrading is never migrated. Its file and Keychain item are
    /// removed so the app starts clean and the owner sets up again. Returns whether one was removed.
    public func discardOlderVersion() throws -> Bool {
        guard FileManager.default.fileExists(atPath: url.path),
            let data = try? Data(contentsOf: url),
            let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let configuration = raw["configuration"] as? [String: Any],
            let version = configuration["version"] as? Int,
            version < TradingConfiguration.currentVersion
        else { return false }
        if let secretRevision = (raw["secretRevision"] as? String).flatMap(UUID.init(uuidString:)) {
            try? secrets.delete(revision: secretRevision)
        }
        try writer.remove(url)
        return true
    }

    public func pendingActivation() throws -> SavedTradingActivationInfo? {
        guard let pending = try loadEnvelope()?.pendingActivation else { return nil }
        return SavedTradingActivationInfo(
            activationID: pending.activationID,
            candidateRevision: pending.candidateRevision
        )
    }

    public func hasCredentialRevision(_ value: String) throws -> Bool {
        guard let revision = UUID(uuidString: value) else {
            throw TradingConfigurationStoreError.invalidFile
        }
        return try secrets.load(revision: revision) != nil
    }

    public func loadCredentialRevision(_ value: String) throws -> TradingSecrets? {
        guard let revision = UUID(uuidString: value) else {
            throw TradingConfigurationStoreError.invalidFile
        }
        return try secrets.load(revision: revision)
    }

    static func isRevision(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }

    private func encode(_ saved: SavedTradingConfiguration) throws -> Data {
        do {
            let data = try JSONEncoder().encode(saved)
            guard data.count <= 1_048_576 else {
                throw TradingConfigurationStoreError.invalidConfiguration
            }
            return data
        } catch let error as TradingConfigurationStoreError {
            throw error
        } catch {
            throw TradingConfigurationStoreError.invalidConfiguration
        }
    }

    private func loadEnvelope() throws -> SavedTradingConfiguration? {
        var info = stat()
        if Darwin.lstat(url.path, &info) != 0 {
            guard errno == ENOENT else { throw TradingConfigurationStoreError.unavailable }
            return nil
        }
        guard (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
            info.st_size <= 1_048_576
        else {
            throw TradingConfigurationStoreError.invalidFile
        }
        do {
            let saved = try JSONDecoder().decode(
                SavedTradingConfiguration.self, from: Data(contentsOf: url)
            )
            guard saved.version == 1, saved.configuration.version == TradingConfiguration.currentVersion, Self.isRevision(saved.revision),
                saved.pendingActivation == nil
                    || saved.pendingActivation?.candidateRevision == saved.revision
            else {
                throw TradingConfigurationStoreError.invalidFile
            }
            return saved
        } catch {
            throw TradingConfigurationStoreError.invalidFile
        }
    }
}

/// The saved JSON contains policy and a Keychain reference, never credential values.
private struct SavedTradingConfiguration: Codable {
    let version: Int
    let configuration: TradingConfiguration
    /// The engine's revision of `configuration`, as reported by validation.
    let revision: String
    let secretRevision: UUID
    var pendingActivation: SavedTradingActivation? = nil
}

private struct SavedTradingActivation: Codable {
    let activationID: String
    let candidateRevision: String
    let previous: SavedTradingConfigurationRevision?
}

private struct SavedTradingConfigurationRevision: Codable {
    let configuration: TradingConfiguration
    let revision: String
    let secretRevision: UUID
}

public protocol TradingConfigurationWriter: Sendable {
    func write(_ data: Data, to url: URL) throws
    func remove(_ url: URL) throws
}

extension TradingConfigurationWriter {
    public func remove(_ url: URL) throws {
        do {
            try FileManager.default.removeItem(at: url)
        } catch CocoaError.fileNoSuchFile {
            return
        } catch {
            throw TradingConfigurationStoreError.unavailable
        }
    }
}

public struct AtomicTradingConfigurationWriter: TradingConfigurationWriter {
    public init() {}

    public func write(_ data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        let temporary = directory.appending(path: ".trading-\(UUID().uuidString).tmp")
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: NSNumber(value: 0o700)]
            )
            let directoryFD = Darwin.open(directory.path, O_RDONLY | O_DIRECTORY)
            guard directoryFD >= 0 else { throw TradingConfigurationStoreError.unavailable }
            defer { _ = Darwin.close(directoryFD) }
            guard
                FileManager.default.createFile(
                    atPath: temporary.path, contents: nil,
                    attributes: [.posixPermissions: NSNumber(value: 0o600)]
                )
            else {
                throw TradingConfigurationStoreError.unavailable
            }
            defer { try? FileManager.default.removeItem(at: temporary) }
            let handle = try FileHandle(forWritingTo: temporary)
            do {
                try handle.write(contentsOf: data)
                try handle.synchronize()
                try handle.close()
            } catch {
                try? handle.close()
                throw error
            }
            // Rename is atomic; syncing the directory makes the new pointer durable.
            guard Darwin.rename(temporary.path, url.path) == 0 else {
                throw TradingConfigurationStoreError.unavailable
            }
            guard Darwin.fsync(directoryFD) == 0 else {
                throw TradingConfigurationStoreError.unavailable
            }
        } catch {
            throw TradingConfigurationStoreError.unavailable
        }
    }

    public func remove(_ url: URL) throws {
        do {
            if !FileManager.default.fileExists(atPath: url.path) { return }
            let directory = url.deletingLastPathComponent()
            let directoryFD = Darwin.open(directory.path, O_RDONLY | O_DIRECTORY)
            guard directoryFD >= 0 else { throw TradingConfigurationStoreError.unavailable }
            defer { _ = Darwin.close(directoryFD) }
            try FileManager.default.removeItem(at: url)
            guard Darwin.fsync(directoryFD) == 0 else {
                throw TradingConfigurationStoreError.unavailable
            }
        } catch {
            throw TradingConfigurationStoreError.unavailable
        }
    }
}

public enum TradingConfigurationStoreError: Error, LocalizedError, Sendable {
    case unavailable
    case invalidFile
    case invalidConfiguration
    case missingSecrets
    case activeProcessing
    case rollbackUnavailable
    case activationPending
    case activationJournalMismatch

    public var errorDescription: String? {
        switch self {
        case .unavailable: "The local trading configuration could not be saved or read."
        case .invalidFile: "The saved trading configuration is invalid."
        case .invalidConfiguration: "The trading configuration is too large or invalid."
        case .missingSecrets: "Saved trading credentials are unavailable in Keychain."
        case .activeProcessing: "Pause processing before changing trading settings."
        case .rollbackUnavailable: "Trading could not start, and the prior local revision could not be restored."
        case .activationPending: "A trading activation is awaiting engine confirmation."
        case .activationJournalMismatch: "Trading activation status does not match the saved revision."
        }
    }
}

public struct SavedTradingActivationInfo: Sendable, Equatable {
    public let activationID: String
    public let candidateRevision: String
}
