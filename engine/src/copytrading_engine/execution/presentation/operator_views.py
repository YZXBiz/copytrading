"""Operator read views of one execution account: exposure, destinations, and journal events."""

import datetime as dt
from decimal import Decimal
from typing import Literal

from pydantic import AwareDatetime

from copytrading_engine.execution.domain.events import (
    AccountControlChanged,
    BrokerAcknowledged,
    CancelRequested,
    JournalEvent,
    Message,
    OrderPrepared,
    OrderUpdate,
    SubmissionAborted,
    SubmissionQuote,
    SubmitError,
    SubmitStarted,
)
from copytrading_engine.execution.domain.events import Skipped as SkippedEvent
from copytrading_engine.execution.domain.ledger_state import LedgerSnapshot
from copytrading_engine.execution.domain.market import Account, Position
from copytrading_engine.execution.domain.orders import OwnedLot
from copytrading_engine.execution.domain.ownership import OwnershipInspection
from copytrading_engine.execution.domain.progress import InstructionProgress, Skipped
from copytrading_engine.execution.domain.values import Money, Positive, Quantity, Value

EXCERPT_LENGTH = 140


class LotView(Value):
    """One block of shares the copier bought, and the post that bought it."""

    lot_id: str
    source_id: str | None
    guru_id: str | None
    posted_at: AwareDatetime | None
    excerpt: str | None
    bought_at: AwareDatetime | None
    original_qty: Quantity
    remaining_qty: Quantity
    average_price: Positive
    #: The lot's remaining shares at the broker's current price, against what they cost.
    unrealized_pl: Money | None = None


class PositionView(Value):
    """One symbol: the shares CopyTrading bought, the owner's own, and the broker's valuation of
    the whole position. Prices are the broker's; missing when the broker was not read."""

    symbol: str
    owned_qty: Quantity
    external_qty: Quantity
    broker_qty: str | None = None
    lots: tuple[LotView, ...] = ()
    avg_entry_price: Money | None = None
    current_price: Money | None = None
    market_value: Money | None = None
    unrealized_pl: Money | None = None
    unrealized_plpc: Money | None = None


class OwnershipIncidentView(Value):
    incident_id: str
    symbol: str
    expected_qty: Quantity
    actual_qty: str
    observed_at: AwareDatetime
    cause: str


class AccountBalanceView(Value):
    """The broker's own valuation of the account at `observed_at`; the app never computes it."""

    equity: Money
    previous_close_equity: Money
    day_change_usd: Money
    cash: Money
    buying_power: Money
    observed_at: AwareDatetime


def account_balance(account: Account, observed_at: dt.datetime) -> AccountBalanceView:
    return AccountBalanceView(
        equity=account.equity,
        previous_close_equity=account.last_equity,
        day_change_usd=account.equity - account.last_equity,
        cash=account.cash,
        buying_power=account.buying_power,
        observed_at=observed_at,
    )


class AccountOverview(Value):
    account_id: str
    environment: Literal["paper", "live"]
    active_configuration: bool
    broker_identity: str
    entry_permission: str
    recovery_preference: str
    readiness: str
    account_risk_status: str
    account_risk_reason: str | None
    account_activity_status: str
    account_activity_reason: str | None
    total_exposure_usd: Quantity | None
    app_cost_basis_usd: Quantity | None
    positions: tuple[PositionView, ...]
    unresolved_incidents: tuple[str, ...]
    ownership_incidents: tuple[OwnershipIncidentView, ...]
    pending_orders: int | None
    balance: AccountBalanceView | None


type UnavailableReason = Literal["timeout", "read_failed"]


class AccountUnavailable(Value):
    """An account whose evidence could not be read for this page; never shown as empty."""

    account_id: str
    reason: UnavailableReason


class AccountOverviewPage(Value):
    items: tuple[AccountOverview, ...]
    next_before_account_id: str | None = None
    unavailable_accounts: tuple[AccountUnavailable, ...] = ()


