"""Payload capture is redacted and bounded; its gaps show without changing the workflow."""

from copytrading_engine.diagnostics.capture import DiagnosticEngineQueries, DiagnosticWorkflowStore
from copytrading_engine.diagnostics.telemetry import local as local_module
from copytrading_engine.diagnostics.telemetry.config import TelemetryConfig
from copytrading_engine.diagnostics.telemetry.local import LocalTelemetry
from copytrading_engine.host.installation import Installation
from copytrading_engine.host.self_test.model import Stage, SubmitSelfTest
from copytrading_engine.host.self_test.parser import SelfTestParser
from copytrading_engine.host.self_test.service import SelfTestService
from copytrading_engine.host.self_test.store import SQLiteSelfTestStore

from .builders import journal_records, journal_text

_TRACE = "4f0f5f8d9b0f4c2e8b3a7c6d5e4f3210"


def test_payload_capture_is_redacted_bounded_and_exposes_gap_counts(tmp_path):
    directory = tmp_path / "diagnostics"
    secret = "provider-secret-0123456789"
    sink = LocalTelemetry(TelemetryConfig(journal_directory=directory))
    try:
        assert sink.register_secrets((secret,))
        sink.record_payload(
            capture_kind="model_request",
            workflow_id=_TRACE,
            trace_id=_TRACE,
            destination_id="e86aa73e66f543799968ef089b13b664",
            attempt=2,
            provider="deepseek",
            payload={"messages": [{"content": "use " + secret}]},
            source_bytes=100,
        )
        sink.record_payload(
            capture_kind="model_response",
            workflow_id=_TRACE,
            trace_id=_TRACE,
            destination_id=None,
            attempt=2,
            provider="deepseek",
            payload={"response": "x" * 80},
            source_bytes=80,
            max_bytes=64,
        )
        assert sink.flush(timeout_seconds=5)
        health = sink.capture_health()
    finally:
        sink.close(timeout_seconds=5)

    complete, oversize = journal_records(directory)
    assert complete["kind"] == "payload"
    assert complete["capture_kind"] == "model_request"
    assert complete["capture_status"] == "complete"
    assert complete["payload"] == {"messages": [{"content": "use [REDACTED]"}]}
    assert complete["redacted_fields"] > 0
    assert complete["trace_id"] == _TRACE
    assert oversize["capture_status"] == "oversize"
    assert oversize["payload"] is None
    assert oversize["payload_bytes"] == 80
    assert health.model_requests == 1
    assert health.model_request_gaps == 0
    assert health.model_responses == 0
    assert health.model_response_gaps == 1
    assert secret not in journal_text(directory)


def test_secret_registry_overflow_disables_payload_capture_as_a_gap(tmp_path):
    directory = tmp_path / "diagnostics"
    credentials = tuple(
        f"configured-credential-{index}" for index in range(local_module._MAX_KNOWN_SECRETS)
    )
    overflow_secret = "credential-rejected-by-bounded-registry"
    sink = LocalTelemetry(TelemetryConfig(journal_directory=directory))
    try:
        assert sink.register_secrets(credentials)
        assert not sink.register_secrets((overflow_secret,))
        sink.record_payload(
            capture_kind="model_response",
            workflow_id=None,
            trace_id=None,
            destination_id=None,
            attempt=None,
            provider="anthropic",
            payload={"error": "model echoed " + overflow_secret},
        )
        assert sink.flush(timeout_seconds=5)
        health = sink.capture_health()
    finally:
        sink.close(timeout_seconds=5)

    (record,) = journal_records(directory)
    assert record["capture_status"] == "incomplete"
    assert record["payload"] is None
    assert health.model_responses == 0
    assert health.model_response_gaps == 1
    assert overflow_secret not in journal_text(directory)


