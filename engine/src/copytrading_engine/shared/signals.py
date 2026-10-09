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
    # The guru's price. A sell the post gives no price, or says is at the market, has none: it
    # sells at the market when it is placed, as a limit just under the live bid (ADR-0007).
    price: Decimal | None = Field(gt=0, le=100000)
    entry_price: Decimal | None = Field(default=None, gt=0, le=100000)
    fraction: Decimal | None = Field(default=None, gt=0, le=1, allow_inf_nan=False)
    # An exit's share counts from what is left of the buys it sells from, unless the post or the
    # playbook says the original buy (ADR-0010).
    exit_basis: Literal["original_position", "remaining_position"] | None = None

    @model_validator(mode="after")
    def validate_reference(self) -> Self:
        # An exit with no entry price sells from every open buy of the stock; with one, from the
        # buys at exactly that price (ADR-0010).
        if self.action == "buy" and self.entry_price is not None:
            raise PydanticCustomError(
                "entry_has_lot_reference", "An entry cannot reference an existing lot"
            )
        if self.action == "buy" and self.price is None:
            raise ValueError("A buy needs the guru's price")
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
    # None for a sell at the market: there is no price to cite. "At market" words, when the post
    # has them, are in the reading.
    price_evidence: str | None = Field(min_length=1, max_length=30)
    entry_evidence: str | None = Field(default=None, max_length=30)
    fraction_evidence: str | None = Field(default=None, max_length=30)

    @model_validator(mode="after")
    def validate_price_evidence(self) -> Self:
        if (self.price is None) != (self.price_evidence is None):
            raise ValueError("A stated price needs its words, and only a stated price has them")
        return self


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
    # For a post that waits for the owner: what Copy places, as the reader read it (ADR-0007).
    suggested: tuple[Instruction, ...] = Field(default=(), max_length=20)
    evidence: tuple[Evidence, ...] = Field(max_length=20)
    instructions: tuple[Instruction, ...] = Field(max_length=20)

    @model_validator(mode="after")
    def validate_decision(self) -> Self:
        if (self.guru_id is None) != (self.profile_revision is None):
            raise ValueError("Guru identity and profile revision must be recorded together")
        if (self.decision == "trade") != bool(self.instructions):
            raise ValueError("Only validated trade decisions contain instructions")
        if self.suggested and self.decision != "review":
            raise ValueError("Only a post that waits for the owner suggests calls to copy")
        if len(self.evidence) != len(self.instructions):
            raise ValueError("Every instruction requires evidence")
        for instruction, evidence in zip(self.instructions, self.evidence, strict=True):
            for field in Instruction.model_fields:
                if getattr(instruction, field) != getattr(evidence, field):
                    raise ValueError("Instruction differs from its validated evidence")
        return self
