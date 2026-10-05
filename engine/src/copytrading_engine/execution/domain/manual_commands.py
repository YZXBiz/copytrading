"""Immutable evidence and wire contracts for reviewed manual commands."""

from decimal import Decimal
from typing import Literal, Self

from pydantic import AwareDatetime, Field, model_validator

from copytrading_engine.execution.domain.market import Quote
from copytrading_engine.execution.domain.order_lifecycle import OrderStatus
from copytrading_engine.execution.domain.orders import OrderPlan
from copytrading_engine.execution.domain.sessions import Session
from copytrading_engine.execution.domain.values import Identifier, Positive, Quantity, Value
from copytrading_engine.shared.signals import Instruction, StockSignal


class ManualCorrectionRequest(Value):
    """One immutable reviewed interpretation shared by selected local accounts."""

    correction_id: Identifier
    source_id: Identifier
    selected_account_ids: tuple[Identifier, ...] = Field(min_length=1, max_length=20)
    actor: Identifier
    reason: Identifier
    instructions: tuple[Instruction, ...] = Field(min_length=1, max_length=20)

    @model_validator(mode="after")
    def valid_identity(self) -> Self:
        if not self.actor.strip() or not self.reason.strip():
            raise ValueError("Manual correction requires an actor and reason")
        if self.selected_account_ids != tuple(sorted(set(self.selected_account_ids))):
            raise ValueError("Selected account IDs must be unique and sorted")
        return self


class ManualSourceEvidence(Value):
    """Trusted source-store evidence copied before a correction can be admitted."""

    source_id: Identifier
    source_revision: int = Field(ge=1)
    source_at: AwareDatetime
    text: str = Field(min_length=1, max_length=50_000)
    accepted_interpretation: StockSignal

    @model_validator(mode="after")
    def matches_interpretation(self) -> Self:
        signal = self.accepted_interpretation
        if (
            self.source_id != f"{signal.source}:{signal.channel_id}:{signal.id}"
            or self.source_at != signal.timestamp
            or self.text != signal.text
        ):
            raise ValueError("Source evidence differs from its accepted interpretation")
        if signal.decision == "ignore":
            raise ValueError("An ignored post has nothing to copy")
        return self


class ManualCorrectionRecord(Value):
    """Account-owner copy of the exact correction and its original evidence."""

    correction_id: Identifier
    source_id: Identifier
    selected_account_ids: tuple[Identifier, ...] = Field(min_length=1, max_length=20)
    revision: int = Field(ge=1)
    actor: Identifier
    reason: Identifier
    instructions: tuple[Instruction, ...] = Field(min_length=1, max_length=20)
    source_revision: int = Field(ge=1)
    source_at: AwareDatetime
    source_text: str = Field(min_length=1, max_length=50_000)
    accepted_interpretation: StockSignal
    recorded_at: AwareDatetime

    @model_validator(mode="after")
    def valid_identity(self) -> Self:
        signal = self.accepted_interpretation
        if self.selected_account_ids != tuple(sorted(set(self.selected_account_ids))):
            raise ValueError("Selected account IDs must be unique and sorted")
        if not self.actor.strip() or not self.reason.strip():
            raise ValueError("Manual correction requires an actor and reason")
        if (
            self.source_id != f"{signal.source}:{signal.channel_id}:{signal.id}"
            or self.source_at != signal.timestamp
            or self.source_text != signal.text
            or signal.decision == "ignore"
        ):
            raise ValueError("Correction does not retain matching reviewed source evidence")
        return self

    def matches_request(self, request: ManualCorrectionRequest) -> bool:
        return (
            self.correction_id == request.correction_id
            and self.source_id == request.source_id
            and self.selected_account_ids == request.selected_account_ids
            and self.actor == request.actor
            and self.reason == request.reason
            and self.instructions == request.instructions
        )


class ManualPreviewRequest(Value):
    preview_id: Identifier
    account_id: Identifier
    correction_id: Identifier
    instruction_index: int = Field(ge=0)


class ManualCheck(Value):
    name: Literal[
        "source",
        "account",
        "permission",
        "session",
        "quote",
        "risk",
        "ownership",
        "activity",
        "prior_action",
    ]
    status: Literal["passed", "warning", "blocked"]
    reason: str | None = None


