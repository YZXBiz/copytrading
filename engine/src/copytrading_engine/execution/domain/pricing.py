"""Deterministic signal pricing policy, independent of quotes and broker clients."""

import datetime as dt
from decimal import ROUND_DOWN, ROUND_UP, Decimal

from pydantic import BaseModel, ConfigDict, Field

from copytrading_engine.execution.domain.market import Quote

# A quote older than this is not the market now.
QUOTE_MAX_AGE_SECONDS = 30


def quote_problem(quote: Quote, price: Decimal | None, now: dt.datetime) -> str | None:
    """Why a quote's price cannot stand for the market now, if it cannot."""
    if quote.timestamp is None or price is None or price <= 0:
        return "quote_unavailable"
    age = (now - quote.timestamp).total_seconds()
    if age < -5 or age > QUOTE_MAX_AGE_SECONDS:
        return "quote_stale"
    return None


class EntryPricingPolicy(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)
    max_above_signal_pct: Decimal = Field(default=Decimal("0"), ge=0, le=100)
    # How far the market may be from the guru's price, up or down, before a buy waits for the
    # owner instead of going through (ADR-0007).
    max_price_move_pct: Decimal = Field(default=Decimal("5"), gt=0, le=100)

    def market_moved(self, signal_price: Decimal, market: Decimal) -> bool:
        """Whether the market is further from the guru's price than the owner allows."""
        return abs(market - signal_price) * 100 > self.max_price_move_pct * signal_price

    def limit_price(self, signal_price: Decimal) -> Decimal:
        """Return a valid stock tick that never exceeds the configured ceiling."""
        if not signal_price.is_finite() or signal_price <= 0:
            raise ValueError("Signal price must be finite and positive")
        ceiling = signal_price * (Decimal(1) + self.max_above_signal_pct / Decimal(100))
        tick = Decimal("0.01") if ceiling >= 1 else Decimal("0.0001")
        return ceiling.quantize(tick, rounding=ROUND_DOWN)

    def exit_limit_price(self, signal_price: Decimal) -> Decimal:
        """Return a valid stock tick that never falls below the same distance under the signal.

        Brokers accept only limit orders outside regular hours, so an extended-hours exit sells
        no further from the guru's price than an entry may buy above it.
        """
        if not signal_price.is_finite() or signal_price <= 0:
            raise ValueError("Signal price must be finite and positive")
        floor = signal_price * (Decimal(1) - self.max_above_signal_pct / Decimal(100))
        tick = Decimal("0.01") if floor >= 1 else Decimal("0.0001")
        return floor.quantize(tick, rounding=ROUND_UP)
