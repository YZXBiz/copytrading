"""Typed status and workflow queries exposed by the engine boundary."""

from dataclasses import dataclass
from typing import Literal

from copytrading_engine.host.self_test.model import WorkflowView
from copytrading_engine.host.self_test.ports import WorkflowStore

EngineState = Literal["starting", "running", "stopping", "failed"]
TelemetryState = Literal["healthy", "degraded"]


@dataclass(frozen=True)
class DiagnosticCaptureProjection:
    source_events: int = 0
    source_event_gaps: int = 0
    model_requests: int = 0
    model_request_gaps: int = 0
    model_responses: int = 0
    model_response_gaps: int = 0


@dataclass(frozen=True)
class EngineStatus:
    instance_id: str
    state: EngineState
    accepted: int
    pending: int
    completed: int
    telemetry_state: TelemetryState
    telemetry_dropped: int
    telemetry_error_code: str | None = None
    diagnostic_capture: DiagnosticCaptureProjection = DiagnosticCaptureProjection()


class EngineQueries:
    """Read status and workflow views without exposing adapter details."""

    def __init__(self, store: WorkflowStore, instance_id: str) -> None:
        self._store = store
        self._instance_id = instance_id

    async def status(
        self,
        state: EngineState,
        *,
        telemetry_state: TelemetryState = "degraded",
        telemetry_dropped: int = 0,
        telemetry_error_code: str | None = None,
        diagnostic_capture: DiagnosticCaptureProjection | None = None,
    ) -> EngineStatus:
        accepted, pending, completed = await self._store.counts_async()
        return EngineStatus(
            instance_id=self._instance_id,
            state=state,
            accepted=accepted,
            pending=pending,
            completed=completed,
            telemetry_state=telemetry_state,
            telemetry_dropped=telemetry_dropped,
            telemetry_error_code=telemetry_error_code,
            diagnostic_capture=diagnostic_capture or DiagnosticCaptureProjection(),
        )

    async def workflow(self, command_id: str) -> WorkflowView:
        return await self._store.get_async(command_id)
