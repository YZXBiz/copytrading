"""Caller-owned diagnostics ports and workflow/store composition."""

from collections.abc import Callable
from dataclasses import dataclass
from typing import Literal, Protocol

from copytrading_engine.host.self_test.model import (
    DestinationOutcome,
    ParsedSelfTest,
    ParseRejected,
    Stage,
    SubmitSelfTest,
    WorkflowAcceptance,
    WorkflowView,
)
from copytrading_engine.host.self_test.ports import WorkflowStore
from copytrading_engine.host.status import (
    DiagnosticCaptureProjection,
    EngineQueries,
    EngineState,
    EngineStatus,
    TelemetryState,
)

type DiagnosticState = Literal["healthy", "degraded"]
type JsonScalar = bool | int | float | str | None
type JsonValue = JsonScalar | list[JsonValue] | dict[str, JsonValue]


@dataclass(frozen=True)
class DiagnosticHealth:
    state: DiagnosticState
    dropped_records: int
    last_error_code: str | None


@dataclass(frozen=True)
class DiagnosticCaptureHealth:
    """How many source and model payloads reached the journal, and how many were gaps."""

    source_events: int
    source_event_gaps: int
    model_requests: int
    model_request_gaps: int
    model_responses: int
    model_response_gaps: int


class DiagnosticSink(Protocol):
    """Caller-owned diagnostics interface used after durable workflow changes."""

    def record_stage(
        self,
        *,
        command_id: str,
        trace_id: str,
        stage: Stage,
        outcome: str,
        payload: JsonValue,
        previous_stage: Stage | None = None,
        anchor_exported: bool | None = None,
    ) -> None: ...

    def snapshot(self) -> DiagnosticHealth: ...

    def capture_health(self) -> DiagnosticCaptureHealth: ...

    def set_anchor_export_callback(self, callback: Callable[[str], None]) -> None: ...


class DiagnosticWorkflowStore:
    """Decorate committed workflow changes with best-effort diagnostic records."""

    def __init__(self, store: WorkflowStore, sink: DiagnosticSink) -> None:
        self._store = store
        self._sink = sink
        self._sink.set_anchor_export_callback(self._store.mark_trace_anchor_exported)

    async def accept_async(self, command: SubmitSelfTest) -> WorkflowAcceptance:
        acceptance = await self._store.accept_async(command)
        workflow = acceptance.workflow
        if acceptance.newly_accepted:
            self._record(
                workflow,
                stage=Stage.CAPTURED,
                outcome="accepted",
                anchor_exported=False,
                payload={
                    "request": {
                        "command_id": command.command_id,
                        "text": command.text,
                        "destination_ids": list(command.destination_ids),
                    },
                    "response": {
                        "command_id": workflow.command_id,
                        "stage": workflow.stage.value,
                    },
                },
            )
        return acceptance

    async def get_async(self, command_id: str) -> WorkflowView:
        return await self._store.get_async(command_id)

    async def pending_async(self, limit: int | None = None) -> tuple[str, ...]:
        return await self._store.pending_async(limit=limit)

    async def advance_async(
        self,
        command_id: str,
        expected: Stage,
        next_stage: Stage,
        outcomes: tuple[DestinationOutcome, ...],
        *,
        parsed: ParsedSelfTest | None = None,
        parse_rejection: ParseRejected | None = None,
    ) -> WorkflowView:
        try:
            workflow = await self._store.advance_async(
                command_id,
                expected,
                next_stage,
                outcomes,
                parsed=parsed,
                parse_rejection=parse_rejection,
            )
        except Exception as exc:
            await self._record_error(command_id, expected, exc)
            raise

        anchor_exported = await self._anchor_exported(workflow.command_id)

        payload: dict[str, JsonValue] = {
            "response": {
                "command_id": workflow.command_id,
                "stage": workflow.stage.value,
                "outcomes": [
                    {"account_id": outcome.account_id, "result": outcome.result}
                    for outcome in workflow.outcomes
                ],
            }
        }
        if parsed is not None:
            payload["parsed"] = {
                "symbol": parsed.symbol,
                "action": parsed.action,
                "quantity": str(parsed.quantity),
                "unit_price": str(parsed.unit_price),
            }
        if parse_rejection is not None:
            payload["error"] = {"code": parse_rejection.reason}
        self._record(
            workflow,
            stage=next_stage,
            outcome=next_stage.value,
            previous_stage=expected,
            anchor_exported=anchor_exported,
            payload=payload,
        )
        return workflow

    async def load_command_async(self, command_id: str) -> SubmitSelfTest:
        return await self._store.load_command_async(command_id)

    async def load_parsed_async(self, command_id: str) -> ParsedSelfTest:
        return await self._store.load_parsed_async(command_id)

    async def counts_async(self) -> tuple[int, int, int]:
        return await self._store.counts_async()

    async def trace_anchor_exported_async(self, command_id: str) -> bool:
        return await self._store.trace_anchor_exported_async(command_id)

    def mark_trace_anchor_exported(self, command_id: str) -> None:
        self._store.mark_trace_anchor_exported(command_id)

    def _record(
        self,
        workflow: WorkflowView,
        *,
        stage: Stage,
        outcome: str,
        payload: JsonValue,
        previous_stage: Stage | None = None,
        anchor_exported: bool | None = None,
    ) -> None:
        try:
            self._sink.record_stage(
                command_id=workflow.command_id,
                trace_id=workflow.trace_id,
                stage=stage,
                outcome=outcome,
                payload=payload,
                previous_stage=previous_stage,
                anchor_exported=anchor_exported,
            )
        except Exception:  # noqa: BLE001 - diagnostics must not alter the operational result
            # Diagnostics are a best-effort side effect after the store commit.
            pass

    async def _record_error(self, command_id: str, stage: Stage, error: Exception) -> None:
        try:
            workflow = await self._store.get_async(command_id)
        except Exception:  # noqa: BLE001 - diagnostics must not alter the operational result
            return
        anchor_exported = await self._anchor_exported(command_id)
        self._record(
            workflow,
            stage=stage,
            outcome="error",
            previous_stage=stage,
            anchor_exported=anchor_exported,
            payload={"error": {"code": _error_code(error)}},
        )

    async def _anchor_exported(self, command_id: str) -> bool | None:
        try:
            return await self._store.trace_anchor_exported_async(command_id)
        except Exception:  # noqa: BLE001 - diagnostics must not alter the operational result
            return None


