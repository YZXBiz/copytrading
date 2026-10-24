"""Whether CopyTrading copies, in the five words the owner sees everywhere.

The engine keeps every detail; what it says to the owner is one of: Copying, Sells only, Paused
(only when the owner or an approved agent paused), Stopped (a problem stopped it, and the detail
says which), or Not started. The app's `CopyingState` makes the same choice from the same facts.
"""

from dataclasses import dataclass

from copytrading_engine.control.wire import CopyingWord

# An account the engine could not open or keep: a problem, never the owner's choice.
UNHELD = frozenset(
    {
        "account_unavailable",
        "outside_open_orders",
        "broker_account_inactive",
        "account_in_use",
        "alpaca_account_shared",
        "record_unreadable",
        "broker_keys_rejected",
        "broker_unreachable",
    }
)


@dataclass(frozen=True, slots=True)
class Copying:
    """One of the five words, and a code for the line under it: why it stopped, what it waits
    for, or a warning while it still copies."""

    word: CopyingWord
    detail: str | None = None


def overall(state: str, error_code: str | None) -> Copying:
    """Copying as a whole, from the engine's processing state."""
    match state:
        case "running":
            return Copying("copying")
        case "degraded":
            # No code means the start is still finishing; a code is a warning while it copies.
            return (
                Copying("copying", error_code) if error_code else Copying("not_started", "starting")
            )
        case "starting":
            return Copying("not_started", "starting")
        case "pausing":
            return Copying("copying", "pausing")
        case "failed":
            return Copying("stopped", error_code or "processing_unavailable")
        case _:
            return Copying("paused")


def account(
    *,
    processing_state: str | None,
    active_configuration: bool,
    entry_permission: str,
    readiness: str,
    error_code: str | None = None,
    run_state: str | None = None,
) -> Copying:
    """One account. `processing_state` is None when only the account's record is at hand, whose
    readiness already says when copying is paused."""
    if not active_configuration:
        return Copying("not_started")
    if run_state == "failed" or readiness in UNHELD:
        return Copying("stopped", error_code if error_code in UNHELD else readiness)
    if processing_state == "failed":
        return Copying("stopped", "processing_unavailable")
    if processing_state in {"paused", "pausing"} or readiness == "processing_stopped":
        return Copying("paused")
    if entry_permission == "paused":
        return Copying("sells_only", "account_paused")
    if readiness == "manual_resume_required":
        return Copying("sells_only", "manual_resume_required")
    if entry_permission != "enabled":
        return Copying("not_started")
    match readiness:
        case "enabled":
            return Copying("copying")
        case "enabled_waiting_for_session" | "enabled_coins_only":
            return Copying("copying", readiness)
        case "recovery_pending" | "reconciliation_unavailable" | "session_unavailable":
            return Copying("copying", readiness)
        case _:
            return Copying("copying", readiness if readiness != "unavailable" else None)
