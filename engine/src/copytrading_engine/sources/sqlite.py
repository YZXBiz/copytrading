"""Durable Discord capture, recovery cursor and live parser delivery in SQLite."""

from __future__ import annotations

import asyncio
import datetime as dt
import hashlib
import json
import sqlite3
from collections.abc import Callable, Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import cast
from uuid import uuid4

import httpx2 as httpx
from pydantic import JsonValue, TypeAdapter

from copytrading_engine.shared.payload_capture import CaptureStatus, PayloadCapture
from copytrading_engine.shared.queue_snapshot import QueueSnapshot
from copytrading_engine.shared.raw_message import RawMessage
from copytrading_engine.shared.sqlite import SchemaComponent, SQLiteUnit, ensure_schema
from copytrading_engine.sources.application import (
    AttachmentReference,
    AttachmentStatus,
    Delivery,
    SourceAttachmentEvidence,
)
from copytrading_engine.sources.attachments import (
    AttachmentCaptureResult,
    capture_attachments,
    read_managed_content,
)
from copytrading_engine.sources.delivery_policy import delivery_mode
from copytrading_engine.sources.evidence import (
    OMITTED_ATTACHMENT_ID,
    bounded_source_event,
    is_evidence_id,
    normalized_source_event,
)
from copytrading_engine.sources.evidence import bounded_attachments as bound_attachment_references
from copytrading_engine.sources.recovery import (
    Bootstrap,
    RecoveryProgress,
    RecoveryStart,
    RejectedCapture,
    plain_json,
)


class SourceIdentityConflict(ValueError):
    """One source identity was reused with different content."""


SOURCE_SCHEMA = SchemaComponent(
    "source",
    3,
    """
CREATE TABLE IF NOT EXISTS source_captures (
    seq INTEGER PRIMARY KEY AUTOINCREMENT,
    id TEXT NOT NULL UNIQUE,
    hash TEXT NOT NULL,
    payload TEXT NOT NULL,
    source_at TEXT NOT NULL,
    captured_at TEXT NOT NULL,
    recovered INTEGER NOT NULL,
    mode TEXT NOT NULL CHECK(mode IN ('live','historical')),
    workflow_id TEXT NOT NULL,
    trace_id TEXT NOT NULL,
    assigned_seq INTEGER UNIQUE,
    confirmed INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS source_captures_waiting
    ON source_captures(assigned_seq) WHERE mode='live' AND confirmed=0;
CREATE TABLE IF NOT EXISTS source_rejected (
    id TEXT PRIMARY KEY,
    hash TEXT NOT NULL,
    payload TEXT NOT NULL,
    reason TEXT NOT NULL,
    rejected_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS source_event_evidence (
    source_id TEXT PRIMARY KEY,
    accepted INTEGER NOT NULL CHECK(accepted IN (0,1)),
    event_payload TEXT,
    capture_status TEXT NOT NULL CHECK(capture_status IN ('complete','oversize','missing')),
    payload_bytes INTEGER NOT NULL CHECK(payload_bytes >= 0),
    captured_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS source_attachment_evidence (
    source_id TEXT NOT NULL,
    evidence_id TEXT NOT NULL UNIQUE,
    attachment_id TEXT NOT NULL,
    filename TEXT NOT NULL,
    content_type TEXT,
    declared_size INTEGER NOT NULL CHECK(declared_size >= 0),
    capture_status TEXT NOT NULL CHECK(capture_status IN (
        'pending','available','missing','oversize','download_failed',
        'origin_rejected','timed_out','count_exceeded'
    )),
    byte_size INTEGER CHECK(byte_size IS NULL OR byte_size >= 0),
    sha256 TEXT,
    managed_path TEXT,
    omitted_count INTEGER NOT NULL DEFAULT 0 CHECK(omitted_count >= 0),
    PRIMARY KEY(source_id,attachment_id),
    FOREIGN KEY(source_id) REFERENCES source_captures(id)
);
CREATE INDEX IF NOT EXISTS source_attachment_evidence_source
    ON source_attachment_evidence(source_id,attachment_id);
CREATE TABLE IF NOT EXISTS source_cursors (
    channel_id TEXT PRIMARY KEY,
    last_id INTEGER NOT NULL,
    bootstrap TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
""",
)

