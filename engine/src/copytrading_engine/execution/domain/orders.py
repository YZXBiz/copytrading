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


# Fields a fresh quote recomputes; see OrderPlan.same_order_as.
_PRICED = frozenset(
    {"limit_price", "source_price", "entry_price", "qty", "requested_usd", "budget_usd"}
)


class OrderPlan(OrderTerms):
    symbol: Identifier
    qty: Positive
    source_price: Positive
    entry_tolerance_pct: Quantity
    lot_id: Identifier | None
    entry_price: Positive
    session: Session
    # A buy for a guru whose sells refer to the whole position joins this open lot.
    joins_lot: Identifier | None = None
    # What the call asked for, and what the maximum per order allowed of it (ADR-0007).
    requested_usd: Positive | None = None
    budget_usd: Positive | None = None

    def same_order_as(self, other: OrderPlan) -> bool:
        """The same order apart from prices, which a fresh quote recomputes every time. The
        owner approves a plan and that plan is sent; prices that tick meanwhile do not change
        which order it is."""
        return self.model_dump(exclude=set(_PRICED)) == other.model_dump(exclude=set(_PRICED))

    @model_validator(mode="after")
    def valid_plan(self) -> Self:
        if self.side == "sell" and (
            self.joins_lot is not None
            or self.requested_usd is not None
            or self.budget_usd is not None
        ):
            raise ValueError("Only buys join a lot or carry a requested amount")
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
    # Later buys at the guru's same price that joined this lot while it was open. The guru
    # counts them as one position, so an exit naming that price sells from all of them.
    joined_entries: tuple[Identifier, ...] = ()

    def entries(self, key: str) -> tuple[str, ...]:
        """Every buy order in this lot: the one that opened it, which keys it, then the rest."""
        return (key, *self.joined_entries)

    @model_validator(mode="after")
    def valid_remaining(self) -> Self:
        if self.remaining_qty > self.original_qty:
            raise ValueError("Remaining shares exceed the original lot")
        return self
