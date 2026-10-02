"""Private observations for explicitly activated trading work, recorded in the local journal."""

from collections.abc import Iterable, Iterator
from contextlib import AbstractContextManager, contextmanager
from hashlib import sha256

from copytrading_engine.diagnostics.redaction import MAX_DIAGNOSTIC_PAYLOAD_BYTES, JsonValue
from copytrading_engine.diagnostics.telemetry.events import safe_ledger_event
from copytrading_engine.diagnostics.telemetry.local import LocalTelemetry
from copytrading_engine.shared.correlation import WorkflowAttempt, current_workflow_attempt
from copytrading_engine.shared.payload_capture import CaptureKind, CaptureStatus, ProviderName


class TradingTelemetry:
    """Record finite operation outcomes without credentials, message text, or prompts."""

    def __init__(self, *, sink: LocalTelemetry | None = None) -> None:
        self._sink = sink

    @contextmanager
    def _scope(
        self,
        operation: str,
        *,
        signal_ref: str | None = None,
        ledger_event: str | None = None,
        correlation: WorkflowAttempt | None = None,
    ) -> Iterator[None]:
        outcome = "returned"
        try:
            yield
        except BaseException:
            outcome = "raised"
            raise
        finally:
            self._record(operation, outcome, signal_ref, ledger_event, correlation)

    def span(self, name: str, message_id: str) -> AbstractContextManager[None]:
        operation = (
            name if name in {"risk_checks", "order_submission", "quote_snapshot"} else "unknown"
        )
        return self._scope(
            f"execution.{operation}",
            signal_ref=signal_reference(message_id),
            correlation=current_workflow_attempt(),
        )

    def workflow_span(self, correlation: WorkflowAttempt) -> AbstractContextManager[None]:
        return self._scope("workflow", correlation=correlation)

    def model_span(self, message_id: str) -> AbstractContextManager[None]:
        return self._scope(
            "model.parse",
            signal_ref=signal_reference(message_id),
            correlation=current_workflow_attempt(),
        )

    def destination_span(
        self, message_id: str, correlation: WorkflowAttempt
    ) -> AbstractContextManager[None]:
        return self._scope(
            "destination.receive",
            signal_ref=signal_reference(message_id),
            correlation=correlation,
        )

    def source_span(self) -> AbstractContextManager[None]:
        return self._scope("source.forward")

    def event(self, name: str) -> None:
        ledger_event = safe_ledger_event(name)
        with self._scope(
            "execution.ledger_event",
            ledger_event=ledger_event,
            correlation=current_workflow_attempt(),
        ):
            pass

    def _record(
        self,
        operation: str,
        outcome: str,
        signal_ref: str | None,
        ledger_event: str | None,
        correlation: WorkflowAttempt | None,
    ) -> None:
        if self._sink is None:
            return
        try:
            self._sink.record_trading_operation(
                operation=operation,
                outcome="observed" if ledger_event is not None else outcome,
                trace_id=correlation.trace_id.replace("-", "") if correlation else None,
                signal_ref=signal_ref,
                ledger_event=ledger_event,
                workflow_id=correlation.workflow_id if correlation else None,
                destination_id=correlation.destination_id if correlation else None,
                attempt=correlation.attempt if correlation else None,
            )
        except Exception:  # noqa: BLE001 - observer failure must not reach trading
            self._report_observer_failure()

    def _report_observer_failure(self) -> None:
        if self._sink is not None:
            try:
                self._sink.report_trading_observer_failure()
            except Exception:  # noqa: BLE001 - observer failure must not reach trading
                pass

    @property
    def diagnostic_sink(self) -> LocalTelemetry | None:
        """Expose the capture port for provider/source adapters without coupling them here."""
        return self._sink

    def register_secrets(self, values: Iterable[str]) -> bool:
        """Register runtime credentials before source or provider work can emit diagnostics."""
        if self._sink is None:
            return True
        return self._sink.register_secrets(values)

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
        if self._sink is None:
            return
        try:
            self._sink.record_payload(
                capture_kind=capture_kind,
                workflow_id=workflow_id,
                trace_id=trace_id,
                destination_id=destination_id,
                attempt=attempt,
                provider=provider,
                payload=payload,
                source_bytes=source_bytes,
                max_bytes=max_bytes,
                status=status,
            )
        except Exception:  # noqa: BLE001 - observer failure must not reach trading
            self._report_observer_failure()


def signal_reference(message_id: str) -> str:
    return sha256(message_id.encode("utf-8", errors="replace")).hexdigest()[:32]
