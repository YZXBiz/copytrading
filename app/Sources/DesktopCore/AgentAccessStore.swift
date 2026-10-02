import Darwin
import Foundation

public enum AgentAccessStoreError: Error, Equatable, LocalizedError, Sendable {
    case unsafeLocation
    case invalidSetting

    public var errorDescription: String? {
        switch self {
        case .unsafeLocation: "The agent access setting is not in a private folder owned by this user."
        case .invalidSetting: "The saved agent access setting could not be read."
        }
    }
}

/// Remembers the owner's agent access choice in the app's private state folder.
public struct AgentAccessStore: Sendable {
    public let url: URL

    public init(stateRoot: URL) {
        url = stateRoot.appending(path: "agent-access.json").standardizedFileURL
    }

    /// A missing file means agents were never allowed.
    public func load() throws -> AgentAccessSetting {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return .off }
        guard info.st_mode & S_IFMT == S_IFREG, info.st_uid == getuid() else {
            throw AgentAccessStoreError.unsafeLocation
        }
        do {
            return try JSONDecoder().decode(Stored.self, from: Data(contentsOf: url)).access
        } catch {
            throw AgentAccessStoreError.invalidSetting
        }
    }

    public func save(_ access: AgentAccessSetting) throws {
        var info = stat()
        if lstat(url.path, &info) == 0, info.st_mode & S_IFMT != S_IFREG {
            throw AgentAccessStoreError.unsafeLocation
        }
        try JSONEncoder().encode(Stored(access: access)).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: url.path)
    }

    private struct Stored: Codable {
        let access: AgentAccessSetting
    }
}