REJECTED_ATTACHMENT_SCHEMA = SchemaComponent(
    "source_rejected_attachment",
    1,
    """
CREATE TABLE IF NOT EXISTS source_rejected_attachment_evidence (
    source_id TEXT NOT NULL,
    evidence_id TEXT NOT NULL UNIQUE,
    attachment_id TEXT NOT NULL,
    filename TEXT NOT NULL,
    content_type TEXT,
    declared_size INTEGER NOT NULL CHECK(declared_size >= 0),
    capture_status TEXT NOT NULL CHECK(capture_status='skipped_rejected'),
    byte_size INTEGER CHECK(byte_size IS NULL OR byte_size >= 0),
    sha256 TEXT,
    managed_path TEXT,
    omitted_count INTEGER NOT NULL DEFAULT 0 CHECK(omitted_count >= 0),
    PRIMARY KEY(source_id,attachment_id),
    FOREIGN KEY(source_id) REFERENCES source_rejected(id)
);
CREATE INDEX IF NOT EXISTS source_rejected_attachment_evidence_source
    ON source_rejected_attachment_evidence(source_id,attachment_id);
""",
)


def _serialize(event: RawMessage) -> tuple[str, str]:
    payload = json.dumps(event.model_dump(mode="json"), sort_keys=True, ensure_ascii=False)
    return payload, hashlib.sha256(payload.encode()).hexdigest()


def _time() -> dt.datetime:
    return dt.datetime.now(dt.UTC)


def _insert_source_event_evidence(
    db: sqlite3.Connection,
    *,
    source_id: str,
    accepted: bool,
    event_payload: str | None,
    capture_status: str,
    payload_bytes: int,
    captured_at: str,
) -> None:
    db.execute(
        "INSERT INTO source_event_evidence "
        "(source_id,accepted,event_payload,capture_status,payload_bytes,captured_at) "
        "VALUES (?,?,?,?,?,?)",
        (source_id, int(accepted), event_payload, capture_status, payload_bytes, captured_at),
    )


def _insert_attachment_evidence(
    db: sqlite3.Connection,
    *,
    source_id: str,
    references: Sequence[AttachmentReference],
    omitted_count: int,
) -> None:
    for reference in references:
        initial: AttachmentStatus = "pending"
        if not reference.url:
            initial = "missing"
        elif reference.declared_size > 1024 * 1024:
            initial = "oversize"
        db.execute(
            "INSERT INTO source_attachment_evidence "
            "(source_id,evidence_id,attachment_id,filename,content_type,declared_size,"
            "capture_status) "
            "VALUES (?,?,?,?,?,?,?)",
            (
                source_id,
                uuid4().hex,
                reference.attachment_id,
                reference.filename,
                reference.content_type,
                max(0, reference.declared_size),
                initial,
            ),
        )
    if omitted_count:
        db.execute(
            "INSERT INTO source_attachment_evidence "
            "(source_id,evidence_id,attachment_id,filename,declared_size,capture_status,"
            "omitted_count) "
            "VALUES (?,?,?, ?,0,'count_exceeded',?)",
            (source_id, uuid4().hex, OMITTED_ATTACHMENT_ID, "", omitted_count),
        )


def _insert_rejected_attachment_evidence(
    db: sqlite3.Connection,
    *,
    source_id: str,
    references: Sequence[AttachmentReference],
    omitted_count: int,
) -> None:
    for reference in references:
        db.execute(
            "INSERT INTO source_rejected_attachment_evidence "
            "(source_id,evidence_id,attachment_id,filename,content_type,declared_size,"
            "capture_status) VALUES (?,?,?,?,?,?,'skipped_rejected')",
            (
                source_id,
                uuid4().hex,
                reference.attachment_id,
                reference.filename,
                reference.content_type,
                max(0, reference.declared_size),
            ),
        )
    if omitted_count:
        db.execute(
            "INSERT INTO source_rejected_attachment_evidence "
            "(source_id,evidence_id,attachment_id,filename,declared_size,capture_status,"
            "omitted_count) VALUES (?,?,?,'',0,'skipped_rejected',?)",
            (source_id, uuid4().hex, OMITTED_ATTACHMENT_ID, omitted_count),
        )


