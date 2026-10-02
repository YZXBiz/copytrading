"""Operator evidence and exceptional execution facts."""

from typing import Literal, Self

from pydantic import AwareDatetime, model_validator

from copytrading_engine.execution.domain.market import BrokerOrder
from copytrading_engine.execution.domain.order_lifecycle import OrderStatus
from copytrading_engine.execution.domain.values import Identifier, Positive, Quantity, Side, Value


class ManualSale(Value):
    order: BrokerOrder
    filled_at: AwareDatetime
    recorded_at: AwareDatetime
    reason: Identifier
    lot_id: Identifier | None = None

    @model_validator(mode="after")
    def confirmed_sale(self) -> Self:
        if self.order.side != "sell" or self.order.status != "filled":
            raise ValueError("Manual reconciliation requires a fully filled sell")
        if self.filled_at > self.recorded_at:
            raise ValueError("A manual sale must be filled before it is recorded")
        return self


class ReleaseEvidence(Value):
    actor: Identifier
    reason: Identifier
    order_history_ref: Identifier
    fill_history_ref: Identifier
    checked_at: AwareDatetime
    account_id: Identifier
    submission_state: Literal["started", "not_started"] = "started"


class IncidentClearanceEvidence(Value):
    actor: Identifier
    reason: Identifier
    checked_at: AwareDatetime
    account_id: Identifier
    matched_audit_ref: Identifier | None = None
    symbol: Identifier | None = None
    expected_qty: Quantity | None = None
    broker_qty: Quantity | None = None

    @model_validator(mode="after")
    def matched_position_evidence(self) -> Self:
        quantities_given = any(
            value is not None for value in (self.symbol, self.expected_qty, self.broker_qty)
        )
        if quantities_given and not (
            self.symbol is not None
            and self.expected_qty is not None
            and self.broker_qty is not None
            and self.expected_qty == self.broker_qty
        ):
            raise ValueError(
                "Matched position evidence requires equal expected and broker quantities"
            )
        if self.matched_audit_ref is None and not quantities_given:
            raise ValueError("Incident clearance requires a matched audit reference or quantities")
        return self


class LateOrderIncident(Value):
    client_id: Identifier
    broker_id: Identifier
    symbol: Identifier
    side: Side
    first_observed_at: AwareDatetime
    last_observed_at: AwareDatetime
    latest_status: OrderStatus
    raw_broker_status: Identifier
    latest_filled_qty: Quantity
    conflicting_order_ids: tuple[Identifier, ...] = ()
    clearance_history: tuple[IncidentClearanceEvidence, ...] = ()
    cleared: bool = False

    @model_validator(mode="after")
    def valid_incident(self) -> Self:
        if self.last_observed_at < self.first_observed_at:
            raise ValueError("Late-order observation time cannot move backwards")
        if self.cleared and not self.clearance_history:
            raise ValueError("A cleared late-order incident requires clearance evidence")
        if len(set(self.conflicting_order_ids)) != len(self.conflicting_order_ids):
            raise ValueError("Late-order conflicting order identities must be unique")
        if self.client_id in self.conflicting_order_ids:
            raise ValueError("A late-order incident cannot conflict with itself")
        if any(
            later.checked_at < earlier.checked_at
            for earlier, later in zip(
                self.clearance_history, self.clearance_history[1:], strict=False
            )
        ):
            raise ValueError("Incident clearance history must be chronological")
        return self

    @property
    def unresolved(self) -> bool:
        return not self.cleared


class QuarantinedFill(Value):
    """Cumulative sell fill evidence that could not all be charged to its source lot."""

    client_id: Identifier
    broker_id: Identifier
    lot_id: Identifier
    symbol: Identifier
    observed_filled_qty: Positive
    applied_filled_qty: Quantity
    unapplied_qty: Positive
    average_price: Positive
    first_observed_at: AwareDatetime
    last_observed_at: AwareDatetime
    incident_client_ids: tuple[Identifier, ...]

    @model_validator(mode="after")
    def valid_quarantine(self) -> Self:
        if self.applied_filled_qty + self.unapplied_qty != self.observed_filled_qty:
            raise ValueError("Quarantined fill quantities do not match the broker observation")
        if self.last_observed_at < self.first_observed_at:
            raise ValueError("Quarantined fill observation time cannot move backwards")
        if not self.incident_client_ids:
            raise ValueError("Quarantined fill requires associated incidents")
        if len(set(self.incident_client_ids)) != len(self.incident_client_ids):
            raise ValueError("Quarantined fill incident identities must be unique")
        return self
