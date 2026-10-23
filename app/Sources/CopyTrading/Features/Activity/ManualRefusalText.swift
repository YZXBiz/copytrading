import DesktopCore

/// What the by-hand flow says when something stops a held call from being copied: one line each,
/// why and then what to do, in the app's language. A code the engine sends is worded here before
/// the shared `Reason` words; every code the engine can send in this flow has a line
/// (`test_manual_refusal_wording.py` keeps the two in step).
@MainActor
enum ManualRefusalText {
    /// The line for an engine code in this flow, or nil when it has none.
    static func text(_ code: String?) -> String? {
        guard let code, let line = known[code] else { return nil }
        return L10n.string(line)
    }

    /// An engine reason as the owner reads it here: this flow's line, else the shared wording.
    static func reason(_ code: String) -> String {
        text(code) ?? Reason.text(code)
    }

    /// A string the review keeps for a failure: a code is worded; a sentence is said as written.
    static func line(_ stored: String) -> String {
        text(stored) ?? L10n.string(stored)
    }

    /// What became of a confirmed order when it did not go well: why, and what to do next.
    static func outcome(of result: ManualCommandResult) -> String? {
        switch result.status {
        case "rejected": reason(result.reason ?? "not_sent")
        case "broker_rejected": reason(result.reason ?? "broker_rejected")
        case "uncertain": reason("uncertain")
        default: result.reason.map(reason)
        }
    }

    private static let known: [String: String] = [
        // Saving the call in an account.
        "copying_not_started": "Copying hasn't started. Start Copying, then try again.",
        "account_not_running": "This account isn't running. Start Copying for it, then try again.",
        "account_unavailable": "This account can't be reached. Check Accounts, then review again.",
        "call_not_received": "This account never got this call. Close this and pick another account.",
        "call_not_waiting": "This call no longer waits in this account. See Activity for why.",
        "call_changed": "The post changed after you opened it. Close this and open it again.",
        "correction_conflict": "Accounts disagree on this correction. Close this and review again.",
        "identity_conflict": "This was already used for a different order. Review again.",
        "record_failed": "Couldn't save the call in this account. Try again.",
        "post_unavailable": "CopyTrading can't read this post now. Close this and open it again.",
        "post_ignored": "CopyTrading set this post aside as chat, so there's nothing to copy.",
        "records_unreadable": "An account's records can't be read. Check Accounts and try again.",
        "correction_failed": "The call couldn't be saved. Nothing was placed. Try again.",

        // Checking and confirming the order.
        "correction_incomplete": "This call isn't saved in every account you chose. Review again.",
        "account_identity_changed": "This account's broker changed. Check Accounts, then review again.",
        "preview_missing": "The check for this order is gone. Review again.",
        "preview_failed": "The order couldn't be checked. Nothing was placed. Review again.",
        "preview_expired": "The check expired before you confirmed. Review again.",
        "correction_changed": "The call changed after you reviewed it. Review again.",
        "configuration_changed": "Your settings changed after you reviewed it. Review again.",
        "account_facts_changed": "The account changed after you reviewed it. Review again.",
        "plan_changed": "The order would be different now. Review again.",
        "related_manual_action": "You already placed this call by hand. Check the account's orders.",
        "wait_pending_order": "An earlier order for this stock is still open. Wait for it to end.",
        "unresolved_order_incident": "An earlier order needs your review. Settle it in Accounts first.",
        "unresolved_account_order": "An open order at Alpaca needs your review first. Settle it in Accounts.",
        "incomplete_account_orders": "Alpaca's order list was incomplete. Review again in a moment.",
        "external_open_order": "Another open order for this stock is in the way. Wait or cancel it.",

        // The account or the market.
        "account_disabled": "This account hasn't started copying. Start it, then review again.",
        "account_paused": "Copying is stopped for this account. Start it, then review again.",
        "manual_resume_required": "Start Copying for this account after the restart, then review again.",
        "recovery_pending": "Still checking the account after a restart. Review again in a minute.",
        "halted": "Copying is paused. Start Copying, then review again.",
        "waiting_expired": "This call's trading day is over, so it can't be copied now.",
        "outside_session": "The market is closed. Review again when it opens.",
        "market_facts_unavailable": "Alpaca couldn't be reached. Review again in a moment.",
        "preview_unavailable": "The order couldn't be checked just now. Review again.",
        "account_risk_unavailable": "Risk couldn't be checked. Review again in a moment.",
        "quote_unavailable": "No price quote was available. Review again in a moment.",
        "quote_stale": "The price quote was too old. Review again in a moment.",
        "quote_above_limit": "The price moved above your limit, so it may not fill.",
        "overnight_not_supported": "Alpaca doesn't trade this stock overnight. Review in the day session.",
        "overnight_halted": "Overnight trading in this stock is halted. Review in the day session.",
        "unsupported_asset": "Alpaca doesn't trade this symbol. Change the stock and review again.",
        "account_blocked": "Alpaca has blocked this account. Check it with Alpaca.",
        "crypto_paper_only": "Crypto trades on paper accounts only. Change to a paper account.",

        // Your limits and holdings.
        "daily_loss_cap": "Your daily loss limit was reached. Raise it in Connections or wait.",
        "daily_entry_cap": "Your daily entry limit was reached. Raise it in Connections or wait.",
        "total_exposure_cap": "Total exposure limit reached. Raise it in Connections or lower the size.",
        "symbol_exposure_cap": "Per-stock limit reached. Raise it in Connections or lower the size.",
        "symbol_and_total_exposure_cap": "Exposure limits reached. Raise them in Connections or lower the size.",
        "insufficient_cash": "Not enough cash for this order. Lower the size, then review again.",
        "below_minimum_budget": "The order is below the minimum size. Raise it, then review again.",
        "below_minimum_quantity": "That's less than one share. Raise the size, then review again.",
        "invalid_price_tick": "That price isn't a valid tick. Change the price, then review again.",
        "exits_disabled": "Copy exits is off for this account. Turn it on in Connections.",
        "ownership_incident": "This stock's holdings need your review first. Settle it in Accounts.",
        "position_mismatch": "CopyTrading's count differs from Alpaca's. Settle it in Accounts.",
        "lot_unavailable": "You hold no shares of this call to sell. Check the account's holdings.",
        "missing_or_ambiguous_lot": "Several copied buys match. Name the buy price, then review again.",
        "named_buy_not_held": "None of your buys is at that price. Change it, then review again.",
        "bought_after_sell": "Every buy is newer than this sell. See the account page to sell.",
        "already_selling": "Open sells already cover these shares. Wait for them to end.",
        "insufficient_owned_shares": "Not enough copied shares to sell. Lower the size, then review again.",

        // What became of the order.
        "broker_rejected": "Alpaca turned this order down. Check its orders, then review again.",
        "not_sent": "It wasn't sent: things changed just before. Review again.",
        "uncertain": "Alpaca didn't confirm this order. Check the account's orders first.",
        "confirm_failed": "Couldn't confirm it was placed. Check the account's orders first.",
        "status_failed": "This order's status couldn't be read. Try again in a moment.",
        "history_failed": "Earlier orders couldn't be loaded. Close this and open it again.",
        "command_not_found": "This order isn't in the account's records. Close this and open it again.",
    ]
}
