"""Validated order terms and records."""

import datetime as dt
import hashlib
from collections.abc import Mapping
from decimal import ROUND_DOWN, Decimal
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
from copytrading_engine.shared.symbols import is_crypto


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
    # A stock order lasts the day; Alpaca takes a coin's only as good-till-canceled, so a sell of
    # one rests at its floor until it fills (ADR-0014).
    time_in_force: Literal["day", "gtc"]
    # Never sent for a coin, which has no extended hours.
    extended_hours: bool | None

    @model_validator(mode="after")
    def valid_session(self) -> Self:
        crypto = is_crypto(self.symbol)
        if crypto != (self.time_in_force == "gtc"):
            raise ValueError("A coin's order is good-till-canceled, and only a coin's")
        if crypto != (self.extended_hours is None):
            raise ValueError("Only a stock's order says whether it trades in extended hours")
        if self.type == "market" and self.extended_hours:
            raise ValueError("Market orders cannot execute in extended hours")
        return self

    @classmethod
    def for_plan(
        cls, plan: OrderPlan, client_order_id: str, *, extended_hours: bool
    ) -> OrderRequest:
        """The order Alpaca is sent for a plan: a stock's for the day, marked for extended hours
        as asked; a coin's good-till-canceled, with no hours at all."""
        crypto = is_crypto(plan.symbol)
        return cls(
            symbol=plan.symbol,
            side=plan.side,
            position_intent=plan.position_intent,
            qty=plan.qty,
            type=plan.type,
            limit_price=plan.limit_price,
            client_order_id=client_order_id,
            time_in_force="gtc" if crypto else "day",
            extended_hours=None if crypto else extended_hours,
        )


_SIZE_TOLERANCE = Decimal("1.02")
# Fields a fresh quote recomputes; see OrderPlan.same_order_as.
_PRICED = frozenset(
    {
        "limit_price",
        "source_price",
        "entry_price",
        "qty",
        "requested_usd",
        "budget_usd",
        "limited_by",
    }
)


# Why CopyTrading asked Alpaca to cancel an order: it went unfilled for the account's order
# timeout, a sell of the same stock replaced a buy still waiting, or copying stopped.
def copy_client_id(message_key: str, part: int, attempt: int = 1) -> str:
    """The client order ID of a copied call: one per post and call, so a retried submit can't
    place it twice, and `-2`, `-3` after it for a sell sent again after an abort (ADR-0010)."""
    base = "copy-" + hashlib.sha256(f"{message_key}:{part}".encode()).hexdigest()[:40]
    return base if attempt == 1 else f"{base}-{attempt}"


type CancelReason = Literal["timeout", "replaced_by_sell", "copying_stopped"]
# Statuses that say Alpaca has the order live on the market; an order's timeout runs from the first
# of them, not from when it was sent, since Alpaca can hold an order before it goes out.
LIVE_AT_BROKER = frozenset(
    {
        OrderStatus.NEW,
        OrderStatus.PARTIALLY_FILLED,
        OrderStatus.FILLED,
    }
)

# What cut a buy below what its call asked for (risk.BuyLimit).
type BuyLimit = Literal["largest_single_buy", "symbol_exposure_cap", "total_exposure_cap"]


class OrderPlan(OrderTerms):
    symbol: Identifier
    qty: Positive
    source_price: Positive
    entry_tolerance_pct: Quantity
    lot_id: Identifier | None
    entry_price: Positive
    session: Session
    # A buy joins the guru's open lot of the stock (ADR-0010).
    joins_lot: Identifier | None = None
    # A sell takes from these buys in its lot, or from every buy when empty (ADR-0010).
    from_entries: tuple[Identifier, ...] = ()
    # What the call asked for, what the account's limits allowed of it, and the limit that cut
    # it, if one did (ADR-0010).
    requested_usd: Positive | None = None
    budget_usd: Positive | None = None
    limited_by: BuyLimit | None = None

    def still_allowed_by(self, fresh: OrderPlan) -> bool:
        """The approved order may still go out: the same order, and no larger than what the
        account's limits allow now. A price tick moves a buy's size a little, so a size within
        2% of today's passes; a real drop, such as buying power falling, does not."""
        return self.same_order_as(fresh) and self.qty <= fresh.qty * _SIZE_TOLERANCE

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
            or self.limited_by is not None
        ):
            raise ValueError("Only buys join a lot or carry a requested amount")
        if self.side == "buy" and self.from_entries:
            raise ValueError("Only sells take from buys")
        if self.session == Session.CLOSED:
            raise ValueError("Cannot prepare an order in a closed session")
        if self.type == "market" and self.session not in {
            Session.REGULAR,
            Session.AROUND_THE_CLOCK,
        }:
            raise ValueError("Market exits require a regular session")
        if is_crypto(self.symbol) != (self.session == Session.AROUND_THE_CLOCK):
            raise ValueError("A coin trades around the clock, and only a coin does")
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
    # When Alpaca first reported the order live on the market; its timeout runs from here.
    accepted_at: AwareDatetime | None = None
    # A coin bought arrives less Alpaca's fee, taken in the coin itself and reported only at the
    # day's end: `fee_qty` is the coin the account never received, counted from the broker's
    # holding once `fee_settled_qty` of the fill had been booked (ADR-0014). Zero for a stock.
    fee_qty: Quantity = Decimal(0)
    fee_settled_qty: Quantity = Decimal(0)

    @property
    def received_qty(self) -> Decimal:
        """What the account holds from this order's fills: a coin's less its fee."""
        return self.filled_qty - self.fee_qty

    @property
    def unsettled_fee_qty(self) -> Decimal:
        """The coin a buy filled since its fee was last counted; a stock's fill, and a sale, pay
        no fee in what they receive."""
        if self.side != "buy" or not is_crypto(self.symbol):
            return Decimal(0)
        return self.filled_qty - self.fee_settled_qty

    @model_validator(mode="after")
    def valid_fill(self) -> Self:
        if self.filled_qty > self.qty or (self.status == "filled" and self.filled_qty != self.qty):
            raise ValueError("Inconsistent recorded fill quantity")
        if self.fee_qty or self.fee_settled_qty:
            if self.side != "buy" or not is_crypto(self.symbol):
                raise ValueError("Only a coin's buy pays its fee in the coin")
            if not self.fee_qty <= self.fee_settled_qty <= self.filled_qty:
                raise ValueError("A fee is counted only on what has filled")
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


