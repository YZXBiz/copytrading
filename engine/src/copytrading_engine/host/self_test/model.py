"""Immutable workflow values and invariants shared by all engine adapters."""

from dataclasses import dataclass
from decimal import Decimal
from enum import StrEnum
from fractions import Fraction
from typing import Literal

from copytrading_engine.host.errors import InvalidCommand

ALLOWED_DESTINATIONS = frozenset({"self-test-a", "self-test-b"})


class Stage(StrEnum):
    CAPTURED = "captured"
    PARSED = "parsed"
    COMPLETED = "completed"
    FAILED = "failed"


@dataclass(frozen=True)
class SubmitSelfTest:
    command_id: str
    text: str
    destination_ids: tuple[str, ...]

    def __post_init__(self) -> None:
        if not self.command_id or len(self.command_id) > 128:
            raise InvalidCommand("command_id must contain 1 to 128 characters")
        if not self.text:
            raise InvalidCommand("text must not be empty")
        if not self.destination_ids:
            raise InvalidCommand("at least one self-test destination is required")
        if len(set(self.destination_ids)) != len(self.destination_ids):
            raise InvalidCommand("destination_ids must not contain duplicates")
        if any(destination not in ALLOWED_DESTINATIONS for destination in self.destination_ids):
            raise InvalidCommand("destination is outside the self-test allowlist")


@dataclass(frozen=True)
class DestinationOutcome:
    account_id: str
    result: Literal["simulated"] = "simulated"

    def __post_init__(self) -> None:
        if self.account_id not in ALLOWED_DESTINATIONS:
            raise InvalidCommand("outcome account is outside the self-test allowlist")


@dataclass(frozen=True)
class WorkflowView:
    command_id: str
    stage: Stage
    outcomes: tuple[DestinationOutcome, ...]
    trace_id: str

    def __post_init__(self) -> None:
        if not self.command_id or not self.trace_id:
            raise InvalidCommand("workflow identity values must not be empty")
        if self.stage is Stage.COMPLETED and not self.outcomes:
            raise InvalidCommand("completed self-tests must have outcomes")
        if self.stage is not Stage.COMPLETED and self.outcomes:
            raise InvalidCommand("only completed self-tests may have outcomes")


@dataclass(frozen=True)
class WorkflowAcceptance:
    """The committed workflow and whether this transaction created it."""

    workflow: WorkflowView
    newly_accepted: bool


@dataclass(frozen=True)
class ParsedSelfTest:
    symbol: str
    action: Literal["buy"]
    quantity: Fraction
    unit_price: Decimal


@dataclass(frozen=True)
class ParseRejected:
    command_id: str
    reason: Literal["unsupported_self_test"] = "unsupported_self_test"


@dataclass(frozen=True)
class SelfTestAccepted:
    command_id: str
    trace_id: str


@dataclass(frozen=True)
class SelfTestParsed:
    command_id: str
    parsed: ParsedSelfTest


@dataclass(frozen=True)
class SelfTestCompleted:
    command_id: str
    outcomes: tuple[DestinationOutcome, ...]