class DiagnosticEngineQueries(EngineQueries):
    """Expose journal health without letting a diagnostics failure break status."""

    def __init__(self, store: WorkflowStore, instance_id: str, sink: DiagnosticSink) -> None:
        super().__init__(store, instance_id)
        self._sink = sink

    async def status(
        self,
        state: EngineState,
        *,
        telemetry_state: TelemetryState = "degraded",
        telemetry_dropped: int = 0,
        telemetry_error_code: str | None = None,
        diagnostic_capture: DiagnosticCaptureProjection | None = None,
    ) -> EngineStatus:
        try:
            health = self._sink.snapshot()
        except Exception:  # noqa: BLE001 - diagnostics must not alter the operational result
            health = DiagnosticHealth(
                telemetry_state,
                telemetry_dropped,
                telemetry_error_code or "health_unavailable",
            )
        capture = diagnostic_capture or DiagnosticCaptureProjection()
        try:
            observed = self._sink.capture_health()
            capture = DiagnosticCaptureProjection(
                source_events=observed.source_events,
                source_event_gaps=observed.source_event_gaps,
                model_requests=observed.model_requests,
                model_request_gaps=observed.model_request_gaps,
                model_responses=observed.model_responses,
                model_response_gaps=observed.model_response_gaps,
            )
        except Exception:  # noqa: BLE001 - diagnostics must not alter the operational result
            health = DiagnosticHealth("degraded", health.dropped_records, "health_unavailable")
        return await super().status(
            state,
            telemetry_state=health.state,
            telemetry_dropped=health.dropped_records,
            telemetry_error_code=health.last_error_code,
            diagnostic_capture=capture,
        )


def _error_code(error: Exception) -> str:
    name = type(error).__name__
    return {
        "StoreUnavailable": "store_unavailable",
        "IdentityConflict": "identity_conflict",
        "InvalidTransition": "invalid_transition",
        "WorkflowNotFound": "not_found",
    }.get(name, "stage_transition_failed")
