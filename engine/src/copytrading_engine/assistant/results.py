"""What each tool hands the model: short, named, in the owner's words, without internal fields.

The engine's contract is for programs; the model reads these instead, so it repeats what the app
says (not codes), names gurus, writes money in dollars, and has fewer tokens to wade through.
Discord text stays under `untrusted_source_text`, which the instructions treat as data.
"""

from collections.abc import Mapping
from decimal import Decimal
from fractions import Fraction

from copytrading_engine.assistant import insights
from copytrading_engine.assistant.wording import (
    AFTER_RESTART,
    COPYING,
    ENTRIES,
    READINESS,
    money,
    plain,
    shares,
    when,
)
from copytrading_engine.control import wire

# How a model call is read, as Activity's "Read as" puts it.
ACTIONS = {"buy": "Buy", "reduce": "Sell part of", "close": "Sell all of"}


def _fraction(value: Decimal | None) -> str | None:
    """ "1/6 of a full position", the way the guru and the app say it."""
    if value is None:
        return None
    if value == 1:
        return "a full position"
    near = Fraction(value).limit_denominator(100)
    share = (
        f"{near}"
        if abs(Decimal(near.numerator) / near.denominator - value) < Decimal("1e-6")
        else f"{value:.4f}"
    )
    return f"{share} of a full position"


def _instruction(item: wire.InstructionItem) -> str:
    price = money(item.price) if item.price is not None else "the market"
    text = f"{ACTIONS[item.action]} {item.symbol} at {price}"
    size = _fraction(item.fraction)
    return f"{text}, {size}" if size else text


def _order(order: wire.OrderView) -> str:
    side = "Bought" if order.side == "buy" else "Sold"
    if order.filled_quantity > 0 and order.average_fill_price is not None:
        return (
            f"{side} {shares(order.filled_quantity)} {order.symbol} "
            f"at {money(order.average_fill_price)} ({plain(order.status)})"
        )
    return f"{order.side} order for {shares(order.quantity)} {order.symbol}: {plain(order.status)}"


def status(view: wire.StatusView) -> dict:
    processing = view.processing
    return {
        "copying": plain(processing.state, COPYING),
        "discord_connected": processing.source_connected,
        "model_ready": processing.model_ready,
        "posts_waiting_to_be_read": processing.pending_source,
        "problem": plain(processing.error_code),
        "accounts": [
            {
                "account": account.account_id,
                "entries": plain(account.entry_permission, ENTRIES),
                "standing": plain(account.readiness, READINESS),
                "after_a_restart": plain(account.recovery_preference, AFTER_RESTART),
                "problem": plain(account.error_code),
            }
            for account in view.accounts
        ],
    }


def accounts(page: wire.AccountsPage) -> dict:
    return {
        "accounts": [_account(account) for account in page.items],
        "could_not_read": [
            {"account": item.account_id, "why": plain(item.reason)} for item in page.unavailable
        ],
    }


def _account(account: wire.AccountView) -> dict:
    shaped: dict = {
        "account": account.account_id,
        "kind": account.environment,
        "entries": plain(account.entry_permission, ENTRIES),
        "standing": plain(account.readiness, READINESS),
        "after_a_restart": plain(account.recovery_preference, AFTER_RESTART),
        "in_stocks": money(account.total_exposure_usd),
        "positions": [
            {
                "stock": position.symbol,
                "copied_shares": shares(position.owned_qty),
                "owners_own_shares": shares(position.external_qty),
                "copied_buys": [
                    {
                        "shares": shares(lot.remaining_qty),
                        "bought_at": money(lot.average_price),
                        "bought": when(lot.bought_at),
                    }
                    for lot in position.lots
                ],
            }
            for position in account.positions
        ],
    }
    if account.balance is not None:
        shaped["balance"] = {
            "equity": money(account.balance.equity),
            "today": money(account.balance.day_change_usd),
            "cash": money(account.balance.cash),
            "buying_power": money(account.balance.buying_power),
            "as_of": when(account.balance.observed_at),
        }
    if account.ownership_incidents:
        shaped["holdings_need_review"] = account.ownership_incidents
    if account.pending_orders:
        shaped["open_orders"] = account.pending_orders
    for name, status_, reason in (
        ("risk_check", account.risk_status, account.risk_reason),
        ("broker_activity_check", account.activity_status, account.activity_reason),
    ):
        if status_ != "ready":
            shaped[name] = plain(reason) or plain(status_)
    return shaped