async def test_engine_status_exposes_typed_capture_gaps_and_journal_health(tmp_path):
    sink = LocalTelemetry(TelemetryConfig(journal_directory=tmp_path / "diagnostics"))
    try:
        sink.record_payload(
            capture_kind="source_event",
            workflow_id=None,
            trace_id=None,
            destination_id=None,
            attempt=None,
            provider="other",
            payload={"source": "bounded"},
        )
        sink.record_payload(
            capture_kind="model_response",
            workflow_id=None,
            trace_id=None,
            destination_id=None,
            attempt=None,
            provider="other",
            payload=None,
            status="missing",
        )
        assert sink.flush(timeout_seconds=5)
        with (
            Installation(tmp_path / "application.db") as installation,
            SQLiteSelfTestStore(installation) as store,
        ):
            status = await DiagnosticEngineQueries(
                store, store.installation.instance_id, sink
            ).status("running")
    finally:
        sink.close(timeout_seconds=5)

    assert status.diagnostic_capture.source_events == 1
    assert status.diagnostic_capture.source_event_gaps == 0
    assert status.diagnostic_capture.model_responses == 0
    assert status.diagnostic_capture.model_response_gaps == 1
    assert status.telemetry_state == "healthy"
    assert status.telemetry_error_code is None


async def test_journal_failures_do_not_change_committed_workflow(tmp_path):
    blocked = tmp_path / "diagnostics"
    blocked.write_text("a file where the journal directory should be", encoding="utf-8")
    sink = LocalTelemetry(TelemetryConfig(journal_directory=blocked))
    try:
        with (
            Installation(tmp_path / "application.db") as installation,
            SQLiteSelfTestStore(installation) as store,
        ):
            service = SelfTestService(DiagnosticWorkflowStore(store, sink), SelfTestParser())
            command = SubmitSelfTest(
                "sim-durable", "Bought AAPL 1/6 at 200", ("self-test-a", "self-test-b")
            )
            accepted = await service.submit(command)
            await service.process_pending()
            completed = await store.get_async(command.command_id)
            assert sink.flush(timeout_seconds=5)
            status = await DiagnosticEngineQueries(
                store, store.installation.instance_id, sink
            ).status("running")
    finally:
        sink.close(timeout_seconds=5)

    assert accepted.trace_id == completed.trace_id
    assert completed.stage is Stage.COMPLETED
    assert status.telemetry_state == "degraded"
    assert status.telemetry_dropped > 0
    assert status.telemetry_error_code == "journal_unavailable"


async def test_idempotent_accept_retries_record_capture_once_and_mark_the_anchor(tmp_path):
    directory = tmp_path / "diagnostics"
    sink = LocalTelemetry(TelemetryConfig(journal_directory=directory))
    command = SubmitSelfTest("sim-idempotent-accept", "Bought AAPL 1/6 at 200", ("self-test-a",))
    try:
        with (
            Installation(tmp_path / "application.db") as installation,
            SQLiteSelfTestStore(installation) as store,
        ):
            service = SelfTestService(DiagnosticWorkflowStore(store, sink), SelfTestParser())
            accepted = await service.submit(command)
            assert await service.submit(command) == accepted
            assert sink.flush(timeout_seconds=5)
            assert await store.trace_anchor_exported_async(command.command_id)

            await service.process_pending()
            completed = await store.get_async(command.command_id)
            assert completed.stage is Stage.COMPLETED
            assert await service.submit(command) == completed
            assert sink.flush(timeout_seconds=5)
    finally:
        sink.close(timeout_seconds=5)

    stages = [
        (record["command_id"], record["stage"])
        for record in journal_records(directory)
        if record["kind"] == "stage"
    ]
    assert stages == [
        (command.command_id, "captured"),
        (command.command_id, "parsed"),
        (command.command_id, "completed"),
    ]


def test_redaction_is_applied_before_the_journal(tmp_path):
    directory = tmp_path / "diagnostics"
    secret = "probe-key-0123456789"
    sink = LocalTelemetry(TelemetryConfig(journal_directory=directory))
    try:
        assert sink.register_secrets((secret,))
        sink.record_stage(
            command_id="sim-safe",
            trace_id=_TRACE,
            stage=Stage.CAPTURED,
            outcome="accepted",
            payload={
                "message": "Bought AAPL 1/6",
                "headers": {"Authorization": "Bearer " + secret},
                "error": "request failed using " + secret,
            },
        )
        assert sink.flush(timeout_seconds=5)
    finally:
        sink.close(timeout_seconds=5)

    journal = journal_text(directory)
    assert "Bought AAPL 1/6" in journal
    assert secret not in journal
