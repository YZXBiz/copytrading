import DesktopCore

extension AppModel {
    /// Whether this account asked to approve every order (ADR-0008).
    func approvesOrders(accountID: String) -> Bool {
        savedTradingConfiguration?.accounts.first { $0.id == accountID }?.policy.approveOrders == true
    }

    /// Whether an order the owner sends by hand into this account needs Touch ID: a live account
    /// always, a paper account when it asks to approve every order.
    func requiresOwnerForOrders(accountID: String) -> Bool {
        guard let account = savedTradingConfiguration?.accounts.first(where: { $0.id == accountID }) else {
            return false
        }
        return account.environment == .live || account.policy.approveOrders
    }

    /// Asks for Touch ID once when any of these accounts needs it, and throws when the owner
    /// doesn't confirm, so nothing is sent.
    func confirmOrders(for accountIDs: Set<String>, reason: String) async throws {
        guard accountIDs.contains(where: requiresOwnerForOrders(accountID:)) else { return }
        try await confirmOwner(reason)
    }
}
