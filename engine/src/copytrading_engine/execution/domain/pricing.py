"""Deterministic signal pricing policy, independent of quotes and broker clients."""

import datetime as dt
from decimal import ROUND_DOWN, ROUND_UP, Decimal

from pydantic import BaseModel, ConfigDict, Field

from copytrading_engine.execution.domain.market import Quote

# A quote older than this is not the market now.
QUOTE_MAX_AGE_SECONDS = 30
# A sell at the market only takes its floor from the bid: an older bid can leave the order resting
# but never fill it worse, since a limit sell fills at the market's better price. Outside regular
# hours the free feed stops updating at the close, so the day's last bid is the bid there is; at
# worst the sell rests until its timeout and the shares stay.
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


class EntryPricingPolicy(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)
    max_above_signal_pct: Decimal = Field(default=Decimal("0"), ge=0, le=100)
    # How far below the guru's sell price an exit may fill: a sell is always a limit order.
    max_below_signal_pct: Decimal = Field(default=Decimal("1"), ge=0, le=100)

    def limit_price(self, signal_price: Decimal) -> Decimal:
        """Return a valid stock tick that never exceeds the configured ceiling."""
        if not signal_price.is_finite() or signal_price <= 0:
            raise ValueError("Signal price must be finite and positive")
        ceiling = signal_price * (Decimal(1) + self.max_above_signal_pct / Decimal(100))
        tick = Decimal("0.01") if ceiling >= 1 else Decimal("0.0001")
        return ceiling.quantize(tick, rounding=ROUND_DOWN)

    def exit_limit_price(self, signal_price: Decimal) -> Decimal:
        """Return a valid stock tick no lower than the allowed distance under the guru's price.

        Every exit is a limit order, so a copied sell never fills far below what the guru got.
        """
        if not signal_price.is_finite() or signal_price <= 0:
            raise ValueError("Signal price must be finite and positive")
        floor = signal_price * (Decimal(1) - self.max_below_signal_pct / Decimal(100))
        tick = Decimal("0.01") if floor >= 1 else Decimal("0.0001")
        return floor.quantize(tick, rounding=ROUND_UP)
