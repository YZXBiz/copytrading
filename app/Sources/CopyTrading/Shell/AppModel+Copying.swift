import DesktopCore

extension AppModel {
    /// Live accounts place real orders, so starting them always asks first.
    var hasLiveAccounts: Bool {
        savedTradingConfiguration?.accounts.contains { $0.environment == .live } == true
    }

    /// Copying into a live account goes on to place real orders by itself, so starting it needs a
    /// fresh Touch ID or Mac password, like a live sale. Paper setups pass straight through.
    func confirmLiveStart(_ configuration: TradingConfiguration) async -> Bool {
        guard configuration.accounts.contains(where: { $0.environment == .live }) else { return true }
        do {
            try await confirmOwner(L10n.string("start copying into live accounts"))
            return true
        } catch {
            message = L10n.string("Copying didn't start. Confirm with Touch ID or your Mac password to copy into live accounts.")
            return false
        }
    }
}
