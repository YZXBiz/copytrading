"""Trading observations reach the journal as finite labels and never change trading results."""

import json
import threading
from pathlib import Path

import pytest

from copytrading_engine.diagnostics.telemetry.config import TelemetryConfig
from copytrading_engine.diagnostics.telemetry.local import LocalTelemetry
from copytrading_engine.shared.correlation import WorkflowAttempt, bind_workflow_attempt
from copytrading_engine.trading.adapters.telemetry import TradingTelemetry, signal_reference


def _records(directory: Path) -> list[dict[str, object]]:
    return [
        json.loads(line)
        for path in sorted(directory.glob("diagnostics.jsonl*"))
        for line in path.read_text(encoding="utf-8").splitlines()
    ]


def test_trading_observations_are_finite_private_and_do_not_claim_parser_success(
    tmp_path: Path,
) -> None:
    directory = tmp_path / "diagnostics"
    sink = LocalTelemetry(TelemetryConfig(journal_directory=directory))
    observer = TradingTelemetry(sink=sink)
    raw_id = "sensitive-message-identifier"
    try:
        with observer.model_span(raw_id):
            pass  # A decoder may return a retry result without raising.
        with pytest.raises(RuntimeError, match="decision remains unchanged"):
            with observer.span("risk_checks", raw_id):
                raise RuntimeError("decision remains unchanged")
        observer.event("order_prepared")
        observer.event("arbitrary secret event label")
        assert sink.flush(timeout_seconds=5)
    finally:
        sink.close(timeout_seconds=5)

    records = _records(directory)
    assert [(item["operation"], item["outcome"]) for item in records] == [
        ("model.parse", "returned"),
        ("execution.risk_checks", "raised"),
        ("execution.ledger_event", "observed"),
        ("execution.ledger_event", "observed"),
    ]
    assert records[0]["signal_ref"] == signal_reference(raw_id)
    assert records[2]["ledger_event"] == "order_prepared"
    assert records[3]["ledger_event"] == "other"
    encoded = json.dumps(records)
    assert raw_id not in encoded
    assert "arbitrary secret event label" not in encoded
    assert "decision remains unchanged" not in encoded


def test_observations_carry_the_bound_workflow_attempt(tmp_path: Path) -> None:
    directory = tmp_path / "diagnostics"
    sink = LocalTelemetry(TelemetryConfig(journal_directory=directory))
    observer = TradingTelemetry(sink=sink)
    attempt = WorkflowAttempt(
        workflow_id="9b1f0c2a4d5e4f6a8b7c6d5e4f3a2b1c",
        trace_id="4f0f5f8d-9b0f-4c2e-8b3a-7c6d5e4f3210",
        destination_id="e86aa73e66f543799968ef089b13b664",
        attempt=3,
    )
    try:
        with bind_workflow_attempt(attempt):
            with observer.span("order_submission", "message-1"):
                pass
        with observer.destination_span("message-1", attempt):
            pass
        assert sink.flush(timeout_seconds=5)
    finally:
        sink.close(timeout_seconds=5)

    for record in _records(directory):
        assert record["workflow_id"] == attempt.workflow_id
        assert record["trace_id"] == "4f0f5f8d9b0f4c2e8b3a7c6d5e4f3210"
        assert record["destination_id"] == attempt.destination_id
        assert record["attempt"] == 3


def test_trading_queue_pressure_degrades_health_without_changing_domain_result(
    tmp_path: Path,
) -> None:
    sink = LocalTelemetry(
        TelemetryConfig(journal_directory=tmp_path / "diagnostics", queue_capacity=1)
    )
    entered = threading.Event()
    release = threading.Event()
    write = sink._write

    def blocking_write(item: object) -> bool:
        entered.set()
        assert release.wait(timeout=5)
        return write(item)

    sink._write = blocking_write
    observer = TradingTelemetry(sink=sink)
    try:
        with observer.source_span():
            result = 42
        assert entered.wait(timeout=3)
        with observer.model_span("one"):
            pass
        with observer.model_span("two"):
            pass
        assert result == 42
        health = sink.snapshot()
        assert health.state == "degraded"
        assert health.last_error_code == "queue_full"
        assert health.dropped_records >= 1
    finally:
        release.set()
        sink.close(timeout_seconds=5)


def test_observer_failure_does_not_change_domain_result_or_error(tmp_path: Path) -> None:
    sink = LocalTelemetry(TelemetryConfig(journal_directory=tmp_path / "diagnostics"))
    observer = TradingTelemetry(sink=sink)

    def broken_record(**kwargs: object) -> None:
        raise RuntimeError("observer failed")

    sink.record_trading_operation = broken_record
    try:
        with observer.source_span():
            result = 42
        assert result == 42
        with pytest.raises(ValueError, match="domain error"):
            with observer.source_span():
                raise ValueError("domain error")
        health = sink.snapshot()
        assert health.state == "degraded"
        assert health.last_error_code == "trading_observer_failed"
    finally:
        sink.close(timeout_seconds=5)


def test_an_observer_without_a_sink_records_nothing_and_changes_nothing() -> None:
    observer = TradingTelemetry()
    with observer.model_span("message"):
        result = 42
    observer.event("order_prepared")
    assert result == 42
    assert observer.register_secrets(("anything",))
