"""Deterministic signal pricing policy, independent of quotes and broker clients."""

from decimal import ROUND_DOWN, ROUND_UP, Decimal

from pydantic import BaseModel, ConfigDict, Field


class EntryPricingPolicy(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)
    max_above_signal_pct: Decimal = Field(default=Decimal("0"), ge=0, le=100)

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
