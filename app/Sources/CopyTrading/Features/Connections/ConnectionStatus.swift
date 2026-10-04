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

    /// A broker account: its keys, and whether it is saved as it reads now.
    @MainActor
    static func account(_ account: TradingAccountDraft, in model: AppModel) -> ConnectionStatus {
        let name = account.name.trimmed
        let typed = !account.key.isEmpty && !account.secret.isEmpty
        let hasSavedKeys = model.savedKeyAccountIDs.contains(name)
        let saved = model.savedTradingConfiguration?.accounts.first { $0.id == name }
        if let saved, !typed, hasSavedKeys, saved.environment == account.environment, saved.policy == account.policy {
            return live(model) { _ in .init(text: "Connected", tone: .positive) } ?? .init(text: "Saved", tone: .inactive)
        }
        return typed || hasSavedKeys ? .init(text: "Not saved yet", tone: .inactive) : .init(text: "Needs keys", tone: .caution)
    }

    /// A guru: what is still missing before their calls can be copied, or whether they are saved.
    @MainActor
    static func guru(_ route: TradingRouteDraft, in model: AppModel) -> ConnectionStatus {
        let draft = model.setupDraft
        if route.displayName.trimmed.isEmpty || route.prefix.trimmed.isEmpty {
            return .init(text: "Needs a name and how their calls start", tone: .caution)
        }
        if draft.effectiveChannel(for: route).isEmpty {
            return .init(text: "Needs a channel", tone: .caution)
        }
        let accounts = Set(draft.accountIDs)
        if !route.connections.contains(where: { accounts.contains($0.accountID.trimmed) }) {
            return .init(text: "Needs an account to copy into", tone: .caution)
        }
        let isSaved = model.savedTradingConfiguration?.profiles.contains { $0.guruID == route.guruID.trimmed } == true
        guard isSaved, !model.hasUnsavedSetupChanges else { return .init(text: "Not saved yet", tone: .inactive) }
        return live(model) { _ in .init(text: "Copying", tone: .positive) } ?? .init(text: "Saved", tone: .inactive)
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