class OrderView(Value):
    client_id: str
    symbol: str
    side: str
    status: str
    quantity: Quantity
    filled_quantity: Quantity
    limit_price: Positive | None
    average_fill_price: Positive | None
    broker_id: str | None
    created_at: AwareDatetime
    # How the order went out: its type and session, the guru's price, and how far above it a
    # buy was allowed to pay.
    order_type: Literal["market", "limit"] | None = None
    session: str | None = None
    source_price: Positive | None = None
    entry_tolerance_pct: Quantity | None = None
    submitted_at: AwareDatetime | None = None
    # The quote when it was sent, for "your limit was $201.00; PM was offered at $208.86".
    quote_bid: Quantity | None = None
    quote_ask: Quantity | None = None
    # Why it ended unfilled: CopyTrading's own cancel (timeout, replaced_by_sell,
    # copying_stopped), Alpaca's (cancelled_at_broker, expired), or rejected.
    cancel_reason: str | None = None
    ended_at: AwareDatetime | None = None
    # Which of the post's calls this order places, and for a buy what the call asked for and
    # what the maximum per order allowed of it (ADR-0007).
    instruction_index: int
    requested_usd: Positive | None
    budget_usd: Positive | None


class LimitHit(Value):
    """The limit a skipped call would have passed, with its numbers."""

    part: int
    scope: Literal["symbol", "total"]
    current: Quantity
    proposed: Quantity
    limit: Quantity


type Step = Literal[
    "received",
    "held",
    "resumed",
    "skipped",
    "sized",
    "sent",
    "accepted",
    "partially_filled",
    "filled",
    "cancel_requested",
    "cancelled",
    "expired",
    "rejected",
    "failed",
]


class TimelineStep(Value):
    """One moment of a post's trip through an account, read from the account's journal."""

    step: Step
    at: AwareDatetime
    client_id: str | None = None
    reason: str | None = None
    quantity: Quantity | None = None
    price: Positive | None = None


class DestinationView(Value):
    account_id: str
    environment: str
    status: str
    instruction_outcomes: tuple[str, ...]
    limits_hit: tuple[LimitHit, ...]
    orders: tuple[OrderView, ...]
    timeline: tuple[TimelineStep, ...] = ()


class AccountEventView(Value):
    sequence: int
    at: AwareDatetime
    kind: str
    message_id: str | None = None
    order_id: str | None = None
    reason: str | None = None
    status: str | None = None


class AccountEventPage(Value):
    account_id: str
    items: tuple[AccountEventView, ...]
    next_before_seq: int | None = None


def _lot_view(
    key: str, lot: OwnedLot, snapshot: LedgerSnapshot, current_price: Decimal | None
) -> LotView:
    """A lot is keyed by the buy order that opened it, which names the post it came from."""
    order = snapshot.orders.get(key)
    message = snapshot.messages.get(order.message_id) if order is not None else None
    return LotView(
        lot_id=key,
        source_id=message.key if message is not None else None,
        guru_id=message.guru_id if message is not None else None,
        posted_at=message.timestamp if message is not None else None,
        excerpt=_excerpt(message.text) if message is not None else None,
        bought_at=order.created_at if order is not None else None,
        original_qty=lot.original_qty,
        remaining_qty=lot.remaining_qty,
        average_price=lot.average_price,
        unrealized_pl=(
            ((current_price - lot.average_price) * lot.remaining_qty).quantize(Decimal("0.01"))
            if current_price is not None
            else None
        ),
    )


def _lot_order(lot: LotView) -> tuple[bool, dt.datetime, str]:
    """Oldest first; a lot without its buy record goes last."""
    earliest = dt.datetime.min.replace(tzinfo=dt.UTC)
    return (lot.bought_at is None, lot.bought_at or earliest, lot.lot_id)


def _excerpt(text: str) -> str | None:
    words = " ".join(text.split())
    if not words:
        return None
    return words if len(words) <= EXCERPT_LENGTH else words[: EXCERPT_LENGTH - 1].rstrip() + "…"


