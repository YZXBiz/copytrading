import DesktopCore

/// Whether CopyTrading copies into an account, in words and a tone. An account copies when copying
/// runs, the engine holds the account, and its buys are on; anything else is off, and its one
/// button says Start Copying.
@MainActor
struct AccountCopyState: Equatable {
    let isCopying: Bool
    let text: String
    let tone: StatusTone

    /// Readiness values for an account the engine could not open, so there is nothing to turn on
    /// until the reason is settled.
    static let unheld: Set<String> = [
        "account_unavailable", "processing_stopped", "outside_open_orders", "broker_account_inactive",
        "account_in_use", "alpaca_account_shared", "record_unreadable", "broker_keys_rejected", "broker_unreachable",
    ]

    /// An account in the setup that is off because the engine could not keep it running or open it,
    /// not because the owner stopped it: it needs a look. Stopping everything on purpose reads
    /// `processing_stopped`, which is not this.
    static func isStopped(_ account: AccountOverview) -> Bool {
        account.activeConfiguration && unheld.contains(account.readiness) && account.readiness != "processing_stopped"
    }

    init(_ account: AccountOverview) {
        guard account.activeConfiguration else {
            (isCopying, text, tone) = (false, "Not copying", .inactive)
            return
        }
        if Self.unheld.contains(account.readiness) {
            (isCopying, text, tone) = (false, Reason.text(account.readiness), .caution)
            return
        }
        guard account.entryPermission == "enabled" else {
            (isCopying, text, tone) = (false, "Not copying", .inactive)
            return
        }
        switch account.readiness {
        case "enabled": (isCopying, text, tone) = (true, "Copying", .positive)
        case "enabled_waiting_for_session": (isCopying, text, tone) = (true, "Copying from the open", .positive)
        case "recovery_pending", "reconciliation_unavailable":
            (isCopying, text, tone) = (true, "Checking the account", .neutral)
        // After a restart the account waits for its Start Copying, like any account that is off.
        case "manual_resume_required", "inactive_evidence": (isCopying, text, tone) = (false, "Not copying", .inactive)
        default: (isCopying, text, tone) = (true, Reason.text(account.readiness), .caution)
        }
    }
}
