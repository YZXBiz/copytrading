"""Bounded native read contracts backed by operational evidence."""

from typing import Literal

from pydantic import AwareDatetime

from copytrading_engine.execution.domain.values import Value
from copytrading_engine.execution.presentation.operator_views import (
    AccountUnavailable,
    DestinationView,
)
from copytrading_engine.shared.reading import PostReading
from copytrading_engine.shared.signals import Instruction


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
    # The calls the post trades, as the engine places them, before any account sizing.
    instructions: tuple[Instruction, ...]
    # For a post that waits for the owner: what Copy places (ADR-0007).
    suggested: tuple[Instruction, ...] = ()
    # How the reader read the post, for Activity's "Read as".
    reading: PostReading | None = None
    guru_id: str | None = None
    profile_revision: str | None = None
    source_event: SourceEventEvidence
    destinations: tuple[DestinationView, ...]
    # When the reader took the post, when it finished, and when the reading reached the
    # accounts: with source_at and captured_at, how long each step took.
    read_started_at: AwareDatetime | None = None
    read_at: AwareDatetime | None = None
    delivered_at: AwareDatetime | None = None


class SourceActivityPage(Value):
    items: tuple[SourceActivity, ...]
    rejected_items: tuple[RejectedSourceActivity, ...]
    next_before_seq: int | None = None
    unavailable_accounts: tuple[AccountUnavailable, ...] = ()


class GuruPost(Value):
    """One read post of a guru's: when it was posted and how long the reader took."""

    source_id: str
    guru_id: str
    source_at: AwareDatetime
    read_started_at: AwareDatetime | None = None
    read_at: AwareDatetime | None = None


class GuruDayStats(Value):
    """One guru's numbers for a day, counted from every post the engine holds, not one page."""

    guru_id: str
    posts: int
    #: The day's posts at least one account bought or sold on.
    traded: int
    #: How long the reader took per post that day, on average; None before any was read.
    read_seconds: float | None = None
    #: Posts of the current trading day a call of which still waits for the owner, any calendar
    #: day; the app leaves out the ones the owner skipped, which only it knows.
    waiting_source_ids: tuple[str, ...] = ()


class GuruDayStatsPage(Value):
    day_start: AwareDatetime
    day_end: AwareDatetime
    gurus: tuple[GuruDayStats, ...]
    unavailable_accounts: tuple[AccountUnavailable, ...] = ()
