"""The private journal: one JSON object per line, private, bounded by age and size."""

import io
import os
import stat
import threading
from datetime import UTC, datetime, timedelta

import pytest

from copytrading_engine.diagnostics.telemetry import journal as journal_module
from copytrading_engine.diagnostics.telemetry.config import (
    DEFAULT_MAX_BYTES,
    DEFAULT_RETENTION_DAYS,
    MIN_MAX_BYTES,
    TelemetryConfig,
)
from copytrading_engine.diagnostics.telemetry.local import LocalTelemetry

from .builders import event, journal_records, journal_text


def test_each_record_is_one_self_describing_json_line(tmp_path):
    directory = tmp_path / "diagnostics"
    sink = LocalTelemetry(TelemetryConfig(journal_directory=directory))
    try:
        sink.record_stage(**event("sim-1"))
        sink.record_trading_operation(operation="model.parse", outcome="returned")
        assert sink.flush(timeout_seconds=5)
        assert sink.snapshot().state == "healthy"
    finally:
        sink.close(timeout_seconds=5)

    stage, trading = journal_records(directory)
    assert stage["kind"] == "stage"
    assert stage["command_id"] == "sim-1"
    assert stage["payload"] == {"request": {"text": "Bought AAPL 1/6 at 200"}}
    assert datetime.fromisoformat(stage["at"]).tzinfo is not None
    assert trading["kind"] == "trading"
    assert trading["operation"] == "model.parse"


def test_journal_directory_and_files_are_private(tmp_path):
    directory = tmp_path / "diagnostics"
    sink = LocalTelemetry(TelemetryConfig(journal_directory=directory))
    try:
        sink.record_stage(**event("sim-private"))
        assert sink.flush(timeout_seconds=5)
    finally:
        sink.close(timeout_seconds=5)

    assert stat.S_IMODE(directory.stat().st_mode) == 0o700
    files = list(directory.glob("diagnostics.jsonl*"))
    assert files
    assert all(stat.S_IMODE(path.stat().st_mode) == 0o600 for path in files)


def test_rotation_keeps_a_finite_file_set_within_the_storage_limit(tmp_path):
    directory = tmp_path / "diagnostics"
    errors: list[int] = []
    logger, error = journal_module.journal_logger(
        directory, retention_age_days=3, max_bytes=8 * 1_024, on_error=lambda: errors.append(1)
    )
    assert error is None
    assert logger is not None
    try:
        for index in range(200):
            logger.info(f'{{"index": {index}, "padding": "{"x" * 200}"}}')
    finally:
        for handler in logger.handlers[:]:
            handler.close()

    files = list(directory.glob("diagnostics.jsonl*"))
    assert len(files) == 8  # the active file plus seven rotations
    assert sum(path.stat().st_size for path in files) <= 8 * 1_024 + 8 * 300
    assert not errors


def test_expiry_removes_only_whole_utc_days_past_retention(tmp_path):
    directory = tmp_path / "diagnostics"
    directory.mkdir()
    now = datetime(2026, 9, 26, 12, 0, tzinfo=UTC)
    expired = directory / "diagnostics.jsonl.3"
    retained_boundary = directory / "diagnostics.jsonl.2"
    current = directory / "diagnostics.jsonl"
    unrelated = directory / "notes.txt"
    for path in (expired, retained_boundary, current, unrelated):
        path.write_text("record", encoding="utf-8")
    old = (now - timedelta(days=4)).timestamp()
    boundary = (now - timedelta(days=3)).timestamp()
    os.utime(expired, (old, old))
    os.utime(retained_boundary, (boundary, boundary))
    os.utime(unrelated, (old, old))

    journal_module.prune_journal(directory, retention_age_days=3, now=now)

    assert not expired.exists()
    assert retained_boundary.exists()
    assert current.exists()
    assert unrelated.exists()


