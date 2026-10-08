import datetime as dt
from typing import ClassVar, Literal, Self

from pydantic import AwareDatetime, model_validator

from copytrading_engine.execution.domain.values import (
    BrokerAccountId,
    Identifier,
    Money,
    Positive,
    Quantity,
    Side,
    Value,
)


class Account(Value):
    id: BrokerAccountId
    status: Identifier
    cash: Money
    buying_power: Money
    equity: Money
    last_equity: Money
    trading_blocked: bool
    account_blocked: bool
    trade_suspended_by_user: bool
    currency: str

    @property
    def active(self) -> bool:
        return self.status == "ACTIVE" and not (
            self.trading_blocked or self.account_blocked or self.trade_suspended_by_user
        )

    def standing(self) -> dict[str, object]:
        """Whether and how this account may trade. Balances move with every tick, so a review
        that compares accounts must not include them."""
        return self.model_dump(
            mode="json", exclude={"cash", "buying_power", "equity", "last_equity"}
        )


class Asset(Value):
    symbol: Identifier
    asset_class: str
    status: str
    tradable: bool
    fractionable: bool
    attributes: tuple[str, ...] = ()
    overnight_tradable: bool = False
    overnight_halted: bool = False


class Position(Value):
    """A broker position: what is held, and the broker's own valuation of it."""

    symbol: Identifier
    qty: Money
    market_value: Money | None = None
    currency: str | None = None
    asset_class: str | None = None
    avg_entry_price: Money | None = None
    current_price: Money | None = None
    unrealized_pl: Money | None = None
    unrealized_plpc: Money | None = None

    #: The broker's valuation, which moves with every tick and every outside fill.
    VALUATION: ClassVar[frozenset[str]] = frozenset(
        {"market_value", "avg_entry_price", "current_price", "unrealized_pl", "unrealized_plpc"}
    )

    def holding(self) -> dict[str, object]:
        """What is held, without its valuation."""
        return self.model_dump(mode="json", exclude=set(self.VALUATION))


class CalendarDay(Value):
    date: dt.date
    open: dt.time
    close: dt.time
    session_open: dt.time = dt.time(4)
    session_close: dt.time | None = None


class BrokerOrder(Value):
    id: Identifier
    client_order_id: Identifier
    symbol: Identifier
    side: Side
    qty: Positive
    filled_qty: Quantity
    filled_avg_price: Positive | None
    status: Identifier
    position_intent: Literal["buy_to_open", "sell_to_close"] | None = None

    @model_validator(mode="after")
    def consistent_fill(self) -> Self:
        if self.filled_qty > self.qty or (self.status == "filled" and self.filled_qty != self.qty):
            raise ValueError("Inconsistent broker fill quantity")
        if self.filled_qty > 0 and self.filled_avg_price is None:
            raise ValueError("A fill requires its average price")
        return self


type QuoteFeed = Literal["iex", "overnight"]


class Quote(Value):
    feed: QuoteFeed
    bid: Quantity | None
    ask: Quantity | None
    timestamp: AwareDatetime | None


class EquityPoint(Value):
    at: AwareDatetime
    equity: Money


type HistoryRange = Literal["day", "week", "month", "three_months", "year"]


class HistoryWindow(Value):
    """A stretch of the broker's equity curve: a range ending now, or one chosen trading day."""

    range: HistoryRange
    day: dt.date | None = None

    @model_validator(mode="after")
    def day_names_only_a_day(self) -> Self:
        if self.day is not None and self.range != "day":
            raise ValueError("Only the day range names a date")
        return self


class EquityHistory(Value):
    """The broker's equity curve for one window, oldest point first."""

    window: HistoryWindow
    base_value: Money | None
    points: tuple[EquityPoint, ...]
