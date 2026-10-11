import datetime as dt
from typing import Self

from pydantic import (
    BaseModel,
    ConfigDict,
    Field,
    StrictBool,
    TypeAdapter,
    field_validator,
    model_validator,
)

from copytrading_engine.execution.domain.market import (
    Account,
    Asset,
    BrokerOrder,
    CalendarDay,
    EquityHistory,
    EquityPoint,
    HistoryWindow,
    Position,
    Quote,
    QuoteFeed,
)
from copytrading_engine.execution.domain.values import Identifier, Money, Positive, Quantity, Side


class AlpacaValue(BaseModel):
    model_config = ConfigDict(frozen=True, extra="ignore", hide_input_in_errors=True)


class AlpacaAccount(AlpacaValue):
    id: Identifier
    status: Identifier
    cash: Money
    buying_power: Money
    equity: Money
    last_equity: Money
    trading_blocked: StrictBool
    account_blocked: StrictBool
    trade_suspended_by_user: StrictBool
    currency: str


class AlpacaAsset(AlpacaValue):
    symbol: Identifier
    asset_class: str = Field(alias="class")
    status: str
    tradable: StrictBool
    fractionable: StrictBool
    attributes: tuple[str, ...] = ()
    overnight_tradable: StrictBool = False
    overnight_halted: StrictBool = False


class AlpacaPosition(AlpacaValue):
    symbol: Identifier
    qty: Money
    market_value: Money | None = None
    avg_entry_price: Money | None = None
    current_price: Money | None = None
    unrealized_pl: Money | None = None
    unrealized_plpc: Money | None = None
    asset_class: str = Field(alias="asset_class")
    currency: str | None = None


class AlpacaCalendarDay(AlpacaValue):
    date: dt.date
    open: dt.time
    close: dt.time
    session_open: dt.time = dt.time(4)
    session_close: dt.time | None = None

    @field_validator("open", "close", "session_open", "session_close", mode="before")
    @classmethod
    def time_value(cls, value: object) -> object:
        if isinstance(value, str):
            if len(value) == 4 and value.isdecimal():
                value = f"{value[:2]}:{value[2:]}"
            return dt.time.fromisoformat(value)
        return value


class AlpacaBrokerOrder(AlpacaValue):
    id: Identifier
    client_order_id: Identifier
    symbol: Identifier
    side: Side
    qty: Positive
    filled_qty: Quantity
    filled_avg_price: Positive | None
    status: Identifier
    position_intent: str | None = None


def _exact_decimal(value: object) -> object:
    # JSON numbers arrive as floats; their shortest text form is the value Alpaca sent.
    return str(value) if isinstance(value, float) else value


class AlpacaPortfolioHistory(AlpacaValue):
    timestamp: tuple[int, ...]
    equity: tuple[Money | None, ...]
    base_value: Money | None = None

    @field_validator("equity", mode="before")
    @classmethod
    def exact_equity(cls, value: object) -> object:
        return [_exact_decimal(item) for item in value] if isinstance(value, list) else value

    @field_validator("base_value", mode="before")
    @classmethod
    def exact_base(cls, value: object) -> object:
        return _exact_decimal(value)

    @model_validator(mode="after")
    def aligned_series(self) -> Self:
        if len(self.timestamp) != len(self.equity):
            raise ValueError("Portfolio history series differ in length")
        return self


class AlpacaQuote(AlpacaValue):
    """A latest quote. Alpaca sends a side with no quote as 0, which means no price at all."""

    bp: Quantity | None = None
    ap: Quantity | None = None
    t: dt.datetime | None = None

    @field_validator("bp", "ap", mode="before")
    @classmethod
    def exact_side(cls, value: object) -> object:
        return None if value in (0, "0", None) else _exact_decimal(value)


def decode_quote(value: object, feed: QuoteFeed) -> Quote:
    # A reply without a quote object fails validation like any other malformed response.
    wire = AlpacaQuote.model_validate(value.get("quote") if isinstance(value, dict) else None)
    return Quote(feed=feed, bid=wire.bp, ask=wire.ap, timestamp=wire.t)


def decode_portfolio_history(value: object, window: HistoryWindow) -> EquityHistory:
    wire = AlpacaPortfolioHistory.model_validate(value)
    return EquityHistory(
        window=window,
        base_value=wire.base_value,
        points=tuple(
            EquityPoint(at=dt.datetime.fromtimestamp(stamp, dt.UTC), equity=equity)
            for stamp, equity in zip(wire.timestamp, wire.equity, strict=True)
            if equity is not None
        ),
    )


def decode_account(value: object) -> Account:
    wire = AlpacaAccount.model_validate(value)
    return Account.model_validate(wire.model_dump())


def decode_asset(value: object) -> Asset:
    wire = AlpacaAsset.model_validate(value)
    return Asset.model_validate(wire.model_dump())


def decode_calendar(value: object) -> tuple[CalendarDay, ...]:
    wire_days = TypeAdapter(tuple[AlpacaCalendarDay, ...]).validate_python(value)
    return tuple(CalendarDay.model_validate(day.model_dump()) for day in wire_days)


def decode_positions(value: object, *, account_currency: str | None = None) -> tuple[Position, ...]:
    wire_positions = TypeAdapter(tuple[AlpacaPosition, ...]).validate_python(value)
    return tuple(
        Position.model_validate(
            position.model_dump()
            | {"currency": position.currency if position.currency is not None else account_currency}
        )
        for position in wire_positions
    )


def decode_broker_order(value: object) -> BrokerOrder:
    wire = AlpacaBrokerOrder.model_validate(value)
    return BrokerOrder.model_validate(wire.model_dump())


def decode_orders(value: object) -> tuple[BrokerOrder, ...]:
    wire_orders = TypeAdapter(tuple[AlpacaBrokerOrder, ...]).validate_python(value)
    return tuple(BrokerOrder.model_validate(order.model_dump()) for order in wire_orders)
