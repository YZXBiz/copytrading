"""Validated per-account execution policy."""

from decimal import Decimal
from typing import Annotated, Self

from pydantic import BaseModel, ConfigDict, Field, StrictBool, StrictInt, model_validator

from copytrading_engine.execution.domain.pricing import EntryPricingPolicy


class SignalSourceNotAllowed(ValueError):
    """A valid signal belongs to a source outside this account's allowlist."""


class CopyConfig(BaseModel):
    """Validated startup policy; collections cannot change after validation."""

    model_config = ConfigDict(extra="forbid", frozen=True, hide_input_in_errors=True)
    sources: tuple[Annotated[str, Field(pattern=r"^[a-z][a-z0-9_-]*:[a-zA-Z0-9_-]+$")], ...] = (
        Field(min_length=1)
    )
    entry_pricing: EntryPricingPolicy = Field(default_factory=EntryPricingPolicy)
    max_order_usd: Decimal = Field(default=Decimal("100"), gt=0, allow_inf_nan=False)
    max_symbol_usd: Decimal = Field(default=Decimal("600"), gt=0)
    max_total_usd: Decimal = Field(default=Decimal("2500"), gt=0)
    daily_loss_cap_usd: Decimal = Field(default=Decimal("250"), gt=0)
    max_entries_per_day: StrictInt = Field(default=30, gt=0)
    max_signal_age_seconds: StrictInt = Field(default=120, gt=0, le=600)
    order_timeout_seconds: StrictInt = Field(default=60, gt=0, le=600)
    poll_seconds: float = Field(default=2, ge=1, le=30)
    extended_hours: StrictBool = True
    overnight: StrictBool = False
    copy_exits: StrictBool = True
    # Off by default. On, no order is sent by itself: a call that would have traded waits for
    # the owner, who approves it in the app (ADR-0008).
    approve_orders: StrictBool = False

    @model_validator(mode="after")
    def validate_sessions(self) -> Self:
        if self.overnight and not self.extended_hours:
            raise ValueError("Overnight trading requires extended_hours")
        return self
