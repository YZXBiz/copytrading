"""Guru profiles (learned playbook, checked examples) and read-only evaluation."""

import datetime as dt
import hashlib
import json
from decimal import ROUND_DOWN, Decimal
from typing import Literal, Self

from pydantic import BaseModel, ConfigDict, Field, model_validator

from copytrading_engine.execution.domain.risk import requested_entry_budget
from copytrading_engine.execution.domain.sizing import RouteConnection
from copytrading_engine.parsing.application import transform
from copytrading_engine.parsing.extraction import DecodeError, Decoder, same_fraction
from copytrading_engine.parsing.routes import Route
from copytrading_engine.shared.raw_message import RawMessage
from copytrading_engine.shared.reading import PostReading
from copytrading_engine.shared.signals import Instruction

type ExitBasis = Literal["original_position", "remaining_position"]
PROFILE_EVALUATION_COST_NOTICE = (
    "Model calls use the configured provider; provider charges may apply."
)


class ProfileExample(BaseModel):
    """A source example paired with a finite, typed expected interpretation."""

    model_config = ConfigDict(extra="forbid", frozen=True, hide_input_in_errors=True)

    message: str = Field(min_length=1, max_length=2_000)
    expected_action: Literal["buy", "reduce", "close"]
    expected_symbol: str = Field(pattern=r"^[A-Z]{1,5}(?:[.][A-Z])?$")
    expected_fraction: Decimal | None = Field(default=None, gt=0, le=1)
    # The guru's price in the post, and for a sell the buy price it names (ADR-0010).
    expected_price: Decimal | None = Field(default=None, gt=0, le=100000)
    expected_buy_price: Decimal | None = Field(default=None, gt=0, le=100000)

    @model_validator(mode="after")
    def validate_expectation(self) -> Self:
        if self.expected_action == "buy":
            if self.expected_buy_price is not None:
                raise ValueError("A buy example names no buy price to sell from")
            return self
        if self.expected_fraction is None:
            raise ValueError("Exit examples require an explicit fraction")
        if self.expected_action == "close" and self.expected_fraction != 1:
            raise ValueError("Close examples use the full remaining quantity")
        if self.expected_action == "reduce" and self.expected_fraction == 1:
            raise ValueError("A full exit must use the close action")
        return self


PLAYBOOK_MAX_LENGTH = 8_000


class ProfileDraft(BaseModel):
    """What the owner saves for one guru: a playbook prompt and checked examples.

    The playbook is owner-written (usually edited from a learned draft) and reaches the model as
    trusted guidance. It never bypasses grounding: a ticker must appear in the post itself, or the
    playbook must state the name-to-ticker mapping.
    """

    model_config = ConfigDict(extra="forbid", frozen=True, hide_input_in_errors=True)

    guru_id: str = Field(pattern=r"^[a-zA-Z0-9_-]{1,64}$")
    display_name: str = Field(min_length=1, max_length=100)
    playbook: str = Field(max_length=PLAYBOOK_MAX_LENGTH)
    examples: tuple[ProfileExample, ...] = Field(default=(), max_length=32)

    @model_validator(mode="after")
    def validate_inputs(self) -> Self:
        if not self.display_name.strip():
            raise ValueError("Profile name is required")
        for example in self.examples:
            if not example.message.strip():
                raise ValueError("Profile examples cannot be blank")
        return self


class ReplayedPost(BaseModel):
    """What one recent post would have done under a guru's draft (ADR-0007); nothing was placed."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    text: str
    decision: Literal["trade", "ignore", "review"]
    reason: str
    reading: PostReading | None
    instructions: tuple[Instruction, ...]
    suggested: tuple[Instruction, ...]


class ProfileReplay(BaseModel):
    """A guru's recent posts read with the draft playbook and rules, before switching them on."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    posts: tuple[ReplayedPost, ...]
    provider: str
    model: str
    cost_notice: str = PROFILE_EVALUATION_COST_NOTICE