def account_overview(
    snapshot: LedgerSnapshot,
    inspection: OwnershipInspection | None,
    *,
    local_account_id: str,
    active_configuration: bool,
    readiness: str,
    balance: AccountBalanceView | None,
) -> AccountOverview:
    if snapshot.account_id is None or snapshot.environment is None:
        raise RuntimeError("Account evidence has no verified identity")
    held = {item.symbol: item for item in inspection.broker_positions} if inspection else {}
    owned: dict[str, Decimal] = {}
    lots: dict[str, list[LotView]] = {}
    for key, lot in snapshot.lots.items():
        owned[lot.symbol] = owned.get(lot.symbol, Decimal(0)) + lot.remaining_qty
        if lot.remaining_qty > 0:
            price = held[lot.symbol].current_price if lot.symbol in held else None
            lots.setdefault(lot.symbol, []).append(_lot_view(key, lot, snapshot, price))
    broker = {symbol: item.qty for symbol, item in held.items()}
    symbols = sorted(set(owned) | set(snapshot.external_positions) | set(broker))
    positions = tuple(
        PositionView(
            symbol=symbol,
            owned_qty=owned.get(symbol, Decimal(0)),
            external_qty=snapshot.external_positions[symbol].qty
            if symbol in snapshot.external_positions
            else Decimal(0),
            broker_qty=str(broker[symbol]) if symbol in broker else None,
            lots=tuple(sorted(lots.get(symbol, ()), key=_lot_order)),
            **(held[symbol].model_dump(include=set(Position.VALUATION)) if symbol in held else {}),
        )
        for symbol in symbols
    )
    incidents = tuple(
        sorted(
            [
                item.incident_id
                for item in snapshot.ownership_incidents.values()
                if not item.resolved
            ]
            + [item.client_id for item in snapshot.late_order_incidents.values() if item.unresolved]
        )
    )
    app_cost = sum(
        (lot.remaining_qty * lot.average_price for lot in snapshot.lots.values()), Decimal(0)
    )
    return AccountOverview(
        account_id=local_account_id,
        environment=snapshot.environment,
        active_configuration=active_configuration,
        broker_identity=snapshot.account_id,
        entry_permission=snapshot.control.entry_permission,
        recovery_preference=snapshot.control.recovery_preference,
        readiness=readiness,
        account_risk_status=inspection.account_risk_status if inspection else "unavailable",
        account_risk_reason=inspection.account_risk_reason if inspection else "not_checked",
        account_activity_status=inspection.account_activity_status if inspection else "unavailable",
        account_activity_reason=inspection.account_activity_reason if inspection else "not_checked",
        total_exposure_usd=inspection.total_exposure_usd if inspection else None,
        app_cost_basis_usd=app_cost,
        positions=positions,
        unresolved_incidents=incidents,
        ownership_incidents=tuple(
            OwnershipIncidentView(
                incident_id=item.incident_id,
                symbol=item.symbol,
                expected_qty=item.expected_qty,
                actual_qty=str(item.actual_qty),
                observed_at=item.observed_at,
                cause=item.cause,
            )
            for item in snapshot.ownership_incidents.values()
            if not item.resolved
        ),
        pending_orders=sum(order.pending for order in snapshot.orders.values()),
        balance=balance,
    )


_ENDED: dict[str, Step] = {"canceled": "cancelled", "expired": "expired", "rejected": "rejected"}
_UPDATES = {"partially_filled", "filled", "cancelled", "expired", "rejected"}
_STEP_ORDER: tuple[Step, ...] = (
    "received",
    "held",
    "resumed",
    "skipped",
    "sized",
    "sent",
    "accepted",
    "partially_filled",
    "filled",
    "cancel_requested",
    "cancelled",
    "expired",
    "rejected",
    "failed",
)
_FILLS: dict[str, Step] = {"partially_filled": "partially_filled", "filled": "filled"}


