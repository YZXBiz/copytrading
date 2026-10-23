"""Durable attribution of broker holdings outside copier-owned lots."""

from collections.abc import Sequence
from dataclasses import dataclass
from decimal import Decimal
from typing import Literal, Self

from pydantic import AwareDatetime, Field, model_validator

from copytrading_engine.execution.domain.market import BrokerOrder, Position
from copytrading_engine.execution.domain.order_lifecycle import OrderStatus
from copytrading_engine.execution.domain.orders import OrderRecord
from copytrading_engine.execution.domain.values import Identifier, Money, Quantity, Value

# Why the app settled a holdings count from the broker's filled count by itself (ADR-0011).
SyncReason = Literal[
    "broker_matches_again",
    "owner_bought_outside",
    "owner_sold_own_shares",
    "owner_sold_copied_shares",
]


@dataclass(frozen=True, slots=True)
class Allocation:
    """How a broker count splits: what each copied lot keeps, and what is the owner's own."""

    lot_remaining: dict[str, Decimal]
    external_qty: Decimal


def allocate(broker_qty: Decimal, lots_oldest_first: Sequence[tuple[str, Decimal]]) -> Allocation:
    """Copied shares the broker still holds stay copied and the rest are the owner's own. A count
    below the copied shares means copied shares were sold outside the app, and they come off the
    oldest buys first, the way the app's own sells take them."""
    copied = sum((held for _, held in lots_oldest_first), Decimal(0))
    if broker_qty >= copied:
        return Allocation(dict(lots_oldest_first), broker_qty - copied)
    missing = copied - broker_qty
    remaining: dict[str, Decimal] = {}
    for key, held in lots_oldest_first:
        taken = min(held, missing)
        remaining[key] = held - taken
        missing -= taken
    return Allocation(remaining, Decimal(0))


def sync_reason(broker_qty: Decimal, expected: Decimal, copied: Decimal) -> SyncReason:
    """What a settled count says the owner did."""
    if broker_qty == expected:
        return "broker_matches_again"
    if broker_qty > expected:
        return "owner_bought_outside"
    return "owner_sold_own_shares" if broker_qty >= copied else "owner_sold_copied_shares"


class ExternalPosition(Value):
    symbol: Identifier
    qty: Quantity
    allocation_revision: int = Field(default=0, ge=0)


class OwnershipIncident(Value):
    incident_id: Identifier
    symbol: Identifier
    expected_qty: Quantity
    actual_qty: Money
    observed_at: AwareDatetime
    cause: Literal["position_mismatch", "manual_sale"]
    resolved_by: Identifier | None = None

    @property
    def resolved(self) -> bool:
        return self.resolved_by is not None


class OwnershipResolutionRequest(Value):
    resolution_id: Identifier
    incident_id: Identifier
    account_id: Identifier
    symbol: Identifier
    actor: Identifier
    reason: Identifier
    broker_qty: Quantity
    external_qty: Quantity
    lot_remaining: dict[Identifier, Quantity] = Field(default_factory=dict)

    @model_validator(mode="after")
    def conserved(self) -> Self:
        if not self.actor.strip() or not self.reason.strip():
            raise ValueError("Ownership resolution requires actor and reason")
        if self.external_qty + sum(self.lot_remaining.values()) != self.broker_qty:
            raise ValueError("Ownership resolution quantity conservation failed")
        return self


class OwnershipResolution(Value):
    request: OwnershipResolutionRequest
    checked_at: AwareDatetime
    lot_reductions: dict[Identifier, Quantity]
    allocation_revision: int = Field(ge=1)

    @property
    def external_qty(self) -> Quantity:
        return self.request.external_qty


class OwnershipInspection(Value):
    account_id: Identifier
    environment: Literal["paper", "live"]
    external_positions: tuple[ExternalPosition, ...]
    incidents: tuple[OwnershipIncident, ...]
    broker_positions: tuple[Position, ...]
    expected_quantities: dict[Identifier, Quantity]
    account_risk_status: Literal["ready", "unavailable"]
    account_risk_reason: str | None
    total_exposure_usd: Quantity | None
    account_activity_status: Literal["ready", "unavailable"]
    account_activity_reason: str | None

    @model_validator(mode="after")
    def risk_fact_consistency(self) -> Self:
        if (self.account_risk_status == "ready") != (self.total_exposure_usd is not None):
            raise ValueError("Ready account risk requires valued exposure")
        if (self.account_activity_status == "ready") != (self.account_activity_reason is None):
            raise ValueError("Ready account activity requires no unresolved reason")
        return self


def account_activity_reason(
    open_orders: tuple[BrokerOrder, ...],
    known_open_orders: tuple[OrderRecord, ...],
    *,
    unresolved_order_incidents: bool,
    symbol: str | None = None,
) -> str | None:
    """Check an observed open-order page against persisted account activity. The page is checked
    whole, since a full or repeating page can't be trusted for any stock; with `symbol` (a sell),
    only an order on that stock that CopyTrading didn't place holds it (ADR-0010)."""
    if unresolved_order_incidents:
        return "unresolved_order_incident"
    if len(open_orders) >= 500:
        return "incomplete_account_orders"
    observed_ids = [order.client_order_id for order in open_orders]
    if len(set(observed_ids)) != len(observed_ids):
        return "incomplete_account_orders"
    known_by_id = {order.client_id: order for order in known_open_orders}
    if any(
        (saved := known_by_id.get(observed.client_order_id)) is None
        or not _same_order(observed, saved)
        for observed in open_orders
        if symbol is None or observed.symbol == symbol
    ):
        return "unresolved_account_order"
    return None


# What only the broker reports: an order the app aborted or never sent is not settled.
_BROKER_SETTLED = frozenset(
    {
        OrderStatus.FILLED,
        OrderStatus.CANCELED,
        OrderStatus.EXPIRED,
        OrderStatus.REPLACED,
        OrderStatus.REJECTED,
    }
)


def still_open(
    open_orders: tuple[BrokerOrder, ...], orders: tuple[OrderRecord, ...]
) -> tuple[BrokerOrder, ...]:
    """The broker's open orders, less the app's own that the broker already reported settled.

    The open-order list can trail a fill or cancel the broker has reported: in a burst, a buy
    planned just after another fills still sees that one listed as open."""
    settled = {order.client_id: order for order in orders if order.status in _BROKER_SETTLED}
    return tuple(
        observed
        for observed in open_orders
        if (saved := settled.get(observed.client_order_id)) is None
        or not _same_order(observed, saved)
    )


def _same_order(observed: BrokerOrder, saved: OrderRecord) -> bool:
    return (
        observed.symbol == saved.symbol
        and observed.side == saved.side
        and observed.qty == saved.qty
        and (saved.broker_id is None or observed.id == saved.broker_id)
        and (observed.position_intent is None or observed.position_intent == saved.position_intent)
    )
