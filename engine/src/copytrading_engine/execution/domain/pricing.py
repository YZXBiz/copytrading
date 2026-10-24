"""Deterministic signal pricing policy, independent of quotes and broker clients."""

import datetime as dt
from decimal import ROUND_DOWN, ROUND_UP, Decimal
from typing import Annotated

from pydantic import BaseModel, ConfigDict, Field

from copytrading_engine.execution.domain.market import Quote

# A quote older than this is not the market now.
QUOTE_MAX_AGE_SECONDS = 30
# A sell at the market only takes its floor from the bid: an older bid can leave the order resting
# but never fill it worse, since a limit sell fills at the market's better price. Outside regular
# hours the free feed stops updating at the close, so the day's last bid is the bid there is; at
# worst the sell rests at that floor until the market reaches it.
SELL_FLOOR_QUOTE_MAX_AGE_SECONDS = 6 * 3600


def quote_problem(
    quote: Quote, price: Decimal | None, now: dt.datetime, max_age: float = QUOTE_MAX_AGE_SECONDS
) -> str | None:
    """Why a quote's price cannot stand for the market now, if it cannot."""
    if quote.timestamp is None or price is None or price <= 0:
        return "quote_unavailable"
    age = (now - quote.timestamp).total_seconds()
    if age < -5 or age > max_age:
        return "quote_stale"
    return None


# How far above the guru's price a buy may fill.
AboveSignalPct = Annotated[Decimal, Field(ge=0, le=100)]
# How far below the guru's sell price an exit may fill: a sell is always a limit order, and under
# 100% so its floor is a price.
BelowSignalPct = Annotated[Decimal, Field(ge=0, lt=100)]
DEFAULT_ABOVE_SIGNAL_PCT = Decimal("0")
DEFAULT_BELOW_SIGNAL_PCT = Decimal("1")


class PricePolicy(BaseModel):
    """How far a copy may stray from the guru's price, one rule per side: a buy pays at most
    its ceiling above it, a sell takes at least its floor below it. Both land on a valid tick:
    a stock's, or the coin's own `increment`."""

    model_config = ConfigDict(extra="forbid", frozen=True)
    max_above_signal_pct: AboveSignalPct = DEFAULT_ABOVE_SIGNAL_PCT
    max_below_signal_pct: BelowSignalPct = DEFAULT_BELOW_SIGNAL_PCT

    def buy_ceiling(self, guru_price: Decimal, increment: Decimal | None = None) -> Decimal:
        """The highest a copied buy pays, rounded down so it never passes the allowance."""
        ceiling = _checked(guru_price) * (Decimal(1) + self.max_above_signal_pct / Decimal(100))
        return ceiling.quantize(price_tick(ceiling, increment), rounding=ROUND_DOWN)

    def sell_floor(self, guru_price: Decimal, increment: Decimal | None = None) -> Decimal:
        """The lowest a copied sell takes, rounded up so it never passes the allowance. Every
        sell is a limit order, so a copy never fills far below what the guru got."""
        floor = _checked(guru_price) * (Decimal(1) - self.max_below_signal_pct / Decimal(100))
        return floor.quantize(price_tick(floor, increment), rounding=ROUND_UP)


def _checked(guru_price: Decimal) -> Decimal:
    if not guru_price.is_finite() or guru_price <= 0:
        raise ValueError("Signal price must be finite and positive")
    return guru_price


def price_tick(price: Decimal, increment: Decimal | None = None) -> Decimal:
    """The step a price moves in: a coin's own increment from Alpaca, else a stock's cent, or a
    hundredth of a cent under $1."""
    if increment is not None:
        return increment
    return Decimal("0.01") if price >= 1 else Decimal("0.0001")
