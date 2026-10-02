"""Diagnostic events the telemetry tests record, and the journal they read back."""

import json
from pathlib import Path
from types import SimpleNamespace
from typing import Any, TypedDict

from copytrading_engine.diagnostics.redaction import JsonValue
from copytrading_engine.diagnostics.telemetry.config import TelemetryConfig
from copytrading_engine.diagnostics.telemetry.local import LocalTelemetry
from copytrading_engine.host.self_test.model import Stage


class _RecordArguments(TypedDict):
    command_id: str
    trace_id: str
    stage: Stage
    outcome: str
    payload: JsonValue


def event(command_id: str) -> _RecordArguments:
    return {
        "command_id": command_id,
        "trace_id": "4f0f5f8d9b0f4c2e8b3a7c6d5e4f3210",
        "stage": Stage.CAPTURED,
        "outcome": "accepted",
        "payload": {"request": {"text": "Bought AAPL 1/6 at 200"}},
    }


def journal_text(directory: Path) -> str:
    return "".join(
        path.read_text(encoding="utf-8") for path in sorted(directory.glob("diagnostics.jsonl*"))
    )


def journal_records(directory: Path) -> list[dict[str, Any]]:
    """Every journal line, oldest rotation first."""
    rotations = sorted(
        directory.glob("diagnostics.jsonl*"),
        key=lambda path: -int(path.suffix[1:]) if path.suffix[1:].isdigit() else 0,
    )
    return [
        json.loads(line)
        for path in rotations
        for line in path.read_text(encoding="utf-8").splitlines()
        if line
    ]


def journal_sink(directory: Path, *, secrets: tuple[str, ...] = ()) -> LocalTelemetry:
    """A journaling sink that already redacts `secrets`."""
    sink = LocalTelemetry(TelemetryConfig(journal_directory=directory))
    assert sink.register_secrets(secrets)
    return sink


def journal_events(directory: Path) -> list[SimpleNamespace]:
    """Journal lines as attribute objects, for tests that read fields by name."""
    return [SimpleNamespace(**record) for record in journal_records(directory)]