@dataclass(frozen=True, slots=True)
class _Evidence:
    """A source event and its attachment references, bounded for storage."""

    original: JsonValue
    stored: str | None
    status: CaptureStatus
    size: int
    attachments: tuple[AttachmentReference, ...]
    omitted: int

    @classmethod
    def bound(cls, original: JsonValue, attachments: Sequence[AttachmentReference]) -> _Evidence:
        stored, status, size = bounded_source_event(original)
        references, omitted = bound_attachment_references(attachments)
        return cls(original, stored, status, size, references, omitted)


def _rejection_key(payload: Mapping[str, object]) -> str:
    return f"{payload['source']}:{payload['channel_id']}:{payload['id']}"


def _check_recovery_page(
    channel: str, events: list[RawMessage], rejected: list[RejectedCapture], last_id: int
) -> None:
    """A page holds only this channel's messages, and the cursor lands on the newest one."""
    observed: list[int] = []
    for event in events:
        if (
            event.source != "discord"
            or event.channel_id != channel
            or not event.id.isascii()
            or not event.id.isdecimal()
        ):
            raise ValueError("Recovery page contains a message from another source")
        observed.append(int(event.id))
    for capture in rejected:
        payload = capture.payload
        identity = payload.get("id")
        if (
            payload.get("source") != "discord"
            or payload.get("channel_id") != channel
            or not isinstance(identity, str)
            or not identity.isascii()
            or not identity.isdecimal()
        ):
            raise ValueError("Recovery page contains a rejection from another source")
        observed.append(int(identity))
    if not observed or max(observed) != last_id:
        raise ValueError("Recovery cursor must equal the highest observed message ID")


def _insert_capture(
    db: sqlite3.Connection,
    event: RawMessage,
    evidence: _Evidence,
    *,
    captured_at: dt.datetime,
    recovered: bool,
    mode: str,
    workflow_id: str,
    trace_id: str,
) -> bool:
    """Insert a capture and its evidence; False when the same content is already captured."""
    payload, digest = _serialize(event)
    if db.execute("SELECT 1 FROM source_rejected WHERE id=?", (event.identity,)).fetchone():
        raise SourceIdentityConflict("Source ID was previously rejected")
    old = db.execute("SELECT hash FROM source_captures WHERE id=?", (event.identity,)).fetchone()
    if old:
        if old[0] != digest:
            raise SourceIdentityConflict("Source ID reused with different payload")
        return False
    db.execute(
        "INSERT INTO source_captures"
        "(id,hash,payload,source_at,captured_at,recovered,mode,workflow_id,trace_id) "
        "VALUES (?,?,?,?,?,?,?,?,?)",
        (
            event.identity,
            digest,
            payload,
            event.timestamp.isoformat(),
            captured_at.isoformat(),
            int(recovered),
            mode,
            workflow_id,
            trace_id,
        ),
    )
    _insert_source_event_evidence(
        db,
        source_id=event.identity,
        accepted=True,
        event_payload=evidence.stored,
        capture_status=evidence.status,
        payload_bytes=evidence.size,
        captured_at=captured_at.isoformat(),
    )
    _insert_attachment_evidence(
        db,
        source_id=event.identity,
        references=evidence.attachments,
        omitted_count=evidence.omitted,
    )
    return True


