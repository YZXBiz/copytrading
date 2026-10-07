"""Validated parser inputs and typed records crossing storage boundaries."""

from dataclasses import dataclass
from datetime import date, datetime
from typing import Protocol

from copytrading_engine.parsing.diagnostics import ValidationIssue
from copytrading_engine.parsing.history import PastCall
from copytrading_engine.shared.raw_message import RawMessage
from copytrading_engine.shared.signals import StockSignal


@dataclass(frozen=True, slots=True)
class ExtractionJob:
    key: str
    raw: RawMessage
    attempts: int
    workflow_id: str
    trace_id: str


@dataclass(frozen=True, slots=True)
class DestinationIdentity:
    message_id: str
    account_id: str
    destination_id: str
    configuration_revision: str
    workflow_id: str
    trace_id: str
    attempt: int = 0


@dataclass(frozen=True, slots=True)
class DestinationRegistration:
    account_id: str
    configuration_revision: str


@dataclass(frozen=True, slots=True)
class RequestReservation:
    key: str
    expected_attempts: int
    day: date
    daily_limit: int
    retry_at: datetime


@dataclass(frozen=True, slots=True)
class PendingSignal:
    key: str
    signal: StockSignal
    seq: int


class ExtractionStore(Protocol):
    async def next(self, now: datetime) -> ExtractionJob | None: ...
    async def reserve(self, request: RequestReservation) -> bool: ...
    async def finish(self, key: str, result: StockSignal) -> None: ...
    async def past_calls(self, channel_id: str, before: str) -> tuple[PastCall, ...]: ...
    async def diagnose(
        self,
        key: str,
        attempt: int,
        at: datetime,
        reason: str,
        issues: tuple[ValidationIssue, ...],
    ) -> None: ...
