"""Provider readiness observations; a delayed probe cannot overwrite a newer alert result."""

import time
from dataclasses import dataclass, field

from copytrading_engine.parsing.extraction import DecodeError, Decoder, Route
from copytrading_engine.shared.reading import Chatter, Commentary


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
        result = (await decoder.answer("Market commentary only. No trade action.", Route())).reading
        # Either way it reads as nothing to trade: a model may fairly take the line for chat.
        error = None if isinstance(result, Commentary | Chatter) else "unexpected_probe_output"
    except DecodeError as exc:
        error = exc.reason
    # Real extraction is stronger evidence than a probe started before that extraction.
    if health.revision == revision:
        health.record(error)
