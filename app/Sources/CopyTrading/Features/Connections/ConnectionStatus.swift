import DesktopCore

/// How each outside service is doing, as a word and a tone on its row: the engine's own reading
/// while copying runs, otherwise the latest check of what is typed, otherwise whether it is saved.
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
        live(model, .discord) {
            $0.sourceConnected ? .init(text: "Connected", tone: .positive) : .init(text: "Not connected", tone: .caution)
        }
    }

    @MainActor
    static func interpreter(_ model: AppModel) -> ConnectionStatus? {
        live(model, .interpreter) { $0.modelReady ? .init(text: "Ready", tone: .positive) : .init(text: "Not ready", tone: .caution) }
    }

    @MainActor
    static func alerts(_ model: AppModel) -> ConnectionStatus? {
        if let checked = checked(.alerts, in: model) { return checked }
        guard let saved = model.savedTradingConfiguration else { return nil }
        return saved.notification == nil ? .init(text: "Off", tone: .inactive) : .init(text: "On", tone: .positive)
    }

    /// A broker account: its keys, and whether it is saved as it reads now.
    @MainActor
    static func account(_ account: TradingAccountDraft, in model: AppModel) -> ConnectionStatus {
        let name = account.name.trimmed
        if let checked = checked(.account(name), in: model) { return checked }
        let typed = !account.key.isEmpty && !account.secret.isEmpty
        let hasSavedKeys = model.savedKeyAccountIDs.contains(name)
        let saved = model.savedTradingConfiguration?.accounts.first { $0.id == name }
        if let saved, !typed, hasSavedKeys, saved.environment == account.environment, saved.policy == account.policy {
            return live(model, .account(name)) { _ in .init(text: "Connected", tone: .positive) }
                ?? .init(text: "Saved", tone: .inactive)
        }
        return typed || hasSavedKeys ? .init(text: "Not saved yet", tone: .inactive) : .init(text: "Needs keys", tone: .caution)
    }

    /// A guru: what is still missing before their calls can be copied, or whether they are saved.
    @MainActor
    static func guru(_ route: TradingRouteDraft, in model: AppModel) -> ConnectionStatus {
        let draft = model.setupDraft
        if route.displayName.trimmed.isEmpty {
            return .init(text: "Needs a name and how their calls start", tone: .caution)
        }
        if draft.effectiveChannel(for: route).isEmpty {
            return .init(text: "Needs a channel", tone: .caution)
        }
        let accounts = Set(draft.accountIDs)
        if route.connection.map({ accounts.contains($0.accountID.trimmed) }) != true {
            return .init(text: "Needs an account to copy into", tone: .caution)
        }
        let isSaved = model.savedTradingConfiguration?.profiles.contains { $0.guruID == route.guruID.trimmed } == true
        guard isSaved, !model.hasUnsavedSetupChanges else { return .init(text: "Not saved yet", tone: .inactive) }
        return running(model) { _ in .init(text: "Copying", tone: .positive) } ?? .init(text: "Saved", tone: .inactive)
    }

    /// The latest check of what is typed: checking, connected, or not.
    @MainActor
    static func checked(_ subject: ConnectionCheckSubject, in model: AppModel) -> ConnectionStatus? {
        guard let result = model.connectionCheckResult(subject) else { return nil }
        guard let check = result.check else { return .init(text: "Checking…", tone: .neutral) }
        return check.state == .ready
            ? .init(text: "Connected", tone: .positive) : .init(text: "Couldn't connect", tone: .caution)
    }

    /// While copying runs, the engine's own reading; otherwise the latest check, or that the setup
    /// is saved.
    @MainActor
    private static func live(
        _ model: AppModel, _ subject: ConnectionCheckSubject, _ reading: (TradingStatus) -> ConnectionStatus
    ) -> ConnectionStatus? {
        if let running = running(model, reading) { return running }
        if let checked = checked(subject, in: model) { return checked }
        guard model.savedTradingConfiguration != nil, model.tradingStatus != nil else { return nil }
        return .init(text: "Saved", tone: .inactive)
    }

    /// The engine's reading while copying runs or starts; nothing while it is paused.
    @MainActor
    private static func running(_ model: AppModel, _ reading: (TradingStatus) -> ConnectionStatus) -> ConnectionStatus? {
        guard model.savedTradingConfiguration != nil, let status = model.tradingStatus else { return nil }
        switch status.state {
        case .running, .degraded: return reading(status)
        case .starting: return .init(text: "Connecting", tone: .neutral)
        case .paused, .pausing, .failed: return nil
        }
    }
}
