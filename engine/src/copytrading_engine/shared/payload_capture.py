"""The wire-capture vocabulary shared by payload producers and the diagnostics sink."""

from typing import Literal, Protocol

from copytrading_engine.shared.model_providers import ModelProvider

type JsonValue = bool | int | float | str | list[JsonValue] | dict[str, JsonValue] | None
type CaptureKind = Literal["source_event", "model_request", "model_response", "other"]
type CaptureStatus = Literal["complete", "incomplete", "missing", "oversize"]
type ProviderName = ModelProvider | Literal["other"]


class PayloadCapture(Protocol):
    """Record one bounded wire payload for diagnostics; never alters the caller's work."""

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
        max_bytes: int = ...,
        status: CaptureStatus = "complete",
    ) -> None: ...
