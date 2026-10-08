"""The app's words for the engine's codes, so the assistant reads and repeats what the owner sees.

`REASONS` mirrors the app's `Reason.swift`; `test_wording.py` keeps the two in step.
"""

import datetime as dt
from decimal import Decimal

REASONS = {
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
    "outside_open_orders": "Cancel the orders open at Alpaca first",
    "broker_account_inactive": "Alpaca has not activated this account",
    "account_risk_unavailable": "Risk could not be checked",
    "recovery_pending": "Still checking the account after a restart",
    "outside_session": "The market was closed",
    "overnight_halted": "Overnight trading was halted",
    "overnight_not_supported": "Overnight trading is not supported",
    "quote_unavailable": "No price quote was available",
    "quote_stale": "The price quote was too old",
    "quote_above_limit": "The price moved above your limit",
    "total_exposure_cap": "Your total exposure limit was reached",
    "symbol_exposure_cap": "Your per-stock limit was reached",
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
    "missing_or_ambiguous_lot": "You don't hold a copied buy at that price",
    "wait_pending_order": "Waiting for an earlier order",
    "external_open_order": "Another open order is in the way",
    "ownership_incident": "Holdings need your review",
    "position_mismatch": "Holdings differ from the broker",
    "duplicate": "A repeat of an earlier call",
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
    "stale_signal": "Too old to copy",
    "source_profile_not_configured": "No guru is set up for this poster",
    "evidence_validation_failed": "The model's reading didn't match the post",
    "invalid_model_output": "The model's answer couldn't be read",
    "model_output_budget_exceeded": "The model's answer was too long",
    "provider_timeout": "The model service didn't answer in time",
    "provider_unavailable": "The model service couldn't be reached",
    "broker_rejected": "The broker rejected the order",
    "sells_from_holdings": "Sells from what the account holds",
    "unresolved_order_incident": "An earlier order needs your review",
    "unresolved_account_order": "An open order at the broker needs your review",
    "incomplete_account_orders": "The broker's order list was incomplete",
    "plan_unavailable": "The order couldn't be planned",
    "conditional": "The guru would trade only if something happens",
    "suggestion": "The guru suggested it but didn't trade",
    "unclear": "The post's meaning wasn't clear",
    "price_range": "The guru gave a price range",
    "price_at_market": "The guru said to trade at the market price",
    "price_not_given": "The post gave no price",
    "approval_required": "You asked to approve every order for this account",
    "named_buy_not_held": "None of your buys is at the buy price the guru named",
    "sell_share_not_given": "The sell doesn't say how much",
    "batch_size_not_given": "The playbook doesn't say how big a batch is",
    "repeats_an_earlier_call": "The post repeats an earlier call of the guru's",
    "repeats_a_recent_call": "A re-post of a call already copied",
    "approved_by_owner": "You approved this call",
    "waiting_expired": "Too late to copy: its trading day is over",
}

# Outcomes the app shows with its own words rather than through Reason.
OUTCOMES = {
    "order_linked": "An order was placed",
    "pending": "Still being processed",
    "done": "Done",
}

# Where an account stands, as the Accounts screen says it.
READINESS = {
    "enabled": "Taking entries",
    "enabled_waiting_for_session": "Taking entries once the market opens",
    "disabled": "Entries are off",
    "paused": "Entries are paused",
    "manual_resume_required": "Waiting for you to resume entries after a restart",
    "recovery_pending": "Still checking the account after a restart",
    "reconciliation_unavailable": "The account couldn't be checked against the broker",
    "session_unavailable": "The market hours couldn't be read",
}

ENTRIES = {"enabled": "on", "disabled": "off", "paused": "paused"}

AFTER_RESTART = {
    "manual": "waits for you to resume entries",
    "automatic": "resumes entries on its own",
}

COPYING = {
    "running": "copying",
    "degraded": "copying, with a problem",
    "starting": "starting",
    "pausing": "pausing",
    "paused": "paused",
    "stopped": "stopped",
    "failed": "stopped by an error",
}

# Why the engine refused a tool, in words the assistant can pass on.
REFUSALS = {
    "access_off": "Agent access is off in Settings.",
    "locked": "CopyTrading is locked; the owner has to unlock it first.",
    "forbidden": "The assistant isn't allowed to do that.",
    "invalid_request": "That request wasn't valid.",
    "not_found": "Nothing by that name was found.",
    "unavailable": "The engine couldn't answer right now.",
    "busy": "Something else is running; try again in a moment.",
    "cooling_down": "That was asked moments ago; try again shortly.",
    "proposal_limit": "There is already a request waiting for the owner's approval.",
    "conflict": "Something changed meanwhile; try again.",
    "expired": "That has expired.",
    "rejected": "The owner rejected it.",
    "cancelled": "The owner cancelled this answer.",
}


def plain(code: str | None, table: dict[str, str] = REASONS) -> str | None:
    """The owner's words for a code; an unknown code reads as its words, never as snake_case."""
    if code is None:
        return None
    return table.get(code) or REASONS.get(code) or OUTCOMES.get(code) or code.replace("_", " ")


def money(value: Decimal | None) -> str | None:
    """Dollars with cents and a thousands separator, signed when negative."""
    if value is None:
        return None
    sign = "-" if value < 0 else ""
    return f"{sign}${abs(value):,.2f}"


def shares(value: Decimal) -> str:
    """A share count without trailing zeros."""
    return f"{value.normalize():f}"


def when(value: dt.datetime | None) -> str | None:
    """A moment in the owner's local time, the way the app shows it: "Oct 8, 7:54 AM"."""
    if value is None:
        return None
    local = value.astimezone()
    return f"{local:%b} {local.day}, {local:%-I:%M %p}"
