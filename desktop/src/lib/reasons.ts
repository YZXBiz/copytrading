import type { ManualCommandResult } from "../../shared/contract"

// Engine reason codes in the words a trader would use: Reason.swift for skips and refusals everywhere,
// ManualRefusalText.swift for the by-hand flow, which says why and then what to do. A code with no sentence
// here reads as its words, never as snake_case.
const KNOWN: Record<string, string> = {
  partial_symbol: "The ticker is not a whole word in the post",
  lot_unavailable: "CopyTrading holds none of these shares",
  preview_expired: "The price check ran out before you confirmed",
  account_facts_changed: "The account changed since you reviewed the sale",
  account_changed: "The account changed since you reviewed the sale",
  plan_changed: "The order would be different now",
  related_manual_action: "A sale of these shares is already under way",
  market_facts_unavailable: "The broker could not be reached",
  preview_unavailable: "The sale could not be checked",
  account_disabled: "Copying into this account is off",
  account_paused: "Copying into this account is stopped",
  account_blocked: "The broker blocked this account",
  account_unavailable: "The account could not be reached",
  outside_open_orders: "Cancel the orders open at Alpaca first",
  broker_account_inactive: "Alpaca has not activated this account",
  account_in_use: "Another CopyTrading on this Mac is copying into this account",
  record_unreadable: "Its record on this Mac couldn't be read",
  alpaca_account_shared: "Another account in this setup uses keys for the same Alpaca account",
  broker_keys_rejected: "Alpaca didn't accept the API keys",
  broker_unreachable: "Alpaca couldn't be reached",
  accounts_unavailable: "More than one account couldn't open",
  storage_unavailable: "CopyTrading couldn't open its data on this Mac",
  routing_state_unavailable: "CopyTrading couldn't read its saved gurus",
  processing_unavailable: "Copying stopped unexpectedly",
  activation_journal_unavailable: "CopyTrading couldn't record the start",
  notification_unavailable: "Alerts couldn't be sent",
  source_unavailable: "Discord could not be reached",
  source_unauthorized: "Discord turned down the token",
  account_risk_unavailable: "Risk could not be checked",
  recovery_pending: "Still checking the account after a restart",
  manual_resume_required: "This account waits for its Start Copying after the restart",
  stale_during_recovery: "Too old by the time the account's restart checks finished",
  stale_waiting_for_resume: "Waited for the account's Start Copying after the restart, and got too old",
  outside_session: "The market was closed",
  overnight_halted: "Overnight trading was halted",
  overnight_not_supported: "Overnight trading is not supported",
  quote_unavailable: "No price quote was available",
  quote_stale: "The price quote was too old",
  quote_above_limit: "The price moved above your limit",
  total_exposure_cap: "Your total exposure limit was reached",
  symbol_exposure_cap: "Your per-stock limit was reached",
  symbol_and_total_exposure_cap: "Your exposure limits were reached",
  daily_loss_cap: "Your daily loss limit was reached",
  daily_entry_cap: "Your daily entry limit was reached",
  insufficient_cash: "Not enough cash",
  insufficient_owned_shares: "No shares left to sell",
  below_minimum_budget: "The order was below the minimum size",
  below_minimum_quantity: "The order was below one share",
  below_minimum_order_size: "Less is left than the coin's smallest order",
  exits_disabled: "Copying exits is off",
  unsupported_asset: "The broker does not support this symbol",
  crypto_paper_only: "Crypto is copied on paper accounts only, and this account is live",
  invalid_price_tick: "The price was not a valid tick",
  missing_or_ambiguous_lot: "You don't hold a copied buy at that price",
  wait_pending_order: "Waiting for an earlier order",
  external_open_order: "Another open order is in the way",
  ownership_incident: "Holdings need your review",
  position_mismatch: "Holdings differ from the broker",
  follow_stops_off: "Following the guru's stops is off",
  stop_buy_not_filled: "The buy this stop protects did not fill",
  stop_buy_not_held: "CopyTrading holds none of the buy this stop protects",
  stop_buy_not_made: "The buy this stop protects was not made",
  stop_not_for_coins: "Stops are not placed for coins",
  stop_nothing_left: "Nothing was left to protect",
  duplicate: "A repeat of an earlier call",
  stale: "Too old to copy: older than this account copies buys. A sell is always copied.",
  provider_rejected: "The model service refused the request",
  provider_key_rejected: "The model service didn't accept the API key",
  provider_model_not_found: "The model service has no model by that name",
  out_of_order: "Arrived out of order",
  review_required: "Needs your review",
  ignored: "Ignored",
  halted: "Copying was halted",
  session_changed: "The market session changed",
  processing_stopped: "Copying is paused",
  not_checked: "Not checked yet",
  stale_signal: "Too old to copy",
  future_signal: "The post's time was ahead of this Mac's clock",
  attachments_require_human_review: "The post has a picture, so it waits for you",
  decode_attempts_exhausted: "The model couldn't read it after three tries",
  daily_model_request_budget_exhausted: "Not read: today's 2,000 model reads were used up",
  source_profile_not_configured: "No guru is set up for this poster",
  evidence_validation_failed: "The model's reading didn't match the post",
  invalid_model_output: "The model's answer couldn't be read",
  model_output_budget_exceeded: "The model's answer was too long",
  provider_timeout: "The model service didn't answer in time",
  provider_unavailable: "The model service couldn't be reached",
  broker_rejected: "The broker rejected the order",
  sells_from_holdings: "Sells from what the account holds",
  unresolved_order_incident: "An earlier order needs your review",
  unresolved_account_order: "An open order at the broker needs your review",
  incomplete_account_orders: "The broker's order list was incomplete",
  plan_unavailable: "The order couldn't be planned",
  conditional: "The guru would trade only if something happens",
  suggestion: "The guru suggested it but didn't trade",
  unclear: "The post's meaning wasn't clear",
  chatter: "Just chat, nothing to trade",
  price_range: "The guru gave a price range",
  price_at_market: "The guru said to trade at the market price",
  price_not_given: "The post gave no price",
  approval_required: "You asked to approve every order for this account",
  named_buy_not_held: "None of your buys is at the buy price the guru named",
  bought_after_sell: "Every buy it would sell was posted after this sell",
  already_selling: "Already selling these shares",
  waiting_for_quote: "Waiting for a price to sell at",
  sell_share_not_given: "The sell doesn't say how much",
  batch_size_not_given: "The playbook doesn't say how big a batch is",
  repeats_an_earlier_call: "The post repeats an earlier call of the guru's",
  repeats_a_recent_call: "A re-post of a call already copied",
  approved_by_owner: "You approved this call",
  waiting_expired: "Too late to copy: its trading day is over",
  account_ownership_pending: "An account you removed still holds what CopyTrading bought",
  routing_change_pending: "Posts were still being read or sent",
  no_open_lot: "No shares bought from this guru are held, so there is nothing to sell",
}

