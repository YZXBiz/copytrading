"""Guru profiles (learned playbook) and read-only evaluation."""

import hashlib
import json
from collections.abc import Sequence
from decimal import ROUND_DOWN, Decimal
from typing import Literal, Self

from pydantic import BaseModel, ConfigDict, Field, model_validator

from copytrading_engine.execution.domain.risk import requested_entry_budget
from copytrading_engine.execution.domain.sizing import RouteConnection
from copytrading_engine.parsing.application import transform
from copytrading_engine.parsing.extraction import Decoder
from copytrading_engine.parsing.routes import Route
from copytrading_engine.shared.raw_message import RawMessage
from copytrading_engine.shared.signals import Instruction

type ExitBasis = Literal["original_position", "remaining_position"]
PROFILE_EVALUATION_COST_NOTICE = (
    "Model calls use the configured provider; provider charges may apply."
)


PLAYBOOK_MAX_LENGTH = 8_000


class ProfileDraft(BaseModel):
    """What the owner saves for one guru: a playbook prompt.

    The playbook is owner-written (usually edited from a learned draft) and reaches the model as
    trusted guidance. It never bypasses grounding: a ticker must appear in the post itself, or the
    playbook must state the name-to-ticker mapping.
    """

    model_config = ConfigDict(extra="forbid", frozen=True, hide_input_in_errors=True)

    guru_id: str = Field(pattern=r"^[a-zA-Z0-9_-]{1,64}$")
    display_name: str = Field(min_length=1, max_length=100)
    playbook: str = Field(max_length=PLAYBOOK_MAX_LENGTH)

    @model_validator(mode="after")
    def validate_inputs(self) -> Self:
        if not self.display_name.strip():
            raise ValueError("Profile name is required")
        return self


class LearnedPlaybook(BaseModel):
    """A draft for the owner to edit: nothing here is saved or used until they save the profile."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    posts_read: int = Field(ge=0)
    playbook: str = Field(max_length=PLAYBOOK_MAX_LENGTH)
    summary: str
    provider: str
    model: str
    cost_notice: str = PROFILE_EVALUATION_COST_NOTICE


def _profile_digest(data: dict[str, object]) -> str:
    encoded = json.dumps(data, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(encoded.encode()).hexdigest()


class ProfileRevision(BaseModel):
    """Immutable, content-addressed interpretation settings for one stable guru."""

    model_config = ConfigDict(extra="forbid", frozen=True, hide_input_in_errors=True)

    guru_id: str = Field(pattern=r"^[a-zA-Z0-9_-]{1,64}$")
    display_name: str = Field(min_length=1, max_length=100)
    playbook: str = Field(max_length=PLAYBOOK_MAX_LENGTH)
    profile_revision: str = Field(pattern=r"^[0-9a-f]{64}$")

    @model_validator(mode="after")
    def validate_revision(self) -> Self:
        base = self.model_dump(mode="json", exclude={"profile_revision"})
        if self.profile_revision != _profile_digest(base):
            raise ValueError("Profile revision does not match its immutable content")
        return self

    def route(self) -> Route:
        """How the reader and its rules treat this guru's posts."""
        return Route(
            playbook=self.playbook, guru_id=self.guru_id, profile_revision=self.profile_revision
        )


class ProfileBuilder:
    """Build content-addressed profile revisions."""

    def build(self, draft: ProfileDraft) -> ProfileRevision:
        draft = ProfileDraft.model_validate(draft.model_dump())
        data = draft.model_dump(mode="json")
        return ProfileRevision(**data, profile_revision=_profile_digest(data))

    def prepared_profiles(self) -> tuple[ProfileRevision, ...]:
        return (
            self.build(
                ProfileDraft(
                    guru_id="prepared-standard",
                    display_name="Standard stock alerts",
                    playbook="",
                )
            ),
        )


class InstructionEvaluation(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)

    action: Literal["buy", "reduce", "close"]
    symbol: str
    # None for a sell at the market (ADR-0007).
    price: Decimal | None
    fraction: Decimal | None
    entry_price: Decimal | None
    exit_basis: ExitBasis | None
    action_evidence: str
    symbol_evidence: str
    price_evidence: str | None
    fraction_evidence: str | None
    # A buy sized in dollars ("$200 of NFLX"), and the post's words for it.
    usd_amount: Decimal | None = None
    usd_amount_evidence: str | None = None


