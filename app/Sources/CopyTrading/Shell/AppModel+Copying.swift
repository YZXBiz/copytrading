import DesktopCore

extension AppModel {
    /// Live accounts place real orders, so starting them always asks first.
    var hasLiveAccounts: Bool {
        savedTradingConfiguration?.accounts.contains { $0.environment == .live } == true
    }
}
