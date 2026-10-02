"""The diagnostic events the engine records in its local journal."""

from dataclasses import dataclass

from copytrading_engine.diagnostics.redaction import JsonValue
from copytrading_engine.shared.payload_capture import CaptureKind, CaptureStatus, ProviderName


@dataclass(frozen=True)
class DiagnosticEvent:
    command_id: str
    trace_id: str
    stage: str
    outcome: str
    payload: JsonValue | None
    previous_stage: str | None
    created_at_ns: int
    anchor_exported: bool | None = None
    capture_status: CaptureStatus = "complete"
    payload_bytes: int = 0
    redacted_fields: int = 0


@dataclass(frozen=True)
class DiagnosticPayloadEvent:
    capture_kind: CaptureKind
    capture_status: CaptureStatus
    workflow_id: str | None
    trace_id: str | None
    destination_id: str | None
    attempt: int | None
    provider: ProviderName
    payload: JsonValue | None
    payload_bytes: int
    redacted_fields: int
    created_at_ns: int


_LEDGER_EVENTS = frozenset(
    {
        "account_bound",
        "signal_rejected",
        "message",
        "skipped",
        "message_done",
        "order_prepared",
        "submit_started",
        "submission_aborted",
        "submission_uncertain",
        "broker_acknowledged",
        "cancel_requested",
        "quote_unavailable",
        "submit_error",
        "submission_quote",
        "manual_sale_recorded",
        "order_intent_released",
        "late_order_incident_cleared",
        "order_update",
        "late_order_incident_opened",
        "late_order_incident_reopened",
    }
)


def safe_ledger_event(name: str) -> str:
    return name if name in _LEDGER_EVENTS else "other"


@dataclass(frozen=True)
class TradingDiagnosticEvent:
    operation: str
    outcome: str
    trace_id: str | None
    signal_ref: str | None
    ledger_event: str | None
    created_at_ns: int
    workflow_id: str | None = None
    destination_id: str | None = None
    attempt: int | None = None
