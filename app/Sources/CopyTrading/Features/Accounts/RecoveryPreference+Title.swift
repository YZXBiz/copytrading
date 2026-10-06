import DesktopCore

/// What an account does after CopyTrading restarts, in the words the app shows.
extension RecoveryPreference {
    @MainActor var title: String {
        switch self {
        case .manual: L10n.string("Wait for me")
        case .automatic: L10n.string("Carry on by itself")
        }
    }
}