class LearnedPlaybook(BaseModel):
    """A draft for the owner to edit: nothing here is saved or used until they save the profile."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    posts_read: int = Field(ge=0)
    playbook: str = Field(max_length=PLAYBOOK_MAX_LENGTH)
    examples: tuple[ProfileExample, ...] = ()
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
    examples: tuple[ProfileExample, ...] = Field(default=(), max_length=32)
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
                    examples=(),
                )
            ),
        )


class InstructionEvaluation(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)

    action: Literal["buy", "reduce", "close"]
    symbol: str
    price: Decimal
    fraction: Decimal | None
    entry_price: Decimal | None
    exit_basis: ExitBasis | None
    action_evidence: str
    symbol_evidence: str
    price_evidence: str
    fraction_evidence: str | None


class DestinationEvaluation(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)

    account_id: str
    action: Literal["buy", "reduce", "close"]
    symbol: str
    budget_usd: Decimal | None
    estimated_quantity: Decimal | None
    exit_basis: ExitBasis | None
    reason: str


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


class ProfileExampleComparison(BaseModel):
    """A typed expectation compared with one read-only interpretation."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    example_index: int = Field(ge=0, le=31)
    expected_action: Literal["buy", "reduce", "close"]
    expected_symbol: str
    expected_fraction: Decimal | None
    actual: ProfileEvaluation
    matches: bool
    review_reasons: tuple[str, ...] = ()


