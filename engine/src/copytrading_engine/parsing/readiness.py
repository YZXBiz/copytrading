"""Provider readiness observations; a delayed probe cannot overwrite a newer alert result."""

import time
from dataclasses import dataclass, field

from copytrading_engine.parsing.extraction import DecodeError, Decoder, Route


@dataclass
class ModelReadiness:
    ready: bool = False
    checked_at: float | None = None
    error: str | None = None
    revision: int = field(default=0, init=False)

    def record(self, error: str | None = None) -> None:
        self.ready = error is None
        self.error = error
        self.checked_at = time.time()
        self.revision += 1


async def probe_model(decoder: Decoder, health: ModelReadiness) -> None:
    revision = health.revision
    try:
        result = await decoder.decode("Market commentary only. No trade action.", Route())
        error = (
            None
            if result.decision == "ignore" and not result.instructions
            else "unexpected_probe_output"
        )
    except DecodeError as exc:
        error = exc.reason
    # Real extraction is stronger evidence than a probe started before that extraction.
    if health.revision == revision:
        health.record(error)
