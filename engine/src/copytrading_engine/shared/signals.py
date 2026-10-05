"""Version 2 stock signal contract. Prices and quantities are decimal strings."""

from decimal import Decimal
from typing import Literal, Self

from pydantic import AwareDatetime, BaseModel, ConfigDict, Field, model_validator
from pydantic_core import PydanticCustomError

from copytrading_engine.shared.reading import PostReading


class SourceIdentityConflict(ValueError):
    """An existing source message identity was reused with different content."""


class Instruction(BaseModel):
    model_config = ConfigDict(frozen=True, extra="forbid")
    action: Literal["buy", "reduce", "close"]
    symbol: str = Field(pattern=r"^[A-Z]{1,5}(?:[.][A-Z])?$")
    price: Decimal = Field(gt=0, le=100000)
    entry_price: Decimal | None = Field(default=None, gt=0, le=100000)
    fraction: Decimal | None = Field(default=None, gt=0, le=1, allow_inf_nan=False)
    exit_basis: Literal["original_position", "remaining_position"] | None = None
    # For a guru whose sells refer to the whole position (ADR-0007): a buy joins the stock's open
    # lot, and a sell sells from it, naming no buy price.
    whole_position: bool = False

    @model_validator(mode="after")
    def validate_reference(self) -> Self:
        if self.action != "buy" and self.entry_price is None and not self.whole_position:
            raise PydanticCustomError(
                "exit_missing_lot_reference", "An exit requires an explicit source entry reference"
            )
        if self.action != "buy" and self.entry_price is not None and self.whole_position:
            raise ValueError("A whole-position exit names no buy price")
        if self.action == "buy" and self.entry_price is not None:
            raise PydanticCustomError(
                "entry_has_lot_reference", "An entry cannot reference an existing lot"
            )
        if self.action != "buy" and self.fraction is None:
            raise ValueError("An exit requires an explicit fraction")
        if self.action == "close" and self.fraction != 1:
            raise ValueError("A close uses all remaining shares")
        if self.action == "buy" and self.exit_basis is not None:
            raise ValueError("Entry instructions cannot carry an exit basis")
        return self


class Evidence(Instruction):
    action_evidence: str = Field(min_length=1, max_length=100)
    symbol_evidence: str = Field(min_length=1, max_length=30)
    price_evidence: str = Field(min_length=1, max_length=30)
    entry_evidence: str | None = Field(default=None, max_length=30)
    fraction_evidence: str | None = Field(default=None, max_length=30)


class StockSignal(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True, hide_input_in_errors=True)
    schema_version: Literal[2] = 2
    event_type: Literal["stock_signal"] = "stock_signal"
    source: str = Field(pattern=r"^[a-z][a-z0-9_-]*$")
    channel_id: str = Field(pattern=r"^[a-zA-Z0-9_-]+$")
    author_id: str | None = Field(default=None, pattern=r"^[0-9]{1,32}$")
    id: str = Field(pattern=r"^[a-zA-Z0-9_-]+$")
    timestamp: AwareDatetime
    text: str = Field(max_length=50000)
    parser_profile: str
    model: str
    guru_id: str | None = Field(default=None, pattern=r"^[a-zA-Z0-9_-]{1,64}$")
    profile_revision: str | None = Field(default=None, pattern=r"^[0-9a-f]{64}$")
    decision: Literal["trade", "ignore", "review"]
    reason: str = Field(min_length=1, max_length=300)
    # How the reader read the post (ADR-0007); absent on signals read before it, or never sent
    # to the reader.
    reading: PostReading | None = None
    evidence: tuple[Evidence, ...] = Field(max_length=20)
    instructions: tuple[Instruction, ...] = Field(max_length=20)

    @model_validator(mode="after")
    def validate_decision(self) -> Self:
        if (self.guru_id is None) != (self.profile_revision is None):
            raise ValueError("Guru identity and profile revision must be recorded together")
        if (self.decision == "trade") != bool(self.instructions):
            raise ValueError("Only validated trade decisions contain instructions")
        if len(self.evidence) != len(self.instructions):
            raise ValueError("Every instruction requires evidence")
        for instruction, evidence in zip(self.instructions, self.evidence, strict=True):
            for field in Instruction.model_fields:
                if getattr(instruction, field) != getattr(evidence, field):
                    raise ValueError("Instruction differs from its validated evidence")
            if (
                self.guru_id is not None
                and instruction.action != "buy"
                and instruction.exit_basis is None
            ):
                raise ValueError("Profile exits require an explicit exit basis")
        return self
