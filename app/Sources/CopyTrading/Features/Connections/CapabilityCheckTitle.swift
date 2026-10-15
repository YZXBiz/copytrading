import DesktopCore

/// What a check is about, in the names Connections uses: "Discord", "Interpreter", "Alerts", an
/// account by its name, or "Setup" for the setup as a whole.
enum CapabilityCheckTitle {
    @MainActor
    static func text(for check: TradingCapabilityCheck) -> String {
        switch check.name {
        case .source: L10n.string("Discord")
        case .model: L10n.string("Interpreter")
        case .notification: L10n.string("Alerts")
        case .broker, .configuration: check.subject ?? L10n.string("Setup")
        }
    }
}
