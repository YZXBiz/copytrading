import DesktopCore

/// Whether CopyTrading copies, in the five words the owner sees everywhere: the sidebar, the
/// toolbar, Settings, the menu bar, each account, and its notifications. The engine keeps every
/// detail; this is the one place that turns them into a word, with the line under it saying why
/// it stopped, what it waits for, or what is wrong while it still copies. The engine's agent
/// tools make the same choice (`copytrading_engine.control.copying`).
@MainActor
struct CopyingState: Equatable {
    enum Word: Equatable, CaseIterable {
        /// Posts are read and orders are placed.
        case copying
        /// The owner paused new buys; sells still go through.
        case sellsOnly
        /// The owner, or an agent they approved, stopped it; nothing trades.
        case paused
        /// A problem stopped it; the detail says which.
        case stopped
        /// Never started with this setup.
        case notStarted
    }

    let word: Word
    /// Why it stopped, what it waits for, or a warning while it copies; nil when there's nothing to add.
    let detail: String?
    /// Whether the line under Copying is something wrong, or only says when it copies.
    let warns: Bool

    init(_ word: Word, _ detail: String? = nil, warns: Bool = true) {
        self.word = word
        self.detail = detail
        self.warns = warns
    }

    var title: String {
        switch word {
        case .copying: L10n.string("Copying")
        case .sellsOnly: L10n.string("Sells only")
        case .paused: L10n.string("Paused")
        case .stopped: L10n.string("Stopped")
        case .notStarted: L10n.string("Not started")
        }
    }

    /// The word and its line together, for places with room for one line.
    var text: String { detail.map { L10n.string("%@ · %@", title, $0) } ?? title }

    var tone: StatusTone {
        switch word {
        case .copying: detail != nil && warns ? .caution : .positive
        case .sellsOnly: .caution
        case .paused, .notStarted: .inactive
        case .stopped: .critical
        }
    }

    /// New buys go out: copying, warnings or not.
    var isCopying: Bool { word == .copying }

    // MARK: Copying as a whole

    static func overall(_ model: AppModel) -> CopyingState {
        if model.runtimeState == .stopped || model.runtimeState == .failed {
            return CopyingState(.stopped, L10n.string("The engine stopped"))
        }
        guard model.savedTradingConfiguration != nil else { return CopyingState(.notStarted) }
        return overall(model.tradingStatus, accounts: model.accountFeature?.accounts ?? [])
    }

    static func overall(_ status: TradingStatus?, accounts: [AccountOverview] = []) -> CopyingState {
        switch status?.state {
        case .running:
            let inSetup = accounts.filter(\.activeConfiguration).map { account($0, processing: status) }
            if !inSetup.isEmpty, inSetup.allSatisfy({ $0.word == .sellsOnly }) {
                return CopyingState(.sellsOnly, L10n.string("New buys are paused in every account"))
            }
            return CopyingState(.copying)
        case .degraded:
            // The engine reports "degraded" while a start finishes (no code) and while it copies
            // with something wrong (a code).
            guard let code = status?.errorCode else { return CopyingState(.notStarted, L10n.string("Starting…")) }
            return CopyingState(.copying, Reason.text(code))
        case .starting:
            return CopyingState(.notStarted, L10n.string("Starting…"))
        case .pausing:
            return CopyingState(.copying, L10n.string("Pausing…"))
        case .failed:
            return CopyingState(.stopped, Reason.text(status?.errorCode ?? "processing_unavailable"))
        case .paused, nil:
            return CopyingState(.paused)
        }
    }

    // MARK: One account

    /// An account the engine could not open or keep: a problem, never the owner's choice.
    static let unheld: Set<String> = [
        "account_unavailable", "outside_open_orders", "broker_account_inactive",
        "account_in_use", "alpaca_account_shared", "record_unreadable", "broker_keys_rejected",
        "broker_unreachable",
    ]

    static func account(_ account: AccountOverview, processing status: TradingStatus? = nil) -> CopyingState {
        guard account.activeConfiguration else { return CopyingState(.notStarted) }
        if unheld.contains(account.readiness) { return CopyingState(.stopped, Reason.text(account.readiness)) }
        if status?.state == .failed {
            return CopyingState(.stopped, Reason.text(status?.errorCode ?? "processing_unavailable"))
        }
        if status?.state == .paused || status?.state == .pausing || account.readiness == "processing_stopped" {
            return CopyingState(.paused)
        }
        if account.entryPermission == "paused" {
            return CopyingState(.sellsOnly, L10n.string("You paused new buys; sells still go through"))
        }
        if account.readiness == "manual_resume_required" {
            return CopyingState(.sellsOnly, L10n.string("Waiting for your Start Copying after a restart"))
        }
        guard account.entryPermission == "enabled" else { return CopyingState(.notStarted) }
        switch account.readiness {
        case "enabled": return CopyingState(.copying)
        case "enabled_waiting_for_session":
            return CopyingState(.copying, L10n.string("Copies once the market opens"), warns: false)
        case "recovery_pending": return CopyingState(.copying, L10n.string("Checking the account after a restart"))
        case "unavailable": return CopyingState(.copying)
        default: return CopyingState(.copying, Reason.text(account.readiness))
        }
    }

    /// An account in the setup that a problem stopped, not the owner: it needs a look.
    static func isStopped(_ account: AccountOverview) -> Bool {
        Self.account(account).word == .stopped
    }
}
