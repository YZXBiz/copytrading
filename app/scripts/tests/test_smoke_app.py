from __future__ import annotations

import sqlite3
import subprocess
import sys
from contextlib import closing
from pathlib import Path

import pytest

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
import smoke_app  # noqa: E402 - importable only after the scripts directory is on sys.path


def _write_operational_database(database: Path) -> None:
    database.parent.mkdir(parents=True, exist_ok=True)
    with closing(sqlite3.connect(database)) as connection, connection:
        for name in ("engine_metadata", "workflows", "jobs", "audit_events"):
            connection.execute(f"CREATE TABLE {name} (id INTEGER PRIMARY KEY)")


def test_operational_database_uses_active_generation(tmp_path: Path) -> None:
    state = tmp_path / "state"
    generation_id = "7fd3821d-66f4-45cc-9bde-311f90ed08c3"
    _write_operational_database(state / "generations" / generation_id / "application.db")
    (state / "active-generation").write_text(f"{generation_id}\n")
    (state / "generations" / generation_id).chmod(0o700)

    assert not (state / "application.db").exists()
    assert smoke_app._operational_database(state)


def test_operational_database_rejects_invalid_active_generation(tmp_path: Path) -> None:
    state = tmp_path / "state"
    _write_operational_database(state / "application.db")
    (state / "active-generation").write_text("../application.db\n")

    assert not smoke_app._operational_database(state)


def test_cleanup_failure_does_not_mask_startup_failure(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    temporary = tmp_path / "private root"
    temporary.mkdir()
    startup_error = RuntimeError("startup failed")

    monkeypatch.setattr(
        smoke_app,
        "_stop_relocated_runtime",
        lambda *_args, **_kwargs: "owned runtime did not stop",
    )

    with pytest.raises(RuntimeError, match="startup failed"):
        try:
            raise startup_error
        except RuntimeError as original:
            smoke_app._finish_smoke_workspace(
                temporary,
                tmp_path / "runtime",
                set(),
                None,
                original,
            )
            raise

    assert temporary.exists()
    assert "startup failed" not in capsys.readouterr().err


def test_cleanup_failure_without_primary_error_is_reported(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    temporary = tmp_path / "private root"
    temporary.mkdir()
    monkeypatch.setattr(
        smoke_app,
        "_stop_relocated_runtime",
        lambda *_args, **_kwargs: "owned runtime did not stop",
    )

    with pytest.raises(RuntimeError, match="owned runtime did not stop"):
        smoke_app._finish_smoke_workspace(
            temporary,
            tmp_path / "runtime",
            set(),
            None,
            None,
        )

    assert temporary.exists()


def test_runtime_cleanup_signals_only_processes_for_this_runtime(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    exited = subprocess.Popen([sys.executable, "-c", "pass"])
    exited.wait()
    observations = iter(({101, 202}, set()))
    signals: list[tuple[int, int]] = []
    monkeypatch.setattr(smoke_app, "_runtime_processes", lambda _runtime: next(observations))

    def record_signal(pid: int, sig: int) -> None:
        signals.append((pid, sig))

    monkeypatch.setattr(smoke_app.os, "kill", record_signal)
    monkeypatch.setattr(smoke_app.time, "sleep", lambda _seconds: None)

    result = smoke_app._stop_relocated_runtime(exited, tmp_path / "unique-runtime", {101, 303})

    assert result is None
    assert set(signals) == {
        (101, smoke_app.signal.SIGTERM),
        (202, smoke_app.signal.SIGTERM),
    }
