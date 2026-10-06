import DesktopCore

extension AccountEvent {
    /// What happened, in the owner's words; unknown kinds fall back to `Humanize`.
    @MainActor var title: String {
        switch kind {
        case "account_control_changed":
            switch reason {
            case "pause": L10n.string("Entries paused")
            case "resume": L10n.string("Entries resumed")
            case "set_recovery":
                L10n.string("After a restart: %@", (RecoveryPreference(rawValue: status ?? "") ?? .manual).title)
            case "restore_manual": L10n.string("Restored from a backup; waits for you after a restart")
            default: L10n.string("Account settings changed")
            }
        case "account_bound": L10n.string("Connected to the broker account")
        case "account_inventoried": L10n.string("Read the holdings already in the account")
        case "message": L10n.string("Received a post")
        case "message_done": L10n.string("Finished with a post")
        case "skipped": L10n.string("Skipped: %@", Reason.text(reason))
        case "signal_rejected": L10n.string("Rejected a post: %@", Reason.text(reason))
        case "order_prepared": L10n.string("Prepared an order")
        case "submit_started": L10n.string("Sent an order to the broker")
        case "broker_acknowledged": L10n.string("The broker accepted an order")
        case "order_update": L10n.string("Order %@", L10n.string(Humanize.code(status ?? "updated").lowercased()))
        case "cancel_requested": L10n.string("Asked the broker to cancel an order")
        case "submission_aborted": L10n.string("Stopped an order before sending it")
        case "submission_uncertain": L10n.string("Unsure whether an order reached the broker")
        case "submit_error": L10n.string("The broker refused an order")
        case "quote_unavailable": L10n.string("No price quote was available")
        case "ownership_incident_opened": L10n.string("Holdings need your review")
        case "ownership_resolved": L10n.string("Holdings review resolved")
        case "manual_sale_recorded": L10n.string("Recorded a sale you made")
        case "manual_correction_recorded": L10n.string("Recorded your correction")
        default: L10n.string(Humanize.code(kind))
        }
    }
}
