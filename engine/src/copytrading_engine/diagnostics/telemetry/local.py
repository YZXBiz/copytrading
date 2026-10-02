"""The diagnostics sink: redacted stage, payload, and trading records in a local journal."""

import json
import queue
import re
import threading
import time
from collections.abc import Callable, Iterable
from dataclasses import asdict, dataclass
from datetime import UTC, datetime

from copytrading_engine.diagnostics.capture import (
    DiagnosticCaptureHealth,
    DiagnosticHealth,
    DiagnosticState,
)
from copytrading_engine.diagnostics.redaction import (
    MAX_DIAGNOSTIC_PAYLOAD_BYTES,
    JsonValue,
    admit_diagnostic_payload,
)
from copytrading_engine.diagnostics.telemetry.attributes import (
    bounded_label,
    bounded_opaque_id,
    capture_counter_keys,
    stages,
    validated_hex_id,
)
from copytrading_engine.diagnostics.telemetry.config import TelemetryConfig
from copytrading_engine.diagnostics.telemetry.events import (
    DiagnosticEvent,
    DiagnosticPayloadEvent,
    TradingDiagnosticEvent,
    safe_ledger_event,
)
from copytrading_engine.diagnostics.telemetry.journal import journal_logger, prune_journal
from copytrading_engine.host.self_test.model import Stage
from copytrading_engine.shared.model_providers import MODEL_PROVIDERS
from copytrading_engine.shared.payload_capture import CaptureKind, CaptureStatus, ProviderName

_MAX_KNOWN_SECRETS = 256
_MAX_KNOWN_SECRET_BYTES = 4096
_PRUNE_INTERVAL_SECONDS = 3_600.0

_TRADING_OPERATIONS = frozenset(
    {
        "source.forward",
        "workflow",
        "model.parse",
        "destination.receive",
        "execution.risk_checks",
        "execution.order_submission",
        "execution.quote_snapshot",
        "execution.ledger_event",
    }
)
_TRADING_OUTCOMES = frozenset({"returned", "raised", "observed"})

type JournalEvent = DiagnosticEvent | TradingDiagnosticEvent | DiagnosticPayloadEvent


@dataclass(slots=True)
class _FlushBarrier:
    completed: threading.Event
    successful: bool = False


def journal_line(event: JournalEvent) -> str:
    """One self-describing JSON line: its kind, an ISO time, then the event's own fields."""
    kind = (
        "stage"
        if isinstance(event, DiagnosticEvent)
        else "payload"
        if isinstance(event, DiagnosticPayloadEvent)
        else "trading"
    )
    at = datetime.fromtimestamp(event.created_at_ns / 1e9, UTC).isoformat(timespec="milliseconds")
    return json.dumps(
        {"kind": kind, "at": at, **asdict(event)}, ensure_ascii=False, separators=(",", ":")
    )