class ManualOrderPreview(Value):
    request: ManualPreviewRequest
    broker_account_id: Identifier
    environment: Literal["paper", "live"]
    correction_revision: int = Field(ge=1)
    source_at: AwareDatetime
    source_age_seconds: int
    instruction: Instruction
    created_at: AwareDatetime
    expires_at: AwareDatetime
    session: Session | None
    quote: Quote | None
    fresh_price: Positive | None
    plan: OrderPlan | None
    checks: tuple[ManualCheck, ...]
    reasons: tuple[Identifier, ...]
    facts_sha256: str = Field(pattern=r"^[0-9a-f]{64}$")
    configuration_sha256: str = Field(pattern=r"^[0-9a-f]{64}$")

    @model_validator(mode="after")
    def valid_decision(self) -> Self:
        if (self.plan is not None) != (not self.reasons):
            raise ValueError("A manual preview plan must agree with its blocking reasons")
        if self.expires_at <= self.created_at:
            raise ValueError("Manual preview expiration must follow its creation")
        if (self.quote is None) != (self.fresh_price is None):
            raise ValueError("A fresh preview price requires its quote evidence")
        if self.plan is not None and self.session is None:
            raise ValueError("A ready manual preview requires a market session")
        return self


class ManualConfirmationRequest(Value):
    command_id: Identifier
    preview_id: Identifier
    account_id: Identifier
    actor: Identifier

    @model_validator(mode="after")
    def valid_actor(self) -> Self:
        if not self.actor.strip():
            raise ValueError("Manual confirmation requires an actor")
        return self


class ManualCommandRecord(Value):
    request: ManualConfirmationRequest
    correction_id: Identifier
    source_id: Identifier
    instruction_index: int = Field(ge=0)
    confirmed_at: AwareDatetime
    state: Literal["rejected", "prepared"]
    reason: Identifier | None = None
    client_id: Identifier | None = None

    @model_validator(mode="after")
    def valid_state(self) -> Self:
        if self.state == "rejected" and (self.reason is None or self.client_id is not None):
            raise ValueError("Rejected manual command requires a reason and no order intent")
        if self.state == "prepared" and (self.reason is not None or self.client_id is None):
            raise ValueError("Prepared manual command requires its order intent")
        return self


class ManualCommandResult(Value):
    command: ManualCommandRecord
    status: Literal[
        "rejected",
        "prepared",
        "uncertain",
        "accepted",
        "partially_filled",
        "filled",
        "cancelled",
        "broker_rejected",
        "expired",
    ]
    reason: Identifier | None = None
    client_id: Identifier | None = None
    broker_order_id: Identifier | None = None
    order_status: OrderStatus | None = None
    filled_qty: Quantity = Decimal(0)


class ManualCorrectionAccountResult(Value):
    account_id: Identifier
    status: Literal["recorded", "unavailable", "failed"]
    reason: Identifier | None = None


class ManualCorrectionOutcome(Value):
    correction: ManualCorrectionRecord
    accounts: tuple[ManualCorrectionAccountResult, ...]


class ManualAccountCommandResult(Value):
    account_id: Identifier
    command_id: Identifier
    result: ManualCommandResult | None = None
    error: Identifier | None = None

    @model_validator(mode="after")
    def has_one_outcome(self) -> Self:
        if (self.result is None) == (self.error is None):
            raise ValueError("Manual account command needs exactly one outcome")
        if self.result is not None and self.result.command.request.account_id != self.account_id:
            raise ValueError("Manual command result belongs to another account")
        return self


class ManualCommandsOutcome(Value):
    outcomes: tuple[ManualAccountCommandResult, ...]


class ManualCommandPage(Value):
    account_id: Identifier
    source_id: Identifier
    items: tuple[ManualCommandResult, ...]
    next_before_command_id: Identifier | None = None

    @model_validator(mode="after")
    def rows_match_page_identity(self) -> Self:
        if any(
            item.command.request.account_id != self.account_id
            or item.command.source_id != self.source_id
            for item in self.items
        ):
            raise ValueError("Manual command page contains a result for another account or source")
        return self


class ManualCommandPageRequest(Value):
    account_id: Identifier
    source_id: Identifier
    before_command_id: Identifier | None = None
    limit: int = Field(default=50, ge=1, le=100)
