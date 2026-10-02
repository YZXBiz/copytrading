import Foundation
import Security

/// Revisions are immutable. Only the configuration file determines which one is active.
public protocol TradingSecretRevisionStore: Sendable {
    func load(revision: UUID) throws -> TradingSecrets?
    func save(_ secrets: TradingSecrets, for revision: UUID) throws
    func delete(revision: UUID) throws
}

public final class TradingKeychainStore: TradingSecretRevisionStore, @unchecked Sendable {
    private let service: String

    public init(service: String) { self.service = service }

    public static func service(forInstallationID identity: String) throws -> String {
        guard let identifier = UUID(uuidString: identity) else {
            throw TradingKeychainError.invalidInstallationID
        }
        return "dev.copytrading.app.trading.\(identifier.uuidString.lowercased())"
    }

    public func load(revision: UUID) throws -> TradingSecrets? {
        var query = baseQuery(revision: revision)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw TradingKeychainError.unavailable
        }
        do {
            return try JSONDecoder().decode(TradingSecrets.self, from: data)
        } catch {
            throw TradingKeychainError.invalidCredentials
        }
    }

    public func save(_ secrets: TradingSecrets, for revision: UUID) throws {
        let data: Data
        do {
            data = try JSONEncoder().encode(secrets)
        } catch {
            throw TradingKeychainError.invalidCredentials
        }
        var attributes = baseQuery(revision: revision)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        // SecItemAdd never updates a prior revision.
        guard SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess else {
            throw TradingKeychainError.unavailable
        }
    }

    /// Blanks a revision, then deletes it. A later build of the app may update but not delete an
    /// item an earlier build saved, so blanking first leaves no old key behind either way.
    public func delete(revision: UUID) throws {
        let query = baseQuery(revision: revision)
        let blanked = SecItemUpdate(query as CFDictionary, [kSecValueData as String: Data()] as CFDictionary)
        guard blanked == errSecSuccess || blanked == errSecItemNotFound else {
            throw TradingKeychainError.unavailable
        }
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound || status == errSecInvalidOwnerEdit else {
            throw TradingKeychainError.unavailable
        }
    }

    private func baseQuery(revision: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "trading.\(revision.uuidString.lowercased())",
        ]
    }
}

public enum TradingKeychainError: Error, LocalizedError, Sendable {
    case unavailable
    case invalidCredentials
    case invalidInstallationID

    public var errorDescription: String? {
        switch self {
        case .unavailable: "Trading credentials are unavailable in Keychain."
        case .invalidCredentials: "Saved trading credentials could not be read."
        case .invalidInstallationID: "The local installation identity is invalid."
        }
    }
}
