"""Validated order terms and records."""

import datetime as dt
from typing import Literal, Self

from pydantic import AwareDatetime, Field, model_validator

from copytrading_engine.execution.domain.order_lifecycle import (
    OrderStatus,
    is_pending,
    is_terminal,
    map_broker_status,
)
from copytrading_engine.execution.domain.sessions import Session
from copytrading_engine.execution.domain.values import Identifier, Positive, Quantity, Side, Value


class OrderTerms(Value):
    side: Side
    position_intent: Literal["buy_to_open", "sell_to_close"]
    type: Literal["limit", "market"]
    limit_price: Positive | None = None

    @model_validator(mode="after")
    def valid_terms(self) -> Self:
        if self.position_intent != ("buy_to_open" if self.side == "buy" else "sell_to_close"):
            raise ValueError("Broker position intent does not match the order side")
        if (self.type == "limit") != (self.limit_price is not None):
            raise ValueError("Only limit orders require a limit price")
        if self.type == "market" and self.side != "sell":
            raise ValueError("Only exits may use market orders")
        return self


class OrderRequest(OrderTerms):
    symbol: Identifier
    qty: Positive
    client_order_id: str = Field(min_length=1, max_length=48)
    time_in_force: Literal["day"] = "day"
    extended_hours: bool

    @model_validator(mode="after")
    def valid_session(self) -> Self:
        if self.type == "market" and self.extended_hours:
            raise ValueError("Market orders cannot execute in extended hours")
        return self


class OrderPlan(OrderTerms):
    symbol: Identifier
    qty: Positive
    source_price: Positive
    entry_tolerance_pct: Quantity
    lot_id: Identifier | None
    entry_price: Positive
    session: Session

    @model_validator(mode="after")
    def valid_plan(self) -> Self:
        if self.session == Session.CLOSED:
            raise ValueError("Cannot prepare an order in a closed session")
        if self.type == "market" and self.session != Session.REGULAR:
            raise ValueError("Market exits require a regular session")
        if (self.side == "sell") != (self.lot_id is not None):
            raise ValueError("Only sells must reference an owned lot")
        return self


class OrderRecord(OrderPlan):
    client_id: Identifier
    message_id: Identifier
    instruction_index: int = Field(ge=0)
    source_key: Identifier
    status: OrderStatus
    filled_qty: Quantity
    broker_id: str | None
    created_at: AwareDatetime
    day: dt.date
    raw_broker_status: Identifier | None = None
    submit_started_at: AwareDatetime | None = None
    filled_avg_price: Positive | None = None

    @model_validator(mode="after")
    def valid_fill(self) -> Self:
        if self.filled_qty > self.qty or (self.status == "filled" and self.filled_qty != self.qty):
            raise ValueError("Inconsistent recorded fill quantity")
        if self.status == "aborted_before_submit" and (self.filled_qty or self.broker_id):
            raise ValueError("An order aborted before submission cannot have broker activity")
        if self.status == OrderStatus.UNRECOGNIZED:
            if (
                self.raw_broker_status is None
                or map_broker_status(self.raw_broker_status) != self.status
            ):
                raise ValueError("An unrecognized order status must preserve its broker value")
        elif (
            self.raw_broker_status is not None
            and map_broker_status(self.raw_broker_status) != self.status
        ):
            raise ValueError("Raw broker status does not match the internal order status")
        return self

    @property
    def pending(self) -> bool:
        return is_pending(self.status)

    @property
    def terminal(self) -> bool:
        return is_terminal(self.status)


class OwnedLot(Value):
    symbol: Identifier
    entry_price: Positive
    source_key: Identifier
    original_qty: Positive
    remaining_qty: Quantity
    average_price: Positive

    @model_validator(mode="after")
    def valid_remaining(self) -> Self:
        if self.remaining_qty > self.original_qty:
            raise ValueError("Remaining shares exceed the original lot")
        return self