class LocalTelemetry:
    """Best-effort diagnostics queue independent from workflow transactions."""

    def __init__(self, config: TelemetryConfig) -> None:
        self._config = config
        self._queue: queue.Queue[JournalEvent | _FlushBarrier] = queue.Queue(
            maxsize=config.queue_capacity
        )
        self._lock = threading.Lock()
        self._secrets_lock = threading.Lock()
        self._known_secrets: set[str] = set()
        self._secret_registry_overflow = False
        self._stop_requested = threading.Event()
        self._state: DiagnosticState = "healthy"
        self._dropped_records = 0
        self._last_error_code: str | None = None
        self._anchor_callback: Callable[[str], None] | None = None
        self._capture_counts = {
            "source_events": 0,
            "source_event_gaps": 0,
            "model_requests": 0,
            "model_request_gaps": 0,
            "model_responses": 0,
            "model_response_gaps": 0,
        }
        self._closed = False
        self._logger, error = journal_logger(
            config.journal_directory,
            retention_age_days=config.retention_age_days,
            max_bytes=config.max_bytes,
            on_error=lambda: self._record_failure(1, "journal_write_failed"),
        )
        if error is not None:
            self._state = "degraded"
            self._last_error_code = "journal_unavailable"
        self._worker = threading.Thread(target=self._run, name="diagnostics-journal", daemon=True)
        self._worker.start()

    def register_secrets(self, values: Iterable[str]) -> bool:
        """Add credentials to this process' bounded redaction set.

        Registrations are additive for the sink lifetime so credentials from old
        activations remain protected while their callbacks may still be running.
        If the registry bound is exceeded, payload capture switches to gap-only
        records rather than journaling data with an incomplete redaction set.
        """
        candidate: set[str] = set()
        for value in values:
            if not isinstance(value, str):
                raise TypeError("diagnostic redaction values must be strings")
            if not value:
                continue
            if len(value.encode("utf-8")) > _MAX_KNOWN_SECRET_BYTES:
                with self._secrets_lock:
                    self._secret_registry_overflow = True
                return False
            candidate.add(value)
            if len(candidate) > _MAX_KNOWN_SECRETS:
                with self._secrets_lock:
                    self._secret_registry_overflow = True
                return False
        with self._secrets_lock:
            if self._secret_registry_overflow:
                return False
            if len(self._known_secrets | candidate) > _MAX_KNOWN_SECRETS:
                self._secret_registry_overflow = True
                return False
            self._known_secrets.update(candidate)
            return True

    def _redaction_snapshot(self) -> tuple[tuple[str, ...], bool]:
        with self._secrets_lock:
            return tuple(self._known_secrets), self._secret_registry_overflow

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
    ) -> None:
        """Redact and enqueue a committed stage without blocking its caller."""
        known_secrets, registry_overflow = self._redaction_snapshot()
        admission = (
            admit_diagnostic_payload(
                payload, secrets=known_secrets, max_bytes=MAX_DIAGNOSTIC_PAYLOAD_BYTES
            )
            if not registry_overflow
            else None
        )
        self._enqueue(
            DiagnosticEvent(
                command_id=bounded_opaque_id(command_id, 128),
                trace_id=bounded_opaque_id(trace_id, 128),
                stage=bounded_label(stage.value, stages()),
                outcome=bounded_label(
                    outcome, ("accepted", "parsed", "completed", "failed", "error")
                ),
                payload=admission.payload if admission is not None else None,
                previous_stage=previous_stage.value if previous_stage else None,
                created_at_ns=time.time_ns(),
                anchor_exported=anchor_exported,
                capture_status=(
                    "incomplete"
                    if admission is None
                    else "oversize"
                    if admission.status == "oversize"
                    else "complete"
                ),
                payload_bytes=admission.original_bytes if admission is not None else 0,
                redacted_fields=admission.redacted_fields if admission is not None else 0,
            )
        )

    def record_payload(
        self,
        *,
        capture_kind: CaptureKind,
        workflow_id: str | None,
        trace_id: str | None,
        destination_id: str | None,
        attempt: int | None,
        provider: ProviderName,
        payload: JsonValue | None,
        source_bytes: int | None = None,
        max_bytes: int = MAX_DIAGNOSTIC_PAYLOAD_BYTES,
        status: CaptureStatus = "complete",
    ) -> None:
        """Admit a redacted, bounded copy of one source/provider wire payload."""
        kind = (
            capture_kind
            if capture_kind in {"source_event", "model_request", "model_response"}
            else "other"
        )
        safe_provider = provider if provider in MODEL_PROVIDERS else "other"
        known_secrets, registry_overflow = self._redaction_snapshot()
        admission = (
            admit_diagnostic_payload(
                payload, secrets=known_secrets, max_bytes=max_bytes, source_bytes=source_bytes
            )
            if not registry_overflow
            else None
        )
        safe_status: CaptureStatus
        if registry_overflow:
            safe_status = "incomplete"
        elif status in {"incomplete", "missing", "oversize"}:
            safe_status = status
        elif admission is None:
            safe_status = "missing"
        elif admission.status != "complete":
            safe_status = admission.status
        else:
            safe_status = "complete"
        event = DiagnosticPayloadEvent(
            capture_kind=kind,
            capture_status=safe_status,
            workflow_id=validated_hex_id(workflow_id, 32),
            trace_id=validated_hex_id(trace_id, 32),
            destination_id=validated_hex_id(destination_id, 32),
            attempt=attempt if type(attempt) is int and attempt > 0 else None,
            provider=safe_provider,
            payload=(
                admission.payload if admission is not None and safe_status == "complete" else None
            ),
            payload_bytes=admission.original_bytes
            if admission is not None
            else (source_bytes or 0),
            redacted_fields=admission.redacted_fields if admission is not None else 0,
            created_at_ns=time.time_ns(),
        )
        count_key, gap_key = capture_counter_keys(kind)
        with self._lock:
            if safe_status == "complete" and count_key is not None:
                self._capture_counts[count_key] += 1
            elif gap_key is not None:
                self._capture_counts[gap_key] += 1
        if not self._enqueue(event) and gap_key is not None:
            with self._lock:
                if safe_status == "complete" and count_key is not None:
                    self._capture_counts[count_key] -= 1
                    self._capture_counts[gap_key] += 1

    def record_trading_operation(
        self,
        *,
        operation: str,
        outcome: str,
        trace_id: str | None = None,
        signal_ref: str | None = None,
        ledger_event: str | None = None,
        workflow_id: str | None = None,
        destination_id: str | None = None,
        attempt: int | None = None,
    ) -> None:
        """Queue only finite labels and opaque correlation, never source/model text."""
        self._enqueue(
            TradingDiagnosticEvent(
                operation=operation if operation in _TRADING_OPERATIONS else "other",
                outcome=outcome if outcome in _TRADING_OUTCOMES else "other",
                trace_id=validated_hex_id(trace_id, 32),
                signal_ref=signal_ref
                if signal_ref and re.fullmatch(r"[0-9a-f]{32}", signal_ref)
                else None,
                ledger_event=safe_ledger_event(ledger_event) if ledger_event is not None else None,
                created_at_ns=time.time_ns(),
                workflow_id=validated_hex_id(workflow_id, 32),
                destination_id=validated_hex_id(destination_id, 32),
                attempt=attempt if type(attempt) is int and attempt > 0 else None,
            )
        )

    def capture_health(self) -> DiagnosticCaptureHealth:
        """Snapshot capture completeness separately from journal health."""
        with self._lock:
            return DiagnosticCaptureHealth(**self._capture_counts)

    def snapshot(self) -> DiagnosticHealth:
        with self._lock:
            return DiagnosticHealth(
                state=self._state,
                dropped_records=self._dropped_records,
                last_error_code=self._last_error_code,
            )

    def report_trading_observer_failure(self) -> None:
        self._record_failure(1, "trading_observer_failed")

    def set_anchor_export_callback(self, callback: Callable[[str], None]) -> None:
        """Receive each self-test command id once its captured stage is in the journal."""
        self._anchor_callback = callback

    def flush(self, *, timeout_seconds: float = 5.0) -> bool:
        """Wait until all events accepted before the barrier have been journaled."""
        if timeout_seconds <= 0:
            return False
        with self._lock:
            if self._closed:
                return False
        barrier = _FlushBarrier(threading.Event())
        deadline = time.monotonic() + timeout_seconds
        try:
            self._queue.put(barrier, timeout=timeout_seconds)
        except queue.Full:
            return False
        completed = barrier.completed.wait(max(0.0, deadline - time.monotonic()))
        return completed and barrier.successful

    def close(self, timeout_seconds: float) -> None:
        """Drain and stop the journal writer within the caller's shutdown budget."""
        if timeout_seconds <= 0:
            raise ValueError("telemetry shutdown timeout must be positive")
        deadline = time.monotonic() + timeout_seconds
        with self._lock:
            if self._closed:
                return
            self._closed = True
            self._stop_requested.set()
        self._worker.join(max(0.0, deadline - time.monotonic()))
        if self._worker.is_alive():
            self._discard_queued_on_shutdown()

    def _enqueue(self, event: JournalEvent) -> bool:
        with self._lock:
            if self._closed:
                self._dropped_records += 1
                self._last_error_code = "sink_closed"
                self._state = "degraded"
                return False
            try:
                self._queue.put_nowait(event)
            except queue.Full:
                self._dropped_records += 1
                self._last_error_code = "queue_full"
                self._state = "degraded"
                return False
            return True

    def _run(self) -> None:
        next_prune = time.monotonic() + _PRUNE_INTERVAL_SECONDS
        try:
            while True:
                if time.monotonic() >= next_prune:
                    next_prune = time.monotonic() + _PRUNE_INTERVAL_SECONDS
                    self._prune()
                try:
                    item = self._queue.get(timeout=0.01)
                except queue.Empty:
                    if self._stop_requested.is_set():
                        return
                    continue
                if isinstance(item, _FlushBarrier):
                    item.successful = True
                    item.completed.set()
                    self._queue.task_done()
                    continue
                written = self._write(item)
                if (
                    written
                    and self._anchor_callback is not None
                    and isinstance(item, DiagnosticEvent)
                    and item.stage == Stage.CAPTURED.value
                    and item.anchor_exported is False
                ):
                    try:
                        self._anchor_callback(item.command_id)
                    except Exception:  # noqa: BLE001 - telemetry failure must not reach operational code
                        self._record_failure(0, "journal_receipt_failed")
                self._queue.task_done()
        finally:
            self._close_journal()

    def _write(self, event: JournalEvent) -> bool:
        if self._logger is None:
            self._record_failure(1, "journal_unavailable")
            return False
        try:
            self._logger.info(journal_line(event))
        except OSError, TypeError, ValueError:
            self._record_failure(1, "journal_write_failed")
            return False
        return True

    def _prune(self) -> None:
        """Expire whole days of journal while the engine keeps running for weeks."""
        try:
            prune_journal(
                self._config.journal_directory,
                retention_age_days=self._config.retention_age_days,
            )
        except OSError:
            self._record_failure(0, "journal_prune_failed")

    def _discard_queued_on_shutdown(self) -> None:
        dropped = 0
        while True:
            try:
                item = self._queue.get_nowait()
            except queue.Empty:
                break
            if isinstance(item, _FlushBarrier):
                item.completed.set()
            else:
                dropped += 1
            self._queue.task_done()
        self._record_failure(dropped, "shutdown_timeout")

    def _close_journal(self) -> None:
        if self._logger is None:
            return
        for handler in self._logger.handlers[:]:
            try:
                handler.flush()
                handler.close()
            except Exception:  # noqa: BLE001 - telemetry failure must not reach operational code
                pass
            self._logger.removeHandler(handler)

    def _record_failure(self, count: int, code: str) -> None:
        with self._lock:
            self._dropped_records += count
            self._state = "degraded"
            self._last_error_code = code