def _timeline(
    events: tuple[JournalEvent, ...], resumes: tuple[dt.datetime, ...]
) -> tuple[TimelineStep, ...]:
    """A post's steps in one account, in the order they happened. A resume between the post
    reaching the account and its first decision means the buy was held for the owner."""
    steps: list[TimelineStep] = []
    seen: set[tuple[str, str]] = set()
    for event in events:
        payload, at = event.payload, event.at
        match payload:
            case Message():
                steps.append(TimelineStep(step="received", at=at))
            case SkippedEvent():
                steps.append(TimelineStep(step="skipped", at=at, reason=payload.reason))
            case OrderPrepared():
                steps.append(
                    TimelineStep(
                        step="sized",
                        at=at,
                        client_id=payload.client_id,
                        quantity=payload.qty,
                        price=payload.limit_price,
                    )
                )
            case SubmitStarted():
                steps.append(TimelineStep(step="sent", at=at, client_id=payload.client_id))
            case BrokerAcknowledged():
                steps.append(TimelineStep(step="accepted", at=at, client_id=payload.client_id))
            case CancelRequested():
                steps.append(
                    TimelineStep(
                        step="cancel_requested",
                        at=at,
                        client_id=payload.client_id,
                        reason=payload.reason,
                    )
                )
            case SubmitError() | SubmissionAborted():
                reason = (
                    payload.reason if isinstance(payload, SubmissionAborted) else "submit_error"
                )
                steps.append(
                    TimelineStep(step="failed", at=at, client_id=payload.client_id, reason=reason)
                )
            case OrderUpdate():
                status = payload.status.value
                step = _FILLS.get(status) or _ENDED.get(status)
                key = (payload.client_id, f"{status}:{payload.filled_qty}")
                if step is None or key in seen:
                    continue
                seen.add(key)
                steps.append(
                    TimelineStep(
                        step=step,
                        at=at,
                        client_id=payload.client_id,
                        quantity=payload.filled_qty if step in _FILLS.values() else None,
                        price=payload.filled_avg_price,
                    )
                )
            case _:
                continue
    # Alpaca's answer to a submit can already carry the fill, written just before the
    # acknowledgement: the order was accepted no later than its first update.
    first_update: dict[str, dt.datetime] = {}
    for step in steps:
        if step.client_id is not None and step.step in _UPDATES:
            first_update.setdefault(step.client_id, step.at)
    steps = [
        step.model_copy(update={"at": min(step.at, first_update[step.client_id])})
        if step.step == "accepted" and step.client_id in first_update
        else step
        for step in steps
    ]
    received = next((step.at for step in steps if step.step == "received"), None)
    decided = next((step.at for step in steps if step.step in {"sized", "skipped", "failed"}), None)
    if received is not None and decided is not None:
        held = [at for at in resumes if received <= at <= decided]
        if held:
            steps.append(TimelineStep(step="held", at=received, reason="waiting_for_resume"))
            steps.append(TimelineStep(step="resumed", at=held[0]))
    # Steps recorded in the same instant read in the order they happen.
    order = {name: index for index, name in enumerate(_STEP_ORDER)}
    return tuple(sorted(steps, key=lambda step: (step.at, order[step.step])))


# Orders cancelled before the reason was recorded: a cancel of CopyTrading's own unfilled order this
# long after it went out is read as the order timeout, by far the usual cause; newer orders say.
_TIMEOUT_EVIDENCE_SECONDS = 30


def _older_cancel_reason(submitted_at: object, cancelled_at: dt.datetime) -> str:
    if isinstance(submitted_at, dt.datetime):
        if (cancelled_at - submitted_at).total_seconds() >= _TIMEOUT_EVIDENCE_SECONDS:
            return "timeout"
    return "cancel_requested"


def _order_detail(order_events: tuple[JournalEvent, ...]) -> dict[str, object]:
    """What the journal adds to an order: how it went out, the quote then, and how it ended."""
    detail: dict[str, object] = {}
    requested: str | None = None
    for event in order_events:
        payload = event.payload
        match payload:
            case OrderPrepared():
                detail.update(
                    order_type=payload.type,
                    session=payload.session.value,
                    source_price=payload.source_price,
                    entry_tolerance_pct=payload.entry_tolerance_pct,
                )
            case SubmitStarted():
                detail["submitted_at"] = payload.submit_started_at
            case SubmissionQuote():
                detail.update(quote_bid=payload.quote.bid, quote_ask=payload.quote.ask)
            case CancelRequested():
                requested = payload.reason or _older_cancel_reason(
                    detail.get("submitted_at"), event.at
                )
            case OrderUpdate() if payload.status.value in _ENDED:
                status = payload.status.value
                detail["ended_at"] = event.at
                if status == "canceled":
                    detail["cancel_reason"] = requested or "cancelled_at_broker"
                else:
                    detail["cancel_reason"] = status
            case _:
                continue
    return detail


