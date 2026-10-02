"""Caller-owned interfaces for persistence and deterministic parsing."""

from typing import Protocol

from copytrading_engine.host.self_test.model import (
    DestinationOutcome,
    ParsedSelfTest,
    ParseRejected,
    Stage,
    SubmitSelfTest,
    WorkflowAcceptance,
    WorkflowView,
)


class WorkflowStore(Protocol):
    """Operations the workflow service needs from durable storage."""

    async def accept_async(self, command: SubmitSelfTest) -> WorkflowAcceptance: ...

    async def get_async(self, command_id: str) -> WorkflowView: ...

    async def pending_async(self, limit: int | None = None) -> tuple[str, ...]: ...

    async def advance_async(
        self,
        command_id: str,
        expected: Stage,
        next_stage: Stage,
        outcomes: tuple[DestinationOutcome, ...],
        *,
        parsed: ParsedSelfTest | None = None,
        parse_rejection: ParseRejected | None = None,
    ) -> WorkflowView: ...

    async def load_command_async(self, command_id: str) -> SubmitSelfTest: ...

    async def load_parsed_async(self, command_id: str) -> ParsedSelfTest: ...

    async def counts_async(self) -> tuple[int, int, int]: ...

    async def trace_anchor_exported_async(self, command_id: str) -> bool: ...

    def mark_trace_anchor_exported(self, command_id: str) -> None: ...


class SelfTestParser(Protocol):
    """A deterministic parser that returns immutable evidence or a domain error."""

    def parse(self, text: str) -> ParsedSelfTest: ...
