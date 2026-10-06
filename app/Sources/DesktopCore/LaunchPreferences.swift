import Foundation
import Security

/// What CopyTrading does when it opens, and while it copies.
public struct LaunchPreferences: Codable, Equatable, Sendable {
    /// Ask for Touch ID (or the Mac password) before showing anything private.
    public var asksForOwner: Bool
    /// Start copying on its own once the app is open, when every account is paper.
    public var startsCopying: Bool
    /// Keep the Mac from idle-sleeping while copying is on, so no post is missed.
    public var keepsMacAwake: Bool

    public init(asksForOwner: Bool = true, startsCopying: Bool = false, keepsMacAwake: Bool = true) {
        self.asksForOwner = asksForOwner
        self.startsCopying = startsCopying
        self.keepsMacAwake = keepsMacAwake
    }
}

/// Keeps the launch preferences in the Keychain, one item per installation root, so another
/// process cannot quietly turn off the owner check the way it could edit a preferences file.
public struct LaunchPreferencesStore: Sendable {
    private let service: String
    private let account: String

    public init(stateRoot: URL, service: String = "dev.copytrading.app.launch") {
        self.service = service
        account = stateRoot.standardizedFileURL.path
    }

    /// The saved preferences; anything unreadable falls back to asking for the owner.
    public func load() -> LaunchPreferences {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
            let data = result as? Data,
            let preferences = try? JSONDecoder().decode(LaunchPreferences.self, from: data)
        else { return LaunchPreferences() }
        return preferences
    }

    public func save(_ preferences: LaunchPreferences) throws {
        let data: Data
        do {
            data = try JSONEncoder().encode(preferences)
        } catch {
            throw KeychainStoreError.unavailable
        }
        let status = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw KeychainStoreError.unavailable }
        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        guard SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess else {
            throw KeychainStoreError.unavailable
        }
    }

    /// Removes the saved item; tests use it to leave the Keychain as they found it.
    public func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