def destination_views(
    snapshot: LedgerSnapshot,
    source_ids: set[str],
    events: tuple[JournalEvent, ...] = (),
) -> dict[str, DestinationView]:
    if snapshot.account_id is None or snapshot.environment is None:
        return {}
    views: dict[str, DestinationView] = {}
    # Posts the owner has acted on by hand: a call held for approval is then no longer waiting.
    approved = {
        command.source_id
        for command in snapshot.manual_commands.values()
        if command.state == "prepared"
    }
    by_message: dict[str, list[JournalEvent]] = {}
    by_order: dict[str, list[JournalEvent]] = {}
    resumes: list[dt.datetime] = []
    for event in events:
        payload = event.payload
        if isinstance(payload, AccountControlChanged):
            if payload.result.command.action == "resume":
                resumes.append(payload.result.applied_at)
            continue
        message_id = getattr(payload, "message_id", None)
        if message_id is not None:
            by_message.setdefault(message_id, []).append(event)
        client_id = getattr(payload, "client_id", None)
        if client_id is not None:
            by_order.setdefault(client_id, []).append(event)
    for message in snapshot.messages.values():
        source_id = f"{message.source}:{message.channel_id}:{message.id}"
        if source_id not in source_ids:
            continue
        orders = tuple(
            OrderView(
                client_id=order.client_id,
                symbol=order.symbol,
                side=order.side,
                status=order.status.value,
                quantity=order.qty,
                filled_quantity=order.filled_qty,
                limit_price=order.limit_price,
                average_fill_price=order.filled_avg_price,
                broker_id=order.broker_id,
                created_at=order.created_at,
                instruction_index=order.instruction_index,
                requested_usd=order.requested_usd,
                budget_usd=order.budget_usd,
            ).model_copy(update=_order_detail(tuple(by_order.get(order.client_id, ()))))
            for order in snapshot.orders.values()
            if order.message_id == message.key
        )
        views[source_id] = DestinationView(
            account_id=message.destination.connection.account_id,
            environment=snapshot.environment,
            status=message.status,
            instruction_outcomes=tuple(
                _outcome(part, approved=source_id in approved) for part in message.parts
            ),
            limits_hit=tuple(
                LimitHit(part=index, **exposure.model_dump())
                for index, part in enumerate(message.parts)
                if isinstance(part, Skipped)
                for exposure in part.exposure
            ),
            orders=orders,
            timeline=_timeline(tuple(by_message.get(message.key, ())), tuple(resumes)),
        )
    return views


def _outcome(part: InstructionProgress, *, approved: bool) -> str:
    if not isinstance(part, Skipped):
        return part.kind
    if part.reason == "approval_required" and approved:
        return "approved_by_owner"
    return part.reason


def event_page(
    account_id: str, rows: tuple[tuple[int, JournalEvent], ...], limit: int
) -> AccountEventPage:
    items = tuple(_event_view(seq, event) for seq, event in rows)
    return AccountEventPage(
        account_id=account_id,
        items=items,
        next_before_seq=items[-1].sequence if len(items) == limit else None,
    )


def _event_view(seq: int, event: JournalEvent) -> AccountEventView:
    payload = event.payload
    if isinstance(payload, AccountControlChanged):
        # The action says what the owner changed; a recovery change also says to what.
        command = payload.result.command
        return AccountEventView(
            sequence=seq,
            at=event.at,
            kind=payload.kind,
            reason=command.action,
            status=command.recovery_preference,
        )
    return AccountEventView(
        sequence=seq,
        at=event.at,
        kind=payload.kind,
        message_id=getattr(payload, "message_id", None),
        order_id=getattr(payload, "client_id", None),
        reason=getattr(payload, "reason", None),
        status=str(getattr(payload, "status", "")) or None,
    )