/** "review_required" becomes "Review required"; nothing becomes a dash. */
export function codeWords(code: string | null | undefined): string {
  if (!code) return "—"
  const text = code.replace(/[_-]/g, " ")
  return text.charAt(0).toUpperCase() + text.slice(1)
}

export const reasonText = (code: string | null | undefined): string => (code ? (KNOWN[code] ?? codeWords(code)) : "—")

/** A phrase as a sentence: capital first, full stop last. */
export function sentence(text: string): string {
  const trimmed = text.trim()
  if (!trimmed) return ""
  const cap = trimmed.charAt(0).toUpperCase() + trimmed.slice(1)
  return /[.!?]$/.test(cap) ? cap : `${cap}.`
}

const REFUSALS: Record<string, string> = {
  // Saving the call in an account.
  copying_not_started: "Copying hasn't started. Start Copying, then try again.",
  account_not_running: "This account isn't running. Start Copying for it, then try again.",
  account_unavailable: "This account can't be reached. Check Accounts, then review again.",
  call_not_received: "This account never got this call. Close this and pick another account.",
  call_not_waiting: "This call no longer waits in this account. See Activity for why.",
  call_changed: "The post changed after you opened it. Close this and open it again.",
  correction_conflict: "Accounts disagree on this correction. Close this and review again.",
  identity_conflict: "This was already used for a different order. Review again.",
  record_failed: "Couldn't save the call in this account. Try again.",
  post_unavailable: "CopyTrading can't read this post now. Close this and open it again.",
  post_ignored: "CopyTrading set this post aside as chat, so there's nothing to copy.",
  records_unreadable: "An account's records can't be read. Check Accounts and try again.",
  correction_failed: "The call couldn't be saved. Nothing was placed. Try again.",
  // Checking and confirming the order.
  correction_incomplete: "This call isn't saved in every account you chose. Review again.",
  account_identity_changed: "This account's broker changed. Check Accounts, then review again.",
  preview_missing: "The check for this order is gone. Review again.",
  preview_failed: "The order couldn't be checked. Nothing was placed. Review again.",
  preview_expired: "The check expired before you confirmed. Review again.",
  correction_changed: "The call changed after you reviewed it. Review again.",
  configuration_changed: "Your settings changed after you reviewed it. Review again.",
  account_facts_changed: "The account changed after you reviewed it. Review again.",
  plan_changed: "The order would be different now. Review again.",
  related_manual_action: "You already placed this call by hand. Check the account's orders.",
  wait_pending_order: "An earlier order for this stock is still open. Wait for it to end.",
  unresolved_order_incident: "An earlier order needs your review. Settle it in Accounts first.",
  unresolved_account_order: "An open order at Alpaca needs your review first. Settle it in Accounts.",
  incomplete_account_orders: "Alpaca's order list was incomplete. Review again in a moment.",
  external_open_order: "Another open order for this stock is in the way. Wait or cancel it.",
  // The account or the market.
  account_disabled: "This account hasn't started copying. Start it, then review again.",
  account_paused: "Copying is stopped for this account. Start it, then review again.",
  manual_resume_required: "Start Copying for this account after the restart, then review again.",
  recovery_pending: "Still checking the account after a restart. Review again in a minute.",
  halted: "Copying is paused. Start Copying, then review again.",
  waiting_expired: "This call's trading day is over, so it can't be copied now.",
  outside_session: "The market is closed. Review again when it opens.",
  market_facts_unavailable: "Alpaca couldn't be reached. Review again in a moment.",
  preview_unavailable: "The order couldn't be checked just now. Review again.",
  account_risk_unavailable: "Risk couldn't be checked. Review again in a moment.",
  quote_unavailable: "No price quote was available. Review again in a moment.",
  quote_stale: "The price quote was too old. Review again in a moment.",
  quote_above_limit: "The price moved above your limit, so it may not fill.",
  overnight_not_supported: "Alpaca doesn't trade this stock overnight. Review in the day session.",
  overnight_halted: "Overnight trading in this stock is halted. Review in the day session.",
  unsupported_asset: "Alpaca doesn't trade this symbol. Change the stock and review again.",
  account_blocked: "Alpaca has blocked this account. Check it with Alpaca.",
  crypto_paper_only: "Crypto trades on paper accounts only. Change to a paper account.",
  // Your limits and holdings.
  daily_loss_cap: "Your daily loss limit was reached. Raise it in Connections or wait.",
  daily_entry_cap: "Your daily entry limit was reached. Raise it in Connections or wait.",
  total_exposure_cap: "Total exposure limit reached. Raise it in Connections or lower the size.",
  symbol_exposure_cap: "Per-stock limit reached. Raise it in Connections or lower the size.",
  symbol_and_total_exposure_cap: "Exposure limits reached. Raise them in Connections or lower the size.",
  insufficient_cash: "Not enough cash for this order. Lower the size, then review again.",
  below_minimum_budget: "The order is below the minimum size. Raise it, then review again.",
  below_minimum_quantity: "That's less than one share. Raise the size, then review again.",
  below_minimum_order_size: "Less of this coin is left than its smallest order, so it can't be sold.",
  invalid_price_tick: "That price isn't a valid tick. Change the price, then review again.",
  exits_disabled: "Copy exits is off for this account. Turn it on in Connections.",
  ownership_incident: "This stock's holdings need your review first. Settle it in Accounts.",
  position_mismatch: "CopyTrading's count differs from Alpaca's. Settle it in Accounts.",
  lot_unavailable: "You hold no shares of this call to sell. Check the account's holdings.",
  missing_or_ambiguous_lot: "Several copied buys match. Name the buy price, then review again.",
  named_buy_not_held: "None of your buys is at that price. Change it, then review again.",
  bought_after_sell: "Every buy is newer than this sell. See the account page to sell.",
  already_selling: "Open sells already cover these shares. Wait for them to end.",
  insufficient_owned_shares: "Not enough copied shares to sell. Lower the size, then review again.",
  // What became of the order.
  broker_rejected: "Alpaca turned this order down. Check its orders, then review again.",
  not_sent: "It wasn't sent: things changed just before. Review again.",
  uncertain: "Alpaca didn't confirm this order. Check the account's orders first.",
  confirm_failed: "Couldn't confirm it was placed. Check the account's orders first.",
  status_failed: "This order's status couldn't be read. Try again in a moment.",
  history_failed: "Earlier orders couldn't be loaded. Close this and open it again.",
  command_not_found: "This order isn't in the account's records. Close this and open it again.",
}

/** An engine reason as the by-hand flow words it, else the shared wording. */
export const refusalReason = (code: string) => REFUSALS[code] ?? reasonText(code)

/** A string the review keeps for a failure: a code is worded, a sentence is said as written. */
export const refusalLine = (stored: string) => REFUSALS[stored] ?? stored

/** What became of a confirmed order when it did not go well: why, and what to do next. */
export function refusalOutcome(result: ManualCommandResult): string | null {
  switch (result.status) {
    case "rejected":
      return refusalReason(result.reason ?? "not_sent")
    case "broker_rejected":
      return refusalReason(result.reason ?? "broker_rejected")
    case "uncertain":
      return refusalReason("uncertain")
    default:
      return result.reason ? refusalReason(result.reason) : null
  }
}
