"""Immutable destination sizing terms carried with each delivered source signal."""

from decimal import Decimal
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator

from copytrading_engine.shared.signals import StockSignal


class RouteConnection(BaseModel):
    """One guru copying into one account (ADR-0007). The guru's full position is the account's
    maximum per stock; a call buys its share of it."""

    model_config = ConfigDict(frozen=True, extra="forbid", hide_input_in_errors=True)

    account_id: str = Field(pattern=r"^[a-zA-Z0-9_-]{1,64}$")
    full_position_usd: Decimal = Field(gt=0, decimal_places=2, allow_inf_nan=False)
    # The share a call that names no size buys; None leaves such a call for the owner.
    default_fraction: Decimal | None = Field(default=Decimal(1), gt=0, le=1, allow_inf_nan=False)


class DestinationTerms(BaseModel):
    model_config = ConfigDict(frozen=True, extra="forbid", hide_input_in_errors=True)

    connection: RouteConnection
    environment: Literal["paper", "live"]
    configuration_revision: str = Field(pattern=r"^[0-9a-f]{64}$")
    guru_id: str | None = Field(default=None, pattern=r"^[a-zA-Z0-9_-]{1,64}$")
    profile_revision: str | None = Field(default=None, pattern=r"^[0-9a-f]{64}$")

    @model_validator(mode="after")
    def validate_profile_reference(self) -> DestinationTerms:
        if (self.guru_id is None) != (self.profile_revision is None):
            raise ValueError("Guru identity and profile revision must be recorded together")
        return self


class DestinationSignal(BaseModel):
    model_config = ConfigDict(frozen=True, extra="forbid", hide_input_in_errors=True)

    signal: StockSignal
    terms: DestinationTerms

    @model_validator(mode="after")
    def profile_matches_signal(self) -> DestinationSignal:
        if (self.signal.guru_id, self.signal.profile_revision) != (
            self.terms.guru_id,
            self.terms.profile_revision,
        ):
            raise ValueError("Accepted destination evidence must retain its profile revision")
        return self
