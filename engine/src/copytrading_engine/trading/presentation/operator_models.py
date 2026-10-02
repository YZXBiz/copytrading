"""Bounded native read contracts backed by operational evidence."""

from decimal import Decimal
from typing import Literal

from pydantic import AwareDatetime

from copytrading_engine.execution.domain.values import Value
from copytrading_engine.execution.presentation.operator_views import (
    AccountUnavailable,
    DestinationView,
)


class SourceEmbedField(Value):
    name: str
    value: str
    inline: bool


class SourceEmbedEvidence(Value):
    title: str | None = None
    description: str | None = None
    fields: tuple[SourceEmbedField, ...]


class SourceAttachmentEvidence(Value):
    evidence_id: str
    attachment_id: str
    filename: str
    content_type: str | None
    declared_size: int
    status: Literal[
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
    byte_size: int | None = None
    sha256: str | None = None
    omitted_count: int = 0


class SourceEventEvidence(Value):
    event_type: str
    message_id: str | None = None
    channel_id: str | None = None
    author_id: str | None = None
    timestamp: str | None = None
    content: str
    embeds: tuple[SourceEmbedEvidence, ...]
    attachments: tuple[SourceAttachmentEvidence, ...]
    attachments_omitted: int
    capture_status: Literal["complete", "oversize", "missing"]
    payload_bytes: int


class RejectedSourceActivity(Value):
    source_id: str
    rejected_at: AwareDatetime
    reason: str
    source_event: SourceEventEvidence


class InstructionView(Value):
    """One trade the interpreter read from a post, before any account sizing."""

    action: Literal["buy", "reduce", "close"]
    symbol: str
    price: Decimal
    fraction: Decimal | None


class SourceActivity(Value):
    sequence: int
    source_id: str
    author_id: str | None = None
    source_revision: int
    source_at: AwareDatetime
    captured_at: AwareDatetime
    text: str
    capture_status: str
    parse_status: str
    delivery_status: str
    decision: str | None
    parser_reason: str | None
    parser_profile: str | None
    interpreted_by: str | None
    instructions: tuple[InstructionView, ...]
    guru_id: str | None = None
    profile_revision: str | None = None
    source_event: SourceEventEvidence
    destinations: tuple[DestinationView, ...]


class SourceActivityPage(Value):
    items: tuple[SourceActivity, ...]
    rejected_items: tuple[RejectedSourceActivity, ...]
    next_before_seq: int | None = None
    unavailable_accounts: tuple[AccountUnavailable, ...] = ()