class DestinationEvaluation(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)

    account_id: str
    action: Literal["buy", "reduce", "close"]
    symbol: str
    budget_usd: Decimal | None
    estimated_quantity: Decimal | None
    exit_basis: ExitBasis | None
    reason: str


def size_destinations(
    instructions: Sequence[Instruction | InstructionEvaluation],
    destinations: Sequence[RouteConnection],
) -> tuple[DestinationEvaluation, ...]:
    """What each account would do with each instruction: a buy's budget and shares after the
    owner's limits; a sell takes from what the account holds. Nothing is placed."""
    evaluations: list[DestinationEvaluation] = []
    for connection in destinations:
        for instruction in instructions:
            if instruction.action == "buy":
                assert instruction.price is not None  # a buy always has the guru's price
                sized = requested_entry_budget(
                    connection, instruction.fraction, instruction.usd_amount
                )
                quantity = (
                    (sized.budget / instruction.price).quantize(
                        Decimal("0.000001"), rounding=ROUND_DOWN
                    )
                    if sized.budget is not None
                    else None
                )
                evaluations.append(
                    DestinationEvaluation(
                        account_id=connection.account_id,
                        action=instruction.action,
                        symbol=instruction.symbol,
                        budget_usd=sized.budget,
                        estimated_quantity=quantity,
                        exit_basis=None,
                        reason=sized.reason,
                    )
                )
            else:
                evaluations.append(
                    DestinationEvaluation(
                        account_id=connection.account_id,
                        action=instruction.action,
                        symbol=instruction.symbol,
                        budget_usd=None,
                        estimated_quantity=None,
                        exit_basis=instruction.exit_basis,
                        reason="sells_from_holdings",
                    )
                )
    return tuple(evaluations)


class ProfileEvaluation(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)

    message_identity: str
    guru_id: str
    profile_revision: str
    provider: str
    model: str
    decision: Literal["trade", "ignore", "review"]
    reason: str
    simulated: Literal[True] = True
    no_order: Literal[True] = True
    cost_notice: str = PROFILE_EVALUATION_COST_NOTICE
    instructions: tuple[InstructionEvaluation, ...] = ()
    destinations: tuple[DestinationEvaluation, ...] = ()
    review_reasons: tuple[str, ...] = ()


class ProfileEvaluationService:
    """Interpret one historical message and size destinations without execution."""

    def __init__(self, decoder: Decoder, *, provider: str, model: str) -> None:
        if not provider or not model:
            raise ValueError("Provider and model identity are required")
        self._decoder = decoder
        self.provider = provider
        self.model = model

    async def evaluate(
        self,
        message: RawMessage,
        profile: ProfileRevision,
        *,
        destinations: tuple[RouteConnection, ...],
    ) -> ProfileEvaluation:
        message = RawMessage.model_validate(message.model_dump())
        if len(destinations) > 20 or len({item.account_id for item in destinations}) != len(
            destinations
        ):
            raise ValueError("Evaluation destinations must be unique and bounded")
        signal = await transform(message, profile.route(), self._decoder, self.model)
        instructions = tuple(
            InstructionEvaluation(
                action=item.action,
                symbol=item.symbol,
                price=item.price,
                fraction=item.fraction,
                usd_amount=item.usd_amount,
                entry_price=item.entry_price,
                exit_basis=item.exit_basis,
                action_evidence=item.action_evidence,
                symbol_evidence=item.symbol_evidence,
                price_evidence=item.price_evidence,
                fraction_evidence=item.fraction_evidence,
                usd_amount_evidence=item.usd_amount_evidence,
            )
            for item in signal.evidence
        )
        evaluations = size_destinations(instructions, destinations)
        review_reasons = [signal.reason] if signal.decision == "review" else []
        review_reasons += [
            item.reason for item in evaluations if item.action == "buy" and item.reason != "ready"
        ]
        return ProfileEvaluation(
            message_identity=message.identity,
            guru_id=profile.guru_id,
            profile_revision=profile.profile_revision,
            provider=self.provider,
            model=self.model,
            decision=signal.decision,
            reason=signal.reason,
            instructions=instructions,
            destinations=evaluations,
            review_reasons=tuple(dict.fromkeys(review_reasons)),
        )