def activity(page: wire.ActivityPage, guru_names: Mapping[str, str]) -> dict:
    return {
        "posts": [_post(item, guru_names) for item in page.items],
        "posts_not_read": [
            {"post": item.source_id, "when": when(item.rejected_at), "why": plain(item.reason)}
            for item in page.rejected
        ],
        "could_not_read": [
            {"account": item.account_id, "why": plain(item.reason)} for item in page.unavailable
        ],
    }


def _post(item: wire.ActivityItem, guru_names: Mapping[str, str]) -> dict:
    shaped: dict = {
        "post": item.source_id,
        "when": when(item.source_at),
        "guru": guru_names.get(item.guru_id or "", item.guru_id),
        "untrusted_source_text": item.untrusted_source_text,
        "read_as": [_instruction(instruction) for instruction in item.understood_as],
    }
    if item.parser_reason:
        shaped["why_not_a_trade"] = plain(item.parser_reason)
    shaped["accounts"] = [
        {
            "account": destination.account_id,
            "outcome": [plain(code) for code in destination.instruction_outcomes]
            or [plain(destination.status)],
            "orders": [_order(order) for order in destination.orders],
        }
        for destination in item.destinations
    ]
    return shaped


def account_events(page: wire.AccountEventsPage) -> dict:
    return {
        "account": page.account_id,
        "events": [
            {
                key: value
                for key, value in (
                    ("when", when(event.at)),
                    ("what", plain(event.kind)),
                    ("why", plain(event.reason)),
                    ("status", plain(event.status)),
                )
                if value
            }
            for event in page.items
        ],
    }


def _asks_to(subject: wire.ProposalSubject) -> str:
    match subject:
        case wire.ResumeAccountSubject():
            return f"resume entries for {subject.account_id}"
        case wire.RecoverySubject():
            return (
                f"set {subject.account_id} so that after a restart it "
                + (AFTER_RESTART[subject.preference])
            )
        case wire.ManualOrderSubject():
            return (
                f"{subject.side} {shares(subject.quantity)} {subject.symbol} "
                f"in {subject.account_id}"
            )


PROPOSAL_STATES = {
    "pending": "waiting for the owner's approval with Touch ID in the app",
    "running": "approved, being carried out",
    "succeeded": "approved and done",
    "failed": "approved but it failed",
    "outcome_unknown": "approved, outcome not known yet",
    "rejected": "the owner rejected it",
    "expired": "expired before the owner approved it",
    "discarded": "discarded",
}


def proposal(view: wire.ProposalView) -> dict:
    return {
        "request": view.proposal_id,
        "asks_to": _asks_to(view.subject),
        "state": PROPOSAL_STATES[view.state],
        "expires": when(view.expires_at),
    }


def proposals(page: wire.ProposalsPage) -> dict:
    return {"requests": [proposal(view) for view in page.items]}


def paused(view: wire.ProcessingPaused) -> dict:
    return {"copying": plain(view.processing.state, COPYING)}


def account_control(view: wire.AccountControlView) -> dict:
    return {
        "account": view.account_id,
        "entries": plain(view.entry_permission, ENTRIES),
        "after_a_restart": plain(view.recovery_preference, AFTER_RESTART),
        "done": when(view.applied_at),
    }


def result(view: wire.Result, guru_names: Mapping[str, str]) -> dict:
    """The model's view of one control result."""
    match view:
        case wire.StatusView():
            return status(view)
        case wire.AccountsPage():
            return accounts(view)
        case wire.ActivityPage():
            return activity(view, guru_names)
        case wire.AccountEventsPage():
            return account_events(view)
        case wire.ProposalView():
            return proposal(view)
        case wire.ProposalsPage():
            return proposals(view)
        case wire.ProcessingPaused():
            return paused(view)
        case wire.AccountControlView():
            return account_control(view)
        case _:
            return view.model_dump(mode="json")


def guru_record(record: insights.GuruRecord, name: str) -> dict:
    return {
        "guru": name,
        "days": record.days,
        "posts": record.posts,
        "calls": record.calls,
        "copied": record.copied,
        "skipped": {plain(code): count for code, count in record.skipped.items()},
    }


def skip(explanation: insights.SkipExplanation) -> dict:
    return {
        "post": explanation.source_id,
        "untrusted_source_text": explanation.untrusted_source_text,
        "read_as": explanation.understood_as,
        "accounts": [
            {"account": account.account_id, "outcome": account.reason}
            for account in explanation.accounts
        ],
    }
