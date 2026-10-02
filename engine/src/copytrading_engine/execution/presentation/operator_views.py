"""Operator read views of one execution account: exposure, destinations, and journal events."""

import datetime as dt
from decimal import Decimal
from typing import Literal

from pydantic import AwareDatetime

from copytrading_engine.execution.domain.events import AccountControlChanged, JournalEvent
from copytrading_engine.execution.domain.ledger_state import LedgerSnapshot
from copytrading_engine.execution.domain.market import Account
from copytrading_engine.execution.domain.orders import OwnedLot
from copytrading_engine.execution.domain.ownership import OwnershipInspection
from copytrading_engine.execution.domain.values import Money, Positive, Quantity, Value
from copytrading_engine.shared.queue_snapshot import QueueSnapshot

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


class PositionView(Value):
    symbol: str
    owned_qty: Quantity
    external_qty: Quantity
    broker_qty: str | None = None
    lots: tuple[LotView, ...] = ()


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
    pending_reports: int | None
    oldest_report_at: AwareDatetime | None
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


class DestinationView(Value):
    account_id: str
    environment: str
    status: str
    instruction_outcomes: tuple[str, ...]
    orders: tuple[OrderView, ...]


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


def _lot_view(key: str, lot: OwnedLot, snapshot: LedgerSnapshot) -> LotView:
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
    queue: QueueSnapshot,
    *,
    local_account_id: str,
    active_configuration: bool,
    readiness: str,
    balance: AccountBalanceView | None,
) -> AccountOverview:
    if snapshot.account_id is None or snapshot.environment is None:
        raise RuntimeError("Account evidence has no verified identity")
    owned: dict[str, Decimal] = {}
    lots: dict[str, list[LotView]] = {}
    for key, lot in snapshot.lots.items():
        owned[lot.symbol] = owned.get(lot.symbol, Decimal(0)) + lot.remaining_qty
        if lot.remaining_qty > 0:
            lots.setdefault(lot.symbol, []).append(_lot_view(key, lot, snapshot))
    broker = {item.symbol: item.qty for item in inspection.broker_positions} if inspection else {}
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
        pending_reports=queue.count,
        oldest_report_at=queue.oldest_at,
        balance=balance,
    )


def destination_views(snapshot: LedgerSnapshot, source_ids: set[str]) -> dict[str, DestinationView]:
    if snapshot.account_id is None or snapshot.environment is None:
        return {}
    views: dict[str, DestinationView] = {}
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
            )
            for order in snapshot.orders.values()
            if order.message_id == message.key
        )
        views[source_id] = DestinationView(
            account_id=message.destination.connection.account_id,
            environment=snapshot.environment,
            status=message.status,
            instruction_outcomes=tuple(
                part.reason if part.kind == "skipped" else part.kind for part in message.parts
            ),
            orders=orders,
        )
    return views


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
