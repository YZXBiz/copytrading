extension TradingCapabilityCheck {
    /// What the owner calls this check: "Discord source", or "Broker account · primary".
    public var title: String {
        let label =
            switch name {
            case .source: "Discord source"
            case .publicSourceAuthorization: "Public Discord authorization"
            case .model: "Model provider"
            case .broker: "Broker account"
            case .notification: "Notifications"
            case .configuration: "Configuration"
            }
        return subject.map { "\(label) · \($0)" } ?? label
    }
}
