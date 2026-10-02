"""Forward saved source messages; confirm only after the publisher acknowledges."""

import logging
from collections.abc import Callable, Mapping, Sequence
from contextlib import AbstractContextManager, nullcontext
from dataclasses import dataclass
from typing import Literal, Protocol

from pydantic import JsonValue

from copytrading_engine.shared.raw_message import RawMessage
from copytrading_engine.sources.recovery import RecoveryStart, RejectedCapture

log = logging.getLogger(__name__)


@dataclass(frozen=True, slots=True)
class Delivery:
    key: str
    payload: str
    mode: Literal["live", "historical"]

    def __post_init__(self) -> None:
        if self.mode not in {"live", "historical"}:
            raise ValueError("Saved delivery has an unknown route")


@dataclass(frozen=True, slots=True)
class AttachmentReference:
    """Ephemeral source-adapter metadata; the signed URL is never persisted."""

    attachment_id: str
    filename: str
    content_type: str | None
    declared_size: int
    url: str


AttachmentStatus = Literal[
    "pending",
    "available",
    "missing",
    "oversize",
    "download_failed",
    "origin_rejected",
    "timed_out",
    "count_exceeded",
    "skipped_rejected",
]


@dataclass(frozen=True, slots=True)
class SourceAttachmentEvidence:
    """Source-owned metadata and private managed reference for one attachment."""

    evidence_id: str
    attachment_id: str
    filename: str
    content_type: str | None
    declared_size: int
    status: AttachmentStatus
    byte_size: int | None = None
    sha256: str | None = None
    managed_path: str | None = None
    omitted_count: int = 0


class SourceCapture(Protocol):
    """Save a validated message or retain the complete rejected input."""

    async def add(
        self,
        event: RawMessage,
        *,
        source_event: JsonValue | None = None,
        attachments: Sequence[AttachmentReference] = (),
    ) -> None: ...

    async def reject(
        self,
        event: dict[str, JsonValue],
        reason: str,
        *,
        source_event: JsonValue | None = None,
        attachments: Sequence[AttachmentReference] = (),
    ) -> None: ...


class RecoveryCapture(SourceCapture, Protocol):
    async def recovery_start(self, channel_id: int, fallback_id: int) -> RecoveryStart: ...

    async def capture_recovery_page(
        self,
        channel_id: int,
        events: list[RawMessage],
        rejected: list[RejectedCapture],
        last_id: int,
        *,
        source_events: Mapping[str, JsonValue] | None = None,
        attachments: Mapping[str, Sequence[AttachmentReference]] | None = None,
    ) -> None: ...


class SourceOutbox(Protocol):
    async def claim_batch(self) -> Sequence[Delivery]:
        """Return the unconfirmed batch, or durably assign the next ordered batch.

        This writes delivery state. Rows include identity, payload, and fixed route;
        their order must survive retries and process restart.
        """
        ...

    async def confirm(self, key: str) -> None: ...


class SourcePublisher(Protocol):
    async def publish(self, delivery: Delivery) -> None:
        """Return only after acknowledgement; retries retain the original identity."""
        ...


class ForwardBatch:
    def __init__(
        self,
        outbox: SourceOutbox,
        publisher: SourcePublisher,
        *,
        observe: Callable[[], AbstractContextManager[None]] = nullcontext,
    ) -> None:
        self.outbox, self.publisher = outbox, publisher
        self.observe = observe

    async def flush(self) -> int:
        rows = await self.outbox.claim_batch()
        if not rows:
            # The loop polls about twice a second; an empty poll is not an operation to record.
            return 0
        with self.observe():
            for delivery in rows:
                # Failure or cancellation in either step retains the unconfirmed head.
                # Replays can duplicate transport delivery, never invent a new identity.
                await self.publisher.publish(delivery)
                await self.outbox.confirm(delivery.key)
                log.info("message_published id=%s mode=%s", delivery.key, delivery.mode)
        return len(rows)