def test_write_errors_degrade_health_without_a_traceback(tmp_path, monkeypatch, capsys):
    secret = "disk-error-secret-4a9c"
    sink = LocalTelemetry(TelemetryConfig(journal_directory=tmp_path / "diagnostics"))
    try:
        sink.record_stage(**event("journal-first"))
        assert sink.flush(timeout_seconds=5)

        def fail_emit(handler, record):
            raise OSError(f"disk rejected {secret}")

        monkeypatch.setattr(journal_module._PrivateRotatingFileHandler, "shouldRollover", fail_emit)
        sink.record_stage(**event("journal-second"))
        assert sink.flush(timeout_seconds=5)
        health = sink.snapshot()
    finally:
        sink.close(timeout_seconds=5)

    output = capsys.readouterr()
    assert health.state == "degraded"
    assert health.dropped_records > 0
    assert health.last_error_code == "journal_write_failed"
    assert secret not in output.out + output.err
    assert "Traceback" not in output.err


def test_a_full_queue_drops_records_and_reports_it(tmp_path):
    directory = tmp_path / "diagnostics"
    sink = LocalTelemetry(TelemetryConfig(journal_directory=directory, queue_capacity=2))
    entered = threading.Event()
    release = threading.Event()
    write = sink._write

    def blocking_write(item):
        entered.set()
        assert release.wait(timeout=5)
        return write(item)

    sink._write = blocking_write
    try:
        sink.record_stage(**event("sim-1"))
        assert entered.wait(timeout=3)
        for index in range(2, 9):
            sink.record_stage(**event(f"sim-{index}"))
        health = sink.snapshot()
    finally:
        release.set()
        assert sink.flush(timeout_seconds=5)
        sink.close(timeout_seconds=5)

    assert health.state == "degraded"
    assert health.dropped_records == 5
    assert health.last_error_code == "queue_full"
    assert "Bought AAPL 1/6 at 200" in journal_text(directory)


def test_records_after_close_are_counted_as_dropped(tmp_path):
    sink = LocalTelemetry(TelemetryConfig(journal_directory=tmp_path / "diagnostics"))
    sink.close(timeout_seconds=5)
    sink.record_stage(**event("late"))

    assert sink.snapshot().dropped_records == 1
    assert sink.snapshot().last_error_code == "sink_closed"
    assert not sink.flush(timeout_seconds=1)


def test_writer_has_no_buffered_bytes_to_retry_at_full_disk(tmp_path):
    sink = LocalTelemetry(TelemetryConfig(journal_directory=tmp_path / "diagnostics"))
    try:
        assert sink._logger is not None
        handler = sink._logger.handlers[0]
        assert isinstance(handler, journal_module._PrivateRotatingFileHandler)
        assert handler.stream is not None
        assert handler.stream.write_through
        assert isinstance(handler.stream.buffer, io.FileIO)
    finally:
        sink.close(timeout_seconds=5)


def test_environment_sets_retention_and_storage_limit(monkeypatch, tmp_path):
    monkeypatch.setenv("COPYTRADING_DESKTOP_DIAGNOSTICS_RETENTION_DAYS", "14")
    monkeypatch.setenv("COPYTRADING_DESKTOP_DIAGNOSTICS_MAX_BYTES", str(MIN_MAX_BYTES * 4))

    config = TelemetryConfig.from_environment(tmp_path)

    assert config.journal_directory == tmp_path
    assert config.retention_age_days == 14
    assert config.max_bytes == MIN_MAX_BYTES * 4


@pytest.mark.parametrize(
    ("days", "size"), [("0", "1"), ("not-a-number", "-5"), ("99999", str(1 << 60))]
)
def test_unusable_environment_values_keep_the_defaults(monkeypatch, tmp_path, days, size):
    monkeypatch.setenv("COPYTRADING_DESKTOP_DIAGNOSTICS_RETENTION_DAYS", days)
    monkeypatch.setenv("COPYTRADING_DESKTOP_DIAGNOSTICS_MAX_BYTES", size)

    config = TelemetryConfig.from_environment(tmp_path)

    assert config.retention_age_days == DEFAULT_RETENTION_DAYS
    assert config.max_bytes == DEFAULT_MAX_BYTES
