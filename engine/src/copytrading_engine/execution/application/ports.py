"""Execution dependencies; broker adapters implement this interface."""

from __future__ import annotations

import datetime as dt
from collections.abc import Mapping
from contextlib import AbstractContextManager, nullcontext
from dataclasses import dataclass
from decimal import Decimal
from typing import Literal, Protocol, get_args, runtime_checkable

from copytrading_engine.execution.domain.events import JournalEvent
from copytrading_engine.execution.domain.ledger_state import LedgerSnapshot
from copytrading_engine.execution.domain.market import (
    Account,
    Asset,
    BrokerOrder,
    CalendarDay,
    EquityHistory,
    HistoryWindow,
    Position,
    Quote,
)
from copytrading_engine.execution.domain.orders import OrderRequest
from copytrading_engine.execution.domain.positions import PositionAudit


class Broker(Protocol):
    def account(self) -> Account: ...
    def asset(self, symbol: str) -> Asset: ...
    def calendar(self, date: str) -> tuple[CalendarDay, ...]: ...
    def positions(self) -> tuple[Position, ...]: ...
    def open_orders(self) -> tuple[BrokerOrder, ...]: ...
    def lookup(self, client_id: str) -> BrokerOrder | None: ...
    def submit(self, order: OrderRequest) -> BrokerOrder: ...
    def cancel(self, order_id: str) -> None: ...


@runtime_checkable
class RestoreEvidenceBroker(Protocol):
    """Narrow read-only broker capability used by restore reconciliation."""

    def restore_evidence(
        self,
        snapshot: LedgerSnapshot,
        created_at: dt.datetime,
    ) -> BrokerRestoreEvidence: ...

    def close(self) -> None: ...


@runtime_checkable
class EquityHistoryBroker(Protocol):
    """Narrow read-only broker capability behind the equity chart."""

    def equity_history(self, window: HistoryWindow) -> EquityHistory: ...


class BrokerError(Exception):
    """Sanitized broker failure; response bodies and credentials stay private."""

    def __init__(self, status: int | None = None) -> None:
        self.status = status
        super().__init__(f"Alpaca HTTP {status}" if status else "Alpaca network error")

    @property
    def transient(self) -> bool:
        """A failure that passes on its own: no connection, a timeout, a rate limit, or an
        outage on Alpaca's side. Anything else (rejected keys, a refused request) needs a person.
        """
        return self.status is None or self.status in {408, 429} or self.status >= 500


# Why a broker account cannot connect until its owner acts.
type AccountOpenRefusal = Literal[
    "outside_open_orders", "broker_account_inactive", "account_in_use"
]
ACCOUNT_OPEN_REFUSALS: frozenset[str] = frozenset(get_args(AccountOpenRefusal.__value__))


class AccountOpenRefused(RuntimeError):
    """The broker account cannot be connected until its owner acts; `reason` says why."""

    def __init__(self, reason: AccountOpenRefusal) -> None:
        self.reason = reason
        super().__init__(reason)


class BrokerResponseError(BrokerError):
    """The broker response failed validation; its delivery outcome remains uncertain."""

    def __init__(self) -> None:
        super().__init__()
        self.args = ("Alpaca response failed validation",)

    @property
    def transient(self) -> bool:
        return False


@dataclass(frozen=True, slots=True)
class BrokerTimelineEvent:
    """Broker event timestamp and exact wire precision, including sub-microseconds."""

    identifier: str
    occurred_at: dt.datetime
    resolution_nanoseconds: int
    submicrosecond_nanoseconds: int = 0

    def __post_init__(self) -> None:
        if not self.identifier:
            raise ValueError("Broker timeline event identifier is required")
        if self.occurred_at.tzinfo is None or self.occurred_at.utcoffset() is None:
            raise ValueError("Broker timeline event timestamp must be timezone-aware")
        if self.resolution_nanoseconds <= 0:
            raise ValueError("Broker timeline event resolution must be positive")
        if not 0 <= self.submicrosecond_nanoseconds < 1_000:
            raise ValueError("Broker timeline event sub-microsecond offset is invalid")

    def overlaps_or_follows(self, cutoff: dt.datetime) -> bool:
        """Return true unless the entire timestamp-resolution interval predates cutoff."""
        if cutoff.tzinfo is None or cutoff.utcoffset() is None:
            raise ValueError("Broker timeline cutoff must be timezone-aware")
        cutoff_utc = cutoff.astimezone(dt.UTC)
        event_start = _datetime_nanoseconds(self.occurred_at) + self.submicrosecond_nanoseconds
        event_end = event_start + self.resolution_nanoseconds
        return event_end > _datetime_nanoseconds(cutoff_utc)


def _datetime_nanoseconds(value: dt.datetime) -> int:
    utc_value = value.astimezone(dt.UTC)
    epoch = dt.datetime(1970, 1, 1, tzinfo=dt.UTC)
    elapsed = utc_value - epoch
    elapsed_seconds = elapsed.days * 86_400 + elapsed.seconds
    return elapsed_seconds * 1_000_000_000 + elapsed.microseconds * 1_000


@dataclass(frozen=True, slots=True)
class BrokerRestoreEvidence:
    """Read-only facts; complete means bounded queries paginated to completion.

    The order endpoint has a submitted-time cursor, not a complete updated-time
    history. This evidence is an activation check, not a full broker audit export.
    """

    account: Account
    environment: str
    positions: Mapping[str, Decimal]
    open_order_client_ids: tuple[str, ...]
    known_orders: Mapping[str, BrokerOrder]
    snapshot_started_at: dt.datetime
    order_events_near_snapshot: tuple[BrokerTimelineEvent, ...]
    activity_events_near_snapshot: tuple[BrokerTimelineEvent, ...]
    complete: bool

    @property
    def orders_after_snapshot(self) -> tuple[str, ...]:
        return tuple(
            dict.fromkeys(
                event.identifier
                for event in self.order_events_near_snapshot
                if event.overlaps_or_follows(self.snapshot_started_at)
            )
        )

    @property
    def activity_ids_after_snapshot(self) -> tuple[str, ...]:
        return tuple(
            dict.fromkeys(
                event.identifier
                for event in self.activity_events_near_snapshot
                if event.overlaps_or_follows(self.snapshot_started_at)
            )
        )


class LedgerRepository(Protocol):
    def load(self) -> LedgerSnapshot: ...
    def save(self, snapshot: LedgerSnapshot, event: JournalEvent) -> None:
        """Commit the snapshot and journal event atomically, or leave both unchanged."""
        ...


@runtime_checkable
class QuoteBroker(Protocol):
    def quote(self, symbol: str) -> Quote: ...


class ExecutionObserver(Protocol):
    def span(self, name: str, message_id: str) -> AbstractContextManager: ...
    def event(self, name: str) -> None: ...


class NoOpObserver:
    def span(self, name: str, message_id: str) -> AbstractContextManager:
        return nullcontext()

    def event(self, name: str) -> None:
        pass


@dataclass(frozen=True)
class ExecutionObservation:
    account: Account
    ledger: LedgerSnapshot
    total_cost_exposure_usd: Decimal
    position_audit: PositionAudit | None


@dataclass(frozen=True)
class AccountRuntimeView:
    entry_permission: str
    recovery_preference: str
    readiness: str
    account_risk_status: str
    account_risk_reason: str | None
    account_activity_status: str
    account_activity_reason: str | None
