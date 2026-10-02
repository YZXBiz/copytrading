import Foundation

public enum KeychainStoreError: Error, Equatable, LocalizedError, Sendable {
    case unavailable

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            "The macOS Keychain is unavailable."
        }
    }
}
