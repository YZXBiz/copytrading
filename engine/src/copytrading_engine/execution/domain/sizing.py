"""Immutable destination sizing terms carried with each delivered source signal."""

from decimal import Decimal
from typing import Literal, Self

from pydantic import BaseModel, ConfigDict, Field, model_validator

from copytrading_engine.shared.signals import StockSignal


class RouteConnection(BaseModel):
    model_config = ConfigDict(frozen=True, extra="forbid", hide_input_in_errors=True)

    account_id: str = Field(pattern=r"^[a-zA-Z0-9_-]{1,64}$")
    mode: Literal["fixed", "proportional"]
    amount_usd: Decimal = Field(gt=0, decimal_places=2, allow_inf_nan=False)
    default_fraction: Decimal | None = Field(default=None, gt=0, le=1, allow_inf_nan=False)

    @model_validator(mode="after")
    def valid_default(self) -> Self:
        if self.mode == "fixed" and self.default_fraction is not None:
            raise ValueError("Fixed sizing cannot have a fraction default")
        return self


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
