"""The owner's sale of one copied lot: previewed against fresh facts, then confirmed once."""

from decimal import Decimal
from typing import Literal, Self

from pydantic import AwareDatetime, Field, model_validator

from copytrading_engine.execution.domain.manual_commands import ManualCheck
from copytrading_engine.execution.domain.market import Quote
from copytrading_engine.execution.domain.order_lifecycle import OrderStatus
from copytrading_engine.execution.domain.orders import OrderPlan
from copytrading_engine.execution.domain.sessions import Session
from copytrading_engine.execution.domain.values import Identifier, Positive, Quantity, Value


class LotSalePreviewRequest(Value):
    """Sell up to `qty` shares of one lot the copier owns in this account."""

    preview_id: Identifier
    account_id: Identifier
    lot_id: Identifier
    qty: Positive


class LotSalePreview(Value):
    request: LotSalePreviewRequest
    broker_account_id: Identifier
    environment: Literal["paper", "live"]
    symbol: Identifier
    lot_remaining_qty: Quantity
    created_at: AwareDatetime
    expires_at: AwareDatetime
    session: Session | None
    quote: Quote | None
    fresh_price: Positive | None
    plan: OrderPlan | None
    checks: tuple[ManualCheck, ...]
    reasons: tuple[Identifier, ...]
    facts_sha256: str = Field(pattern=r"^[0-9a-f]{64}$")

    @model_validator(mode="after")
    def valid_decision(self) -> Self:
        if (self.plan is not None) != (not self.reasons):
            raise ValueError("A lot sale preview plan must agree with its blocking reasons")
        if self.expires_at <= self.created_at:
            raise ValueError("Lot sale preview expiration must follow its creation")
        if (self.quote is None) != (self.fresh_price is None):
            raise ValueError("A fresh preview price requires its quote evidence")
        if self.plan is not None:
            if self.session is None:
                raise ValueError("A ready lot sale preview requires a market session")
            if (
                self.plan.side != "sell"
                or self.plan.symbol != self.symbol
                or self.plan.lot_id != self.request.lot_id
                or self.plan.qty > self.request.qty
                or self.plan.qty > self.lot_remaining_qty
            ):
                raise ValueError("A lot sale plan must sell no more than its lot holds")
        return self


class LotSaleConfirmation(Value):
    command_id: Identifier
    preview_id: Identifier
    account_id: Identifier
    actor: Identifier

    @model_validator(mode="after")
    def valid_actor(self) -> Self:
        if not self.actor.strip():
            raise ValueError("A lot sale confirmation requires an actor")
        return self


class LotSaleRecord(Value):
    request: LotSaleConfirmation
    lot_id: Identifier
    confirmed_at: AwareDatetime
    state: Literal["rejected", "prepared"]
    reason: Identifier | None = None
    client_id: Identifier | None = None

    @model_validator(mode="after")
    def valid_state(self) -> Self:
        if self.state == "rejected" and (self.reason is None or self.client_id is not None):
            raise ValueError("A rejected lot sale requires a reason and no order intent")
        if self.state == "prepared" and (self.reason is not None or self.client_id is None):
            raise ValueError("A prepared lot sale requires its order intent")
        return self


class LotSaleResult(Value):
    sale: LotSaleRecord
    status: Literal[
        "rejected",
        "prepared",
        "uncertain",
        "accepted",
        "partially_filled",
        "filled",
        "cancelled",
        "broker_rejected",
        "expired",
    ]
    reason: Identifier | None = None
    client_id: Identifier | None = None
    broker_order_id: Identifier | None = None
    order_status: OrderStatus | None = None
    filled_qty: Quantity = Decimal(0)
    filled_avg_price: Positive | None = None