def _insert_rejection(
    db: sqlite3.Connection,
    event: dict[str, JsonValue],
    reason: str,
    evidence: _Evidence,
    *,
    rejected_at: dt.datetime,
) -> bool:
    """Insert a rejection and its evidence; False when the same input is already rejected."""
    key = _rejection_key(event)
    payload = json.dumps(event, sort_keys=True, ensure_ascii=False)
    digest = hashlib.sha256(payload.encode()).hexdigest()
    if db.execute("SELECT 1 FROM source_captures WHERE id=?", (key,)).fetchone():
        raise SourceIdentityConflict("Source ID was previously captured")
    old = db.execute("SELECT hash FROM source_rejected WHERE id=?", (key,)).fetchone()
    if old:
        if old[0] != digest:
            raise SourceIdentityConflict("Rejected source ID reused with different payload")
        return False
    db.execute(
        "INSERT INTO source_rejected VALUES (?,?,?,?,?)",
        (key, digest, payload, reason, rejected_at.isoformat()),
    )
    _insert_source_event_evidence(
        db,
        source_id=key,
        accepted=False,
        event_payload=evidence.stored,
        capture_status=evidence.status,
        payload_bytes=evidence.size,
        captured_at=rejected_at.isoformat(),
    )
    _insert_rejected_attachment_evidence(
        db, source_id=key, references=evidence.attachments, omitted_count=evidence.omitted
    )
    return True


