import Foundation

/// How long the engine keeps its private diagnostics journal, and how much disk it may use.
public struct DiagnosticsSettings: Codable, Equatable, Sendable {
    public static let minimumAgeDays = 1
    public static let maximumAgeDays = 90
    public static let supportedStorageLimits: [Int64] = [
        64, 128, 256, 512, 1_024, 2_048,
    ].map { Int64($0) * 1_024 * 1_024 }

    public let ageDays: Int
    public let storageLimitBytes: Int64

    public init() {
        ageDays = 7
        storageLimitBytes = 256 * 1_024 * 1_024
    }

    public init(ageDays: Int, storageLimitBytes: Int64) throws {
        guard (Self.minimumAgeDays...Self.maximumAgeDays).contains(ageDays),
            Self.supportedStorageLimits.contains(storageLimitBytes)
        else {
            throw DiagnosticsSettingsError.invalid
        }
        self.ageDays = ageDays
        self.storageLimitBytes = storageLimitBytes
    }

    /// What the engine reads at launch to bound its journal.
    public var engineEnvironment: [String: String] {
        [
            "COPYTRADING_DESKTOP_DIAGNOSTICS_RETENTION_DAYS": String(ageDays),
            "COPYTRADING_DESKTOP_DIAGNOSTICS_MAX_BYTES": String(storageLimitBytes),
        ]
    }

    private enum CodingKeys: String, CodingKey {
        case ageDays
        case storageLimitBytes
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            ageDays: container.decode(Int.self, forKey: .ageDays),
            storageLimitBytes: container.decode(Int64.self, forKey: .storageLimitBytes)
        )
    }
}

public enum DiagnosticsSettingsError: Error, Equatable, LocalizedError, Sendable {
    case invalid
    case unavailable

    public var errorDescription: String? {
        switch self {
        case .invalid:
            "Choose a supported log retention and storage limit."
        case .unavailable:
            "The log settings could not be saved on this Mac."
        }
    }
}

/// A small private preference file beside the journal it governs.
public struct DiagnosticsSettingsStore: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url.standardizedFileURL
    }

    public func load() throws -> DiagnosticsSettings? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
            values.isRegularFile == true, values.isSymbolicLink != true
        else { throw DiagnosticsSettingsError.invalid }
        do {
            return try JSONDecoder().decode(DiagnosticsSettings.self, from: Data(contentsOf: url))
        } catch {
            throw DiagnosticsSettingsError.invalid
        }
    }

    public func save(_ settings: DiagnosticsSettings) throws {
        let parent = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: parent,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: NSNumber(value: 0o700)]
            )
            try JSONEncoder().encode(settings).write(to: url, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: NSNumber(value: 0o600)],
                ofItemAtPath: url.path
            )
        } catch {
            throw DiagnosticsSettingsError.unavailable
        }
    }
}
