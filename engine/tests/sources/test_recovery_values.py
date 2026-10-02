"""Recovery protocol values own immutable, validated state."""

import datetime as dt
from collections.abc import Mapping
from dataclasses import FrozenInstanceError
from typing import Any, cast

import pytest
from pydantic import JsonValue

from copytrading_engine.sources.recovery import RecoveryProgress, RecoveryStart, RejectedCapture


def test_recovery_start_is_a_frozen_named_value():
    start = RecoveryStart(41, "earliest_retained")
    assert start.last_id == 41
    assert start.bootstrap == "earliest_retained"
    with pytest.raises(FrozenInstanceError):
        cast(Any, start).last_id = 42


def test_recovery_progress_requires_an_aware_update_time():
    progress = RecoveryProgress(
        channel_id="7",
        last_id=42,
        bootstrap="recent_only",
        updated_at=dt.datetime(2026, 9, 24, tzinfo=dt.UTC),
    )
    assert progress.updated_at.utcoffset() == dt.timedelta(0)
    with pytest.raises(ValueError, match="timezone-aware"):
        RecoveryProgress("7", 42, "recent_only", dt.datetime(2026, 9, 24))


def test_rejected_capture_copies_and_freezes_nested_payloads():
    source: dict[str, JsonValue] = {"nested": {"ids": [1, {"ok": True}]}}
    rejected = RejectedCapture(source, "invalid")
    source_nested = source["nested"]
    source_ids = cast(list[JsonValue], source_nested["ids"])
    cast(dict[str, JsonValue], source_ids[1])["ok"] = False

    payload_nested = cast(Mapping[str, JsonValue], rejected.payload["nested"])
    payload_ids = cast(tuple[JsonValue, ...], payload_nested["ids"])
    assert payload_ids == (1, {"ok": True})
    with pytest.raises(TypeError):
        cast(Any, rejected.payload)["new"] = "later"
    with pytest.raises(TypeError):
        cast(Any, cast(Mapping[str, JsonValue], payload_ids[1]))["ok"] = False