class SQLiteSourceStore:
    def __init__(
        self,
        unit: SQLiteUnit,
        path: Path,
        diagnostics: PayloadCapture | None = None,
        attachment_transport: httpx.AsyncBaseTransport | None = None,
        on_captured: Callable[[], None] | None = None,
    ) -> None:
        self._unit = unit
        self._attachment_root = path.parent / "attachments"
        self._diagnostics = diagnostics
        self._attachment_transport = attachment_transport
        self._on_captured = on_captured

    @classmethod
    async def open(
        cls,
        path: Path,
        *,
        diagnostics: PayloadCapture | None = None,
        attachment_transport: httpx.AsyncBaseTransport | None = None,
        on_captured: Callable[[], None] | None = None,
    ) -> SQLiteSourceStore:
        unit = await SQLiteUnit.open(path)
        try:
            await unit.run(
                lambda db: ensure_schema(db, SOURCE_SCHEMA),
                write=True,
            )
            await unit.run(
                lambda db: ensure_schema(db, REJECTED_ATTACHMENT_SCHEMA),
                write=True,
            )
            await unit.run(
                lambda db: db.execute(
                    "UPDATE source_attachment_evidence SET capture_status='download_failed' "
                    "WHERE capture_status='pending'"
                ),
                write=True,
            )
        except BaseException:
            await unit.close()
            raise
        return cls(unit, path, diagnostics, attachment_transport, on_captured)

    async def add(
        self,
        event: RawMessage,
        *,
        source_event: JsonValue | None = None,
        attachments: Sequence[AttachmentReference] = (),
    ) -> None:
        """Capture a live message once; a replay with the same content is a no-op."""
        evidence = _Evidence.bound(
            source_event if source_event is not None else normalized_source_event(event),
            attachments,
        )
        workflow_id, trace_id = uuid4().hex, uuid4().hex
        inserted = await self._unit.run(
            lambda db: _insert_capture(
                db,
                event,
                evidence,
                captured_at=_time(),
                recovered=False,
                mode="live",
                workflow_id=workflow_id,
                trace_id=trace_id,
            ),
            write=True,
        )
        if inserted:
            if self._on_captured is not None:
                # Wake the processing loop now instead of on its next tick.
                self._on_captured()
            await self._emit_capture(event.identity, evidence, workflow_id, trace_id)

    async def reject(
        self,
        event: dict[str, JsonValue],
        reason: str,
        *,
        source_event: JsonValue | None = None,
        attachments: Sequence[AttachmentReference] = (),
    ) -> None:
        """Retain a rejected input whole, with the reason it was not captured."""
        evidence = _Evidence.bound(source_event if source_event is not None else event, attachments)
        inserted = await self._unit.run(
            lambda db: _insert_rejection(db, event, reason, evidence, rejected_at=_time()),
            write=True,
        )
        if inserted:
            self._emit_rejection(evidence)

    async def recovery_start(self, channel_id: int, fallback_id: int) -> RecoveryStart:
        channel = str(channel_id)

        def start(db: sqlite3.Connection) -> RecoveryStart:
            row = db.execute(
                "SELECT last_id,bootstrap FROM source_cursors WHERE channel_id=?", (channel,)
            ).fetchone()
            if row:
                return RecoveryStart(int(row[0]), _stored_bootstrap(row[1]))
            rows = db.execute(
                "SELECT id FROM source_captures WHERE id LIKE ? UNION ALL "
                "SELECT id FROM source_rejected WHERE id LIKE ?",
                (f"discord:{channel}:%", f"discord:{channel}:%"),
            ).fetchall()
            ids = [
                int(value.rsplit(":", 1)[1])
                for (value,) in rows
                if value.rsplit(":", 1)[1].isascii() and value.rsplit(":", 1)[1].isdecimal()
            ]
            earliest = min(ids) if ids else None
            bootstrap: Bootstrap = "earliest_retained" if earliest is not None else "recent_only"
            last_id = earliest - 1 if earliest is not None else fallback_id
            db.execute(
                "INSERT INTO source_cursors VALUES (?,?,?,?)",
                (channel, last_id, bootstrap, _time().isoformat()),
            )
            return RecoveryStart(last_id, bootstrap)

        return await self._unit.run(start, write=True)

    async def capture_recovery_page(
        self,
        channel_id: int,
        events: list[RawMessage],
        rejected: list[RejectedCapture],
        last_id: int,
        *,
        source_events: Mapping[str, JsonValue] | None = None,
        attachments: Mapping[str, Sequence[AttachmentReference]] | None = None,
    ) -> None:
        """Capture one page of history and advance the channel cursor in one transaction."""
        channel = str(channel_id)
        _check_recovery_page(channel, events, rejected, last_id)
        source_events = source_events or {}
        attachments = attachments or {}
        accepted = {
            event.identity: _Evidence.bound(
                source_events.get(event.identity, normalized_source_event(event)),
                attachments.get(event.identity, ()),
            )
            for event in events
        }
        refused = {
            _rejection_key(capture.payload): _Evidence.bound(
                source_events.get(_rejection_key(capture.payload), plain_json(capture.payload)),
                attachments.get(_rejection_key(capture.payload), ()),
            )
            for capture in rejected
        }

        def save(
            db: sqlite3.Connection,
        ) -> tuple[tuple[tuple[str, str, str], ...], tuple[str, ...]]:
            row = db.execute(
                "SELECT last_id FROM source_cursors WHERE channel_id=?", (channel,)
            ).fetchone()
            if row is None or int(row[0]) > last_id:
                raise RuntimeError("Recovery cursor did not advance")
            assigned_at = _time()
            captured: list[tuple[str, str, str]] = []
            for event in events:
                workflow_id, trace_id = uuid4().hex, uuid4().hex
                if _insert_capture(
                    db,
                    event,
                    accepted[event.identity],
                    captured_at=assigned_at,
                    recovered=True,
                    mode=delivery_mode(
                        recovered=True, source_at=event.timestamp, assigned_at=assigned_at
                    ),
                    workflow_id=workflow_id,
                    trace_id=trace_id,
                ):
                    captured.append((event.identity, workflow_id, trace_id))
            newly_refused: list[str] = []
            for capture in rejected:
                key = _rejection_key(capture.payload)
                payload = cast(dict[str, JsonValue], plain_json(capture.payload))
                if _insert_rejection(
                    db, payload, capture.reason, refused[key], rejected_at=assigned_at
                ):
                    newly_refused.append(key)
            db.execute(
                "UPDATE source_cursors SET last_id=?,updated_at=? WHERE channel_id=?",
                (last_id, assigned_at.isoformat(), channel),
            )
            return tuple(captured), tuple(newly_refused)

        captured, newly_refused = await self._unit.run(save, write=True)
        for identity, workflow_id, trace_id in captured:
            await self._emit_capture(identity, accepted[identity], workflow_id, trace_id)
        for key in newly_refused:
            self._emit_rejection(refused[key])

    async def claim_batch(self, limit: int = 100) -> tuple[Delivery, ...]:
        if limit < 1:
            raise ValueError("Delivery limit must be positive")

        def claim(db: sqlite3.Connection) -> tuple[Delivery, ...]:
            rows = db.execute(
                "SELECT id,payload,mode FROM source_captures WHERE mode='live' "
                "AND confirmed=0 AND assigned_seq IS NOT NULL ORDER BY assigned_seq LIMIT ?",
                (limit,),
            ).fetchall()
            if not rows:
                fresh = db.execute(
                    "SELECT id FROM source_captures WHERE mode='live' AND assigned_seq IS NULL "
                    "ORDER BY source_at,seq LIMIT ?",
                    (limit,),
                ).fetchall()
                next_seq = db.execute(
                    "SELECT COALESCE(MAX(assigned_seq),0) FROM source_captures"
                ).fetchone()[0]
                for index, (key,) in enumerate(fresh, 1):
                    db.execute(
                        "UPDATE source_captures SET assigned_seq=? WHERE id=?",
                        (next_seq + index, key),
                    )
                rows = db.execute(
                    "SELECT id,payload,mode FROM source_captures WHERE mode='live' "
                    "AND confirmed=0 AND assigned_seq IS NOT NULL ORDER BY assigned_seq LIMIT ?",
                    (limit,),
                ).fetchall()
            return tuple(Delivery(*row) for row in rows)

        return await self._unit.run(claim, write=True)

    async def confirm(self, key: str) -> None:
        await self._unit.run(
            lambda db: db.execute("UPDATE source_captures SET confirmed=1 WHERE id=?", (key,)),
            write=True,
        )

    async def recovery_progress(self) -> tuple[RecoveryProgress, ...]:
        def read(db: sqlite3.Connection) -> tuple[RecoveryProgress, ...]:
            rows = db.execute(
                "SELECT channel_id,last_id,bootstrap,updated_at "
                "FROM source_cursors ORDER BY channel_id"
            ).fetchall()
            return tuple(
                RecoveryProgress(c, int(i), _stored_bootstrap(b), dt.datetime.fromisoformat(t))
                for c, i, b, t in rows
            )

        return await self._unit.run(read)

    async def pending_count(self) -> int:
        return await self._unit.run(
            lambda db: db.execute(
                "SELECT count(*) FROM source_captures WHERE mode='live' AND confirmed=0"
            ).fetchone()[0]
        )

    async def pending_snapshot(self) -> QueueSnapshot:
        def read(db: sqlite3.Connection) -> QueueSnapshot:
            count, oldest = db.execute(
                "SELECT count(*),min(captured_at) FROM source_captures "
                "WHERE mode='live' AND confirmed=0"
            ).fetchone()
            return QueueSnapshot(count, dt.datetime.fromisoformat(oldest) if oldest else None, 0)

        return await self._unit.run(read)

    async def rejected_count(self) -> int:
        return await self._unit.run(
            lambda db: db.execute("SELECT count(*) FROM source_rejected").fetchone()[0]
        )

    async def attachment_evidence(self, source_id: str) -> tuple[SourceAttachmentEvidence, ...]:
        def read(db: sqlite3.Connection) -> tuple[SourceAttachmentEvidence, ...]:
            rows = db.execute(
                "SELECT evidence_id,attachment_id,filename,content_type,declared_size,"
                "capture_status,"
                "byte_size,sha256,managed_path,omitted_count "
                "FROM source_attachment_evidence WHERE source_id=? "
                "UNION ALL "
                "SELECT evidence_id,attachment_id,filename,content_type,declared_size,"
                "capture_status,byte_size,sha256,managed_path,omitted_count "
                "FROM source_rejected_attachment_evidence WHERE source_id=? "
                "ORDER BY attachment_id",
                (source_id, source_id),
            ).fetchall()
            return tuple(
                SourceAttachmentEvidence(
                    evidence_id=row[0],
                    attachment_id=row[1],
                    filename=row[2],
                    content_type=row[3],
                    declared_size=int(row[4]),
                    status=_stored_attachment_status(row[5]),
                    byte_size=int(row[6]) if row[6] is not None else None,
                    sha256=row[7],
                    managed_path=row[8],
                    omitted_count=int(row[9]),
                )
                for row in rows
            )

        return await self._unit.run(read)

    async def read_attachment(self, evidence_id: str) -> bytes:
        """Return only stored evidence addressed by its opaque source-owned reference."""
        if not is_evidence_id(evidence_id):
            raise ValueError("attachment_evidence_unavailable")
        row = await self._unit.run(
            lambda db: db.execute(
                "SELECT managed_path,sha256,byte_size FROM source_attachment_evidence "
                "WHERE evidence_id=? AND capture_status='available'",
                (evidence_id,),
            ).fetchone()
        )
        if row is None or row[0] is None or row[1] is None or row[2] is None:
            raise ValueError("attachment_evidence_unavailable")
        try:
            return await asyncio.to_thread(
                read_managed_content,
                self._attachment_root,
                row[0],
                expected_digest=row[1],
                expected_size=int(row[2]),
            )
        except OSError, ValueError:
            raise ValueError("attachment_evidence_unavailable") from None

    async def close(self) -> None:
        await self._unit.close()

    async def _capture_attachment_rows(
        self,
        source_id: str,
        references: Sequence[AttachmentReference],
    ) -> None:
        if not references:
            return
        try:
            outcomes = await capture_attachments(
                references,
                self._attachment_root,
                transport=self._attachment_transport,
            )
        except asyncio.CancelledError:
            raise
        except Exception:  # noqa: BLE001 - attachment failures are recorded per reference
            outcomes = tuple(AttachmentCaptureResult("download_failed") for _ in references)
        for reference, result in zip(references, outcomes, strict=True):
            await self._unit.run(
                lambda db, reference=reference, result=result: db.execute(
                    "UPDATE source_attachment_evidence SET capture_status=?,byte_size=?,"
                    "sha256=?,managed_path=? WHERE source_id=? AND attachment_id=?",
                    (
                        result.status,
                        result.byte_size,
                        result.sha256,
                        result.managed_path,
                        source_id,
                        reference.attachment_id,
                    ),
                ),
                write=True,
            )

    async def _emit_capture(
        self, identity: str, evidence: _Evidence, workflow_id: str, trace_id: str
    ) -> None:
        self._record_source_event(
            evidence.original,
            workflow_id=workflow_id,
            trace_id=trace_id,
            status=evidence.status,
            source_bytes=evidence.size,
        )
        await self._capture_attachment_rows(identity, evidence.attachments)

    def _emit_rejection(self, evidence: _Evidence) -> None:
        self._record_source_event(
            evidence.original,
            workflow_id=None,
            trace_id=None,
            status=evidence.status,
            source_bytes=evidence.size,
        )

    def _record_source_event(
        self,
        payload: JsonValue,
        *,
        workflow_id: str | None,
        trace_id: str | None,
        status: CaptureStatus = "complete",
        source_bytes: int | None = None,
    ) -> None:
        if self._diagnostics is None:
            return
        if source_bytes is None:
            serialized = json.dumps(payload, ensure_ascii=False, separators=(",", ":"))
            source_bytes = len(serialized.encode("utf-8"))
        try:
            self._diagnostics.record_payload(
                capture_kind="source_event",
                workflow_id=workflow_id,
                trace_id=trace_id,
                destination_id=None,
                attempt=None,
                provider="other",
                payload=payload,
                source_bytes=source_bytes,
                status=status,
            )
        except Exception:  # noqa: BLE001 - diagnostics must not alter the operational result
            # Source commits are operational; diagnostics can only report a gap.
            return


_BOOTSTRAP: TypeAdapter[Bootstrap] = TypeAdapter(Bootstrap)
_ATTACHMENT_STATUS: TypeAdapter[AttachmentStatus] = TypeAdapter(AttachmentStatus)


def _stored_bootstrap(value: object) -> Bootstrap:
    """A cursor row read from disk is checked before it steers history recovery."""
    return _BOOTSTRAP.validate_python(value, strict=True)


def _stored_attachment_status(value: object) -> AttachmentStatus:
    """An evidence row read from disk is checked before it reaches operator views."""
    return _ATTACHMENT_STATUS.validate_python(value, strict=True)