# Shares are kept to the millionth, as Alpaca trades them.
SHARE_STEP = Decimal("0.000001")


class OwnedLot(Value):
    """Every buy of one stock from one guru, as one position (ADR-0010). The lot keeps each buy's
    remaining shares, so a sell can take from the buys at a named price, or from all of them."""

    symbol: Identifier
    entry_price: Positive
    source_key: Identifier
    original_qty: Positive
    remaining_qty: Quantity
    # What each share still held cost: every buy's remaining shares at that buy's own fill price.
    average_price: Positive
    # Later buys of the stock from the same guru, in the order they joined.
    joined_entries: tuple[Identifier, ...] = ()
    # What is left of each buy, keyed by its order, oldest first; it adds up to remaining_qty.
    entry_remaining: dict[Identifier, Quantity]
    # The guru's price for each buy, so a sell naming a price finds its buys.
    entry_prices: dict[Identifier, Positive]

    def entries(self, key: str) -> tuple[str, ...]:
        """Every buy order in this lot: the one that opened it, which keys it, then the rest."""
        return (key, *self.joined_entries)

    def entries_at(self, price: Decimal) -> tuple[str, ...]:
        """The buys the guru made at exactly this price that still hold shares."""
        return tuple(
            entry
            for entry, entry_price in self.entry_prices.items()
            if entry_price == price and self.entry_remaining.get(entry, Decimal(0)) > 0
        )

    def remaining_of(self, entries: tuple[str, ...]) -> Decimal:
        return sum((self.entry_remaining[entry] for entry in entries), Decimal(0))

    def priced(self, fills: Mapping[str, Decimal]) -> OwnedLot:
        """The lot with its average set from `fills`, each buy's fill price by its order. A buy
        that was partly sold weighs only what it has left, so a sale of one buy moves the average
        toward the others. A sold-out lot, or one missing a held buy's fill, keeps its average."""
        held = {entry: left for entry, left in self.entry_remaining.items() if left > 0}
        if not held or any(entry not in fills for entry in held):
            return self
        cost = sum((left * fills[entry] for entry, left in held.items()), Decimal(0))
        return self.model_copy(update={"average_price": cost / self.remaining_qty})

    def reduced(self, qty: Decimal, entries: tuple[str, ...] | None = None) -> OwnedLot:
        """The lot after selling `qty`, taken from `entries` (all buys when None) in proportion to
        what each has left; the rounding remainder comes from the oldest of them. A sale of whole
        shares from buys that hold whole shares, as every sale of a stock that trades only in
        whole shares is, splits in whole shares, so no buy is left a fraction it can't sell
        (ADR-0010)."""
        chosen = tuple(
            entry
            for entry in (entries or tuple(self.entry_remaining))
            if self.entry_remaining.get(entry, Decimal(0)) > 0
        )
        available = self.remaining_of(chosen)
        if qty > available:
            raise ValueError("A sale cannot take more than the buys it sells from hold")
        whole = all(
            amount == amount.to_integral_value()
            for amount in (qty, *(self.entry_remaining[entry] for entry in chosen))
        )
        step = Decimal(1) if whole else SHARE_STEP
        taken: dict[str, Decimal] = {}
        for entry in chosen:
            share = (qty * self.entry_remaining[entry] / available) if available else Decimal(0)
            taken[entry] = share.quantize(step, rounding=ROUND_DOWN)
        leftover = qty - sum(taken.values(), Decimal(0))
        for entry in chosen:
            if leftover <= 0:
                break
            extra = min(leftover, self.entry_remaining[entry] - taken[entry])
            taken[entry] += extra
            leftover -= extra
        return OwnedLot.model_validate(
            self.model_dump()
            | {
                "remaining_qty": self.remaining_qty - qty,
                "entry_remaining": {
                    entry: left - taken.get(entry, Decimal(0))
                    for entry, left in self.entry_remaining.items()
                },
            }
        )

    @model_validator(mode="after")
    def valid_remaining(self) -> Self:
        if self.remaining_qty > self.original_qty:
            raise ValueError("Remaining shares exceed the original lot")
        if sum(self.entry_remaining.values(), Decimal(0)) != self.remaining_qty:
            raise ValueError("A lot's buys must add up to its remaining shares")
        if set(self.entry_remaining) != set(self.entry_prices) or len(self.entry_remaining) != (
            1 + len(self.joined_entries)
        ):
            raise ValueError("Every buy in a lot has its remaining shares and price")
        return self
