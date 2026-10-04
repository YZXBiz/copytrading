import Foundation

/// Engine reason codes in the words a trader would use; unknown codes fall back to `Humanize`.
enum Reason {
    static func text(_ code: String?) -> String {
        guard let code else { return "—" }
        return known[code] ?? Humanize.code(code)
    }

    /// Keeps parser identifiers out of the main explanation while preserving free readable text.
    static func parserMessage(_ raw: String?, needsReview: Bool = false) -> String? {
        guard let raw else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if let explanation = known[value] { return explanation }

        let isMachineIdentifier =
            value == value.lowercased()
            && value.contains(where: { $0 == "_" || $0 == "-" })
            && value.unicodeScalars.allSatisfy {
                CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "-"
            }
        if isMachineIdentifier {
            return needsReview ? "Review this post’s interpretation before copying." : nil
        }
        return value
    }

    private static let known: [String: String] = [
        "lot_unavailable": "These shares are no longer held",
        "preview_expired": "The price check ran out before you confirmed",
        "account_facts_changed": "The account changed since you reviewed the sale",
        "account_changed": "The account changed since you reviewed the sale",
        "plan_changed": "The order would be different now",
        "related_manual_action": "A sale of these shares is already under way",
        "market_facts_unavailable": "The broker could not be reached",
        "preview_unavailable": "The sale could not be checked",
        "account_disabled": "Entries are off for this account",
        "account_paused": "Entries are paused for this account",
        "account_blocked": "The broker blocked this account",
        "account_unavailable": "The account could not be reached",
        "account_risk_unavailable": "Risk could not be checked",
        "recovery_pending": "The account is still recovering",
        "outside_session": "The market was closed",
        "overnight_halted": "Overnight trading was halted",
        "overnight_not_supported": "Overnight trading is not supported",
        "quote_unavailable": "No price quote was available",
        "quote_stale": "The price quote was too old",
        "quote_above_limit": "The price moved above your limit",
        "total_exposure_cap": "Your total exposure limit was reached",
        "symbol_exposure_cap": "Your per-symbol limit was reached",
        "symbol_and_total_exposure_cap": "Your exposure limits were reached",
        "daily_loss_cap": "Your daily loss limit was reached",
        "daily_entry_cap": "Your daily entry limit was reached",
        "insufficient_cash": "Not enough cash",
        "insufficient_owned_shares": "No shares left to sell",
        "below_minimum_budget": "The order was below the minimum size",
        "below_minimum_quantity": "The order was below one share",
        "exits_disabled": "Copying exits is off",
        "unsupported_asset": "The broker does not support this symbol",
        "invalid_price_tick": "The price was not a valid tick",
        "missing_or_ambiguous_lot": "The matching entry could not be found",
        "missing_source_fraction": "The post did not say how much to sell",
        "missing_source_fraction_review": "The post did not say how much to sell",
        "wait_pending_order": "Waiting for an earlier order",
        "external_open_order": "Another open order is in the way",
        "ownership_incident": "Holdings need your review",
        "position_mismatch": "Holdings differ from the broker",
        "duplicate": "Already handled",
        "stale": "Too old to copy",
        "provider_rejected": "The model service refused the request",
        "provider_key_rejected": "The model service didn't accept the API key",
        "provider_model_not_found": "The model service has no model by that name",
        "out_of_order": "Arrived out of order",
        "review_required": "Needs your review",
        "halted": "Copying was halted",
        "session_changed": "The market session changed",
        "processing_stopped": "Copying is paused",
        "not_checked": "Not checked yet",
    ]
}
