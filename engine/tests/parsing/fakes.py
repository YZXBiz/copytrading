"""Test doubles for parser workflows; the store has no durability model."""

import datetime as dt
import hashlib
from dataclasses import dataclass

from copytrading_engine.parsing.contracts import (
    ExtractionJob,
    PendingSignal,
    RawMessage,
    RequestReservation,
)
from copytrading_engine.parsing.diagnostics import ValidationIssue
from copytrading_engine.parsing.history import PastCall
from copytrading_engine.shared.signals import SourceIdentityConflict, StockSignal


@dataclass(frozen=True, slots=True)
class DiagnosticRecord:
    key: str
    attempt: int
    at: dt.datetime
    reason: str
    issues: tuple[ValidationIssue, ...]


class InMemoryExtractionStore:
    """Keep typed parser inputs and outputs for deterministic workflow assertions."""

    def __init__(self) -> None:
        self._messages: dict[str, RawMessage] = {}
        self._order: list[str] = []
        self._attempts: dict[str, int] = {}
        self._retry_at: dict[str, dt.datetime] = {}
        self._results: dict[str, StockSignal] = {}
        self._requests_by_day: dict[dt.date, int] = {}
        self._reservations: list[RequestReservation] = []
        self._diagnostics: list[DiagnosticRecord] = []

    @staticmethod
    def key_for(message: RawMessage) -> str:
        return f"{message.source}:{message.channel_id}:{message.id}"

    async def past_calls(self, channel_id: str, before: str) -> tuple[PastCall, ...]:
        """The calls this channel's traded posts made before `before`, as the SQLite store
        reads them (owner corrections aside)."""
        earlier = self._order[: self._order.index(before)] if before in self._order else []
        return tuple(
            PastCall(source_key=key, index=index, at=result.timestamp, instruction=instruction)
            for key in earlier
            if self._messages[key].channel_id == channel_id
            and (result := self._results.get(key)) is not None
            and result.decision == "trade"
            for index, instruction in enumerate(result.instructions)
        )

    @property
    def inputs(self) -> tuple[RawMessage, ...]:
        return tuple(self._messages[key] for key in self._order)

    @property
    def reservations(self) -> tuple[RequestReservation, ...]:
        return tuple(self._reservations)

    @property
    def diagnostics(self) -> tuple[DiagnosticRecord, ...]:
        return tuple(self._diagnostics)

    def add(self, event: RawMessage) -> None:
        key = self.key_for(event)
        existing = self._messages.get(key)
        if existing is not None and existing != event:
            raise SourceIdentityConflict("Source ID reused with a different payload")
        if existing is None:
            self._messages[key] = event
            self._order.append(key)

    async def next(self, now: dt.datetime) -> ExtractionJob | None:
        for index, key in enumerate(self._order):
            if key in self._results:
                continue
            message = self._messages[key]
            has_pending_predecessor = any(
                prior not in self._results
                and self._messages[prior].source == message.source
                and self._messages[prior].channel_id == message.channel_id
                for prior in self._order[:index]
            )
            if has_pending_predecessor or self._retry_at.get(key, now) > now:
                continue
            workflow_id = hashlib.sha256(f"workflow:{key}".encode()).hexdigest()[:32]
            trace_id = hashlib.sha256(f"trace:{key}".encode()).hexdigest()[:32]
            return ExtractionJob(key, message, self._attempts.get(key, 0), workflow_id, trace_id)
        return None

    async def reserve(self, request: RequestReservation) -> bool:
        attempts = self._attempts.get(request.key)
        if attempts is None and request.key not in self._messages:
            raise ValueError("Cannot reserve an unknown source message")
        attempts = attempts or 0
        if attempts != request.expected_attempts:
            raise ValueError("Cannot reserve with stale extraction attempts")
        count = self._requests_by_day.get(request.day, 0)
        if count >= request.daily_limit:
            return False
        self._requests_by_day[request.day] = count + 1
        self._attempts[request.key] = attempts + 1
        self._retry_at[request.key] = request.retry_at
        self._reservations.append(request)
        return True

    async def finish(self, key: str, result: StockSignal) -> None:
        self._results.setdefault(key, result)

    async def diagnose(
        self,
        key: str,
        attempt: int,
        at: dt.datetime,
        reason: str,
        issues: tuple[ValidationIssue, ...],
    ) -> None:
        record = DiagnosticRecord(key, attempt, at, reason, issues)
        if record not in self._diagnostics:
            self._diagnostics.append(record)

    def pending(self) -> tuple[PendingSignal, ...]:
        return tuple(
            PendingSignal(key, self._results[key], index)
            for index, key in enumerate(self._order, 1)
            if key in self._results
        )

    def result_for(self, key: str) -> StockSignal | None:
        return self._results.get(key)


class FakeDecoder:
    def __init__(self, result):
        self.result = result
        self.calls = 0

    async def decode(self, text, route, recent=()):
        self.calls += 1
        return self.result