class ProfileExampleReview(BaseModel):
    """Preview results; only fully matching examples permit activation."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    guru_id: str
    profile_revision: str
    provider: str
    model: str
    simulated: Literal[True] = True
    no_order: Literal[True] = True
    cost_notice: str = PROFILE_EVALUATION_COST_NOTICE
    examples: tuple[ProfileExampleComparison, ...] = ()
    review_reasons: tuple[str, ...] = ()
    automatic_activation_allowed: bool


class ProfileExampleReviewService:
    """Interpret finite examples for operator review without creating execution policy."""

    def __init__(self, decoder: Decoder, *, provider: str, model: str) -> None:
        self._decoder = decoder
        self.provider = provider
        self.model = model

    async def evaluate(
        self,
        profile: ProfileRevision,
        *,
        destinations: tuple[RouteConnection, ...],
    ) -> ProfileExampleReview:
        if len(destinations) > 20 or len({item.account_id for item in destinations}) != len(
            destinations
        ):
            raise ValueError("Evaluation destinations must be unique and bounded")

        comparisons: list[ProfileExampleComparison] = []
        all_reasons: list[str] = []
        evaluator = ProfileEvaluationService(
            self._decoder, provider=self.provider, model=self.model
        )
        for index, example in enumerate(profile.examples):
            message = RawMessage(
                schema_version=1,
                event_type="raw_message",
                source="profile_example",
                channel_id="profile_examples",
                id=f"{profile.profile_revision[:24]}_{index}",
                timestamp=dt.datetime.now(dt.UTC),
                text=example.message,
            )
            try:
                actual = await evaluator.evaluate(message, profile, destinations=destinations)
            except DecodeError as exc:
                reason = exc.issues[0].code if exc.issues else exc.reason
                actual = ProfileEvaluation(
                    message_identity=message.identity,
                    guru_id=profile.guru_id,
                    profile_revision=profile.profile_revision,
                    provider=self.provider,
                    model=self.model,
                    decision="review",
                    reason=reason,
                    destinations=tuple(
                        DestinationEvaluation(
                            account_id=connection.account_id,
                            action=example.expected_action,
                            symbol=example.expected_symbol,
                            budget_usd=None,
                            estimated_quantity=None,
                            exit_basis=None,
                            reason="example_interpretation_failed",
                        )
                        for connection in destinations
                    ),
                    review_reasons=(reason,),
                )
            if not actual.destinations and destinations:
                actual = actual.model_copy(
                    update={
                        "destinations": tuple(
                            DestinationEvaluation(
                                account_id=connection.account_id,
                                action=example.expected_action,
                                symbol=example.expected_symbol,
                                budget_usd=None,
                                estimated_quantity=None,
                                exit_basis=None,
                                reason="example_requires_review",
                            )
                            for connection in destinations
                        )
                    }
                )
            reasons: list[str] = []
            if actual.decision != "trade":
                reasons.append("example_did_not_produce_trade")
            if len(actual.instructions) != 1:
                reasons.append("example_requires_exactly_one_instruction")
            if len(actual.instructions) == 1:
                instruction = actual.instructions[0]
                if instruction.action != example.expected_action:
                    reasons.append("example_action_mismatch")
                if instruction.symbol != example.expected_symbol:
                    reasons.append("example_symbol_mismatch")
                if not same_fraction(instruction.fraction, example.expected_fraction):
                    reasons.append("example_fraction_mismatch")
                if (
                    example.expected_price is not None
                    and instruction.price != example.expected_price
                ):
                    reasons.append("example_price_mismatch")
                if (
                    example.expected_buy_price is not None or instruction.action != "buy"
                ) and instruction.entry_price != example.expected_buy_price:
                    reasons.append("example_buy_price_mismatch")
            matches = not reasons
            if not matches:
                all_reasons.extend(reasons)
            all_reasons.extend(actual.review_reasons)
            comparisons.append(
                ProfileExampleComparison(
                    example_index=index,
                    expected_action=example.expected_action,
                    expected_symbol=example.expected_symbol,
                    expected_fraction=example.expected_fraction,
                    actual=actual,
                    matches=matches,
                    review_reasons=tuple(dict.fromkeys((*reasons, *actual.review_reasons))),
                )
            )

        cost_notice = (
            f"Examples are interpreted by {self.provider} ({self.model}); "
            "provider charges may apply."
        )
        activation_allowed = all(comparison.matches for comparison in comparisons)
        return ProfileExampleReview(
            guru_id=profile.guru_id,
            profile_revision=profile.profile_revision,
            provider=self.provider,
            model=self.model,
            cost_notice=cost_notice,
            examples=tuple(comparisons),
            review_reasons=tuple(dict.fromkeys(all_reasons)),
            automatic_activation_allowed=activation_allowed,
        )


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
                entry_price=item.entry_price,
                exit_basis=item.exit_basis,
                action_evidence=item.action_evidence,
                symbol_evidence=item.symbol_evidence,
                price_evidence=item.price_evidence,
                fraction_evidence=item.fraction_evidence,
            )
            for item in signal.evidence
        )
        evaluations: list[DestinationEvaluation] = []
        review_reasons: list[str] = []
        if signal.decision == "review":
            review_reasons.append(signal.reason)
        for connection in destinations:
            for instruction in instructions:
                if instruction.action == "buy":
                    sized = requested_entry_budget(connection, instruction.fraction)
                    quantity = (
                        (sized.budget / instruction.price).quantize(
                            Decimal("0.000001"), rounding=ROUND_DOWN
                        )
                        if sized.budget is not None
                        else None
                    )
                    reason = sized.reason
                    if reason != "ready":
                        review_reasons.append(reason)
                    evaluations.append(
                        DestinationEvaluation(
                            account_id=connection.account_id,
                            action=instruction.action,
                            symbol=instruction.symbol,
                            budget_usd=sized.budget,
                            estimated_quantity=quantity,
                            exit_basis=None,
                            reason=reason,
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
                            reason="position_required_for_exit_sizing",
                        )
                    )
                    review_reasons.append("position_required_for_exit_sizing")
        return ProfileEvaluation(
            message_identity=message.identity,
            guru_id=profile.guru_id,
            profile_revision=profile.profile_revision,
            provider=self.provider,
            model=self.model,
            decision=signal.decision,
            reason=signal.reason,
            instructions=instructions,
            destinations=tuple(evaluations),
            review_reasons=tuple(dict.fromkeys(review_reasons)),
        )
