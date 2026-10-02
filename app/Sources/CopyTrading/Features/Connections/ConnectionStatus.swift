import DesktopCore

/// How each outside service is doing: a word and a tone beside
/// its section. Nothing shows before a setup is saved.
struct ConnectionStatus: Equatable {
    let text: String
    let tone: StatusTone

    @MainActor
    init(text: String, tone: StatusTone) {
        self.text = L10n.string(text)
        self.tone = tone
    }

    @MainActor
    static func discord(_ model: AppModel) -> ConnectionStatus? {
        live(model) { $0.sourceConnected ? .init(text: "Connected", tone: .positive) : .init(text: "Not connected", tone: .caution) }
    }

    @MainActor
    static func interpreter(_ model: AppModel) -> ConnectionStatus? {
        live(model) { $0.modelReady ? .init(text: "Ready", tone: .positive) : .init(text: "Not ready", tone: .caution) }
    }

    @MainActor
    static func alerts(_ model: AppModel) -> ConnectionStatus? {
        guard let saved = model.savedTradingConfiguration else { return nil }
        return saved.notification == nil ? .init(text: "Off", tone: .inactive) : .init(text: "On", tone: .positive)
    }

    /// While copying runs the engine's own reading; otherwise only that the setup is saved.
    @MainActor
    private static func live(_ model: AppModel, _ reading: (TradingStatus) -> ConnectionStatus) -> ConnectionStatus? {
        guard model.savedTradingConfiguration != nil, let status = model.tradingStatus else { return nil }
        switch status.state {
        case .running, .degraded: return reading(status)
        case .starting: return .init(text: "Connecting", tone: .neutral)
        case .paused, .pausing, .failed: return .init(text: "Saved", tone: .inactive)
        }
    }
}
