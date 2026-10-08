import DesktopCore
import Foundation

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
        case "limits_changed":
            L10n.string("Limits changed: %@", changes.map(Self.phrase).joined(separator: L10n.string(", ")))
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

    /// "per order $200 → $500".
    @MainActor private static func phrase(_ change: AccountLimitChange) -> String {
        let (name, unit) = setting(change.setting)
        return L10n.string("%@ %@ → %@", name, value(change.before, unit), value(change.after, unit))
    }

    private enum Unit { case dollars, seconds, percent, count, onOff }

    @MainActor private static func setting(_ code: String) -> (String, Unit) {
        switch code {
        case "max_order_usd": (L10n.string("per order"), .dollars)
        case "max_symbol_usd": (L10n.string("per stock"), .dollars)
        case "max_total_usd": (L10n.string("total exposure"), .dollars)
        case "daily_loss_cap_usd": (L10n.string("daily loss cap"), .dollars)
        case "max_entries_per_day": (L10n.string("entries per day"), .count)
        case "max_signal_age_seconds": (L10n.string("signal age"), .seconds)
        case "order_timeout_seconds": (L10n.string("order timeout"), .seconds)
        case "poll_seconds": (L10n.string("check interval"), .seconds)
        case "max_above_signal_pct": (L10n.string("above signal price"), .percent)
        case "max_below_signal_pct": (L10n.string("below signal price"), .percent)
        case "extended_hours": (L10n.string("extended hours"), .onOff)
        case "overnight": (L10n.string("overnight"), .onOff)
        case "copy_exits": (L10n.string("copy exits"), .onOff)
        case "approve_orders": (L10n.string("ask before orders"), .onOff)
        default: (L10n.string(Humanize.code(code)).lowercased(), .count)
        }
    }

    @MainActor private static func value(_ text: String, _ unit: Unit) -> String {
        guard unit != .onOff else { return L10n.string(text == "true" ? "on" : "off") }
        guard let number = Decimal(engine: text) else { return text }
        switch unit {
        case .dollars: return number.formatted(.currency(code: "USD"))
        case .seconds: return L10n.string("%@ s", number.formatted())
        case .percent: return L10n.string("%@%%", number.formatted())
        case .count, .onOff: return number.formatted()
        }
    }
}
