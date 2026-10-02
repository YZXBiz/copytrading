"""Bounded, validated journal field values."""

import re

from copytrading_engine.host.self_test.model import Stage
from copytrading_engine.shared.payload_capture import CaptureKind


def stages() -> tuple[str, ...]:
    return tuple(stage.value for stage in Stage)


def bounded_label(value: str, allowed: tuple[str, ...]) -> str:
    return value if value in allowed else "other"


def validated_hex_id(value: str | None, size: int) -> str | None:
    if value is None:
        return None
    candidate = value.replace("-", "").casefold()
    if len(candidate) != size or not re.fullmatch(r"[0-9a-f]+", candidate):
        return None
    if int(candidate, 16) == 0:
        return None
    return candidate


def bounded_opaque_id(value: str, maximum: int) -> str:
    if len(value) <= maximum and re.fullmatch(r"[A-Za-z0-9._:-]+", value):
        return value
    return "[REDACTED]"


def capture_counter_keys(kind: CaptureKind) -> tuple[str | None, str | None]:
    return {
        "source_event": ("source_events", "source_event_gaps"),
        "model_request": ("model_requests", "model_request_gaps"),
        "model_response": ("model_responses", "model_response_gaps"),
        "other": (None, None),
    }[kind]
