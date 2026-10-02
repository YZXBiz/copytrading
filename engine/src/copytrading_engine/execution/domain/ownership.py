"""Durable attribution of broker holdings outside copier-owned lots."""

from typing import Literal, Self

from pydantic import AwareDatetime, Field, model_validator

from copytrading_engine.execution.domain.market import BrokerOrder, Position
from copytrading_engine.execution.domain.orders import OrderRecord
from copytrading_engine.execution.domain.values import Identifier, Money, Quantity, Value


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
) -> str | None:
    """Check an observed open-order page against persisted account activity."""
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
        or observed.symbol != saved.symbol
        or observed.side != saved.side
        or observed.qty != saved.qty
        or (saved.broker_id is not None and observed.id != saved.broker_id)
        or (
            observed.position_intent is not None
            and observed.position_intent != saved.position_intent
        )
        for observed in open_orders
    ):
        return "unresolved_account_order"
    return None
