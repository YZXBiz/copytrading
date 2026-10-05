"""Project committed source, parser and account evidence for the private UI."""

import datetime as dt
import json
import sqlite3
from contextlib import closing
from pathlib import Path
from typing import Literal

from copytrading_engine.execution.adapters.sqlite_ledger import (
    EXECUTION_SCHEMA,
    decode_ledger_snapshot,
)
from copytrading_engine.execution.domain.events import JournalEvent
from copytrading_engine.execution.domain.ledger_state import LedgerSnapshot
from copytrading_engine.execution.domain.manual_commands import ManualSourceEvidence
from copytrading_engine.execution.presentation.operator_views import (
    AccountEventPage,
    AccountOverview,
    DestinationView,
    account_overview,
    event_page,
)
from copytrading_engine.shared.queue_snapshot import QueueSnapshot
from copytrading_engine.shared.raw_message import RawMessage
from copytrading_engine.shared.signals import StockSignal
from copytrading_engine.trading.presentation.operator_models import (
    RejectedSourceActivity,
    SourceActivity,
    SourceActivityPage,
    SourceAttachmentEvidence,
    SourceEmbedEvidence,
    SourceEmbedField,
    SourceEventEvidence,
)


def _has_table(db: sqlite3.Connection, name: str) -> bool:
    row = db.execute(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", (name,)
    ).fetchone()
    return row is not None


def source_page(
    database: Path,
    *,
    before_seq: int | None,
    limit: int,
    destinations: dict[str, tuple[DestinationView, ...]],
) -> SourceActivityPage:
    if not 1 <= limit <= 100 or (before_seq is not None and before_seq < 1):
        raise ValueError("Invalid source activity page")
    if not database.exists():
        return SourceActivityPage(items=(), rejected_items=())
    with closing(sqlite3.connect(database.as_uri() + "?mode=ro", uri=True)) as db:
        # The self-test store creates the database before processing first opens the source store.
        if not _has_table(db, "source_captures"):
            return SourceActivityPage(items=(), rejected_items=())
        rows = db.execute(
            "SELECT capture.seq,capture.id,capture.payload,capture.source_at,"
            "capture.captured_at,capture.mode,capture.confirmed,parser.result,"
            "delivery.delivered_at,event.event_payload,event.capture_status,event.payload_bytes "
            "FROM source_captures capture LEFT JOIN parser_inbox parser ON parser.id=capture.id "
            "LEFT JOIN parser_signal_deliveries delivery ON delivery.message_id=capture.id "
            "LEFT JOIN source_event_evidence event ON event.source_id=capture.id "
            "WHERE (? IS NULL OR capture.seq < ?) ORDER BY capture.seq DESC LIMIT ?",
            (before_seq, before_seq, limit),
        ).fetchall()
        rejected_rows = db.execute(
            "SELECT rejected.id,rejected.payload,rejected.reason,rejected.rejected_at,"
            "event.event_payload,event.capture_status,event.payload_bytes "
            "FROM source_rejected rejected LEFT JOIN source_event_evidence event "
            "ON event.source_id=rejected.id ORDER BY rejected.rejected_at DESC,rejected.id DESC "
            "LIMIT ?",
            (limit,),
        ).fetchall()
        source_ids = tuple(row[1] for row in rows)
        attachment_rows = ()
        if source_ids:
            placeholders = ",".join("?" for _ in source_ids)
            attachment_rows = db.execute(
                "SELECT source_id,evidence_id,attachment_id,filename,content_type,declared_size,"
                "capture_status,byte_size,sha256,omitted_count "
                f"FROM source_attachment_evidence WHERE source_id IN ({placeholders}) "
                "ORDER BY source_id,attachment_id",
                source_ids,
            ).fetchall()
        rejected_ids = tuple(row[0] for row in rejected_rows)
        rejected_attachment_rows = ()
        if rejected_ids:
            placeholders = ",".join("?" for _ in rejected_ids)
            rejected_attachment_rows = db.execute(
                "SELECT source_id,evidence_id,attachment_id,filename,content_type,declared_size,"
                "capture_status,byte_size,sha256,omitted_count "
                f"FROM source_rejected_attachment_evidence WHERE source_id IN ({placeholders}) "
                "ORDER BY source_id,attachment_id",
                rejected_ids,
            ).fetchall()
    attachments_by_source: dict[str, list[SourceAttachmentEvidence]] = {
        source_id: [] for source_id in source_ids
    }
    for row in attachment_rows:
        attachments_by_source[row[0]].append(
            SourceAttachmentEvidence(
                evidence_id=row[1],
                attachment_id=row[2],
                filename=row[3],
                content_type=row[4],
                declared_size=int(row[5]),
                status=row[6],
                byte_size=int(row[7]) if row[7] is not None else None,
                sha256=row[8],
                omitted_count=int(row[9]),
            )
        )
    rejected_attachments_by_source: dict[str, list[SourceAttachmentEvidence]] = {
        source_id: [] for source_id in rejected_ids
    }
    for row in rejected_attachment_rows:
        rejected_attachments_by_source[row[0]].append(
            SourceAttachmentEvidence(
                evidence_id=row[1],
                attachment_id=row[2],
                filename=row[3],
                content_type=row[4],
                declared_size=int(row[5]),
                status=row[6],
                byte_size=int(row[7]) if row[7] is not None else None,
                sha256=row[8],
                omitted_count=int(row[9]),
            )
        )
    items = []
    for (
        seq,
        source_id,
        raw,
        source_at,
        captured_at,
        mode,
        confirmed,
        parsed,
        delivered_at,
        event_payload,
        event_status,
        event_bytes,
    ) in rows:
        source = RawMessage.model_validate_json(raw)
        decision = StockSignal.model_validate_json(parsed) if parsed else None
        source_event = _source_event_view(
            event_payload,
            _source_event_status(event_status or "missing"),
            int(event_bytes or 0),
            source.text,
            tuple(attachments_by_source[source_id]),
        )
        items.append(
            SourceActivity(
                sequence=seq,
                source_id=source_id,
                author_id=source.author_id,
                source_revision=source.schema_version,
                source_at=dt.datetime.fromisoformat(source_at),
                captured_at=dt.datetime.fromisoformat(captured_at),
                text=source.text,
                capture_status="historical"
                if mode == "historical"
                else "delivered"
                if confirmed
                else "pending",
                parse_status="complete"
                if decision
                else "pending"
                if mode == "live"
                else "not_applicable",
                delivery_status="delivered"
                if delivered_at
                else "pending"
                if parsed
                else "not_ready",
                decision=decision.decision if decision else None,
                parser_reason=decision.reason if decision else None,
                parser_profile=decision.parser_profile if decision else None,
                interpreted_by=decision.model if decision else None,
                instructions=decision.instructions if decision else (),
                suggested=decision.suggested if decision else (),
                guru_id=decision.guru_id if decision else None,
                profile_revision=decision.profile_revision if decision else None,
                source_event=source_event,
                destinations=destinations.get(source_id, ()),
            )
        )
    return SourceActivityPage(
        items=tuple(items),
        rejected_items=tuple(
            RejectedSourceActivity(
                source_id=row[0],
                rejected_at=dt.datetime.fromisoformat(row[3]),
                reason=row[2],
                source_event=_source_event_view(
                    row[4],
                    _source_event_status(row[5] or "missing"),
                    int(row[6] or 0),
                    _rejected_fallback_text(row[1]),
                    tuple(rejected_attachments_by_source[row[0]]),
                ),
            )
            for row in rejected_rows
        ),
        next_before_seq=items[-1].sequence if len(items) == limit else None,
    )


def _rejected_fallback_text(serialized: str) -> str:
    try:
        payload = json.loads(serialized)
    except json.JSONDecodeError, TypeError:
        return ""
    if not isinstance(payload, dict):
        return ""
    text = payload.get("text")
    return text if isinstance(text, str) else ""


def _source_event_view(
    serialized: str | None,
    capture_status: Literal["complete", "oversize", "missing"],
    payload_bytes: int,
    fallback_text: str,
    attachments: tuple[SourceAttachmentEvidence, ...],
) -> SourceEventEvidence:
    payload: dict[str, object] = {}
    if serialized is not None:
        try:
            decoded = json.loads(serialized)
            if isinstance(decoded, dict):
                payload = decoded
        except json.JSONDecodeError, TypeError:
            pass
    embeds: list[SourceEmbedEvidence] = []
    raw_embeds = payload.get("embeds")
    if isinstance(raw_embeds, list):
        for raw_embed in raw_embeds:
            if not isinstance(raw_embed, dict):
                continue
            fields: list[SourceEmbedField] = []
            raw_fields = raw_embed.get("fields")
            if isinstance(raw_fields, list):
                for raw_field in raw_fields:
                    if not isinstance(raw_field, dict):
                        continue
                    fields.append(
                        SourceEmbedField(
                            name=str(raw_field.get("name") or ""),
                            value=str(raw_field.get("value") or ""),
                            inline=bool(raw_field.get("inline", False)),
                        )
                    )
            title, description = raw_embed.get("title"), raw_embed.get("description")
            embeds.append(
                SourceEmbedEvidence(
                    title=title if isinstance(title, str) else None,
                    description=description if isinstance(description, str) else None,
                    fields=tuple(fields),
                )
            )
    content = payload.get("content")
    raw_omitted = payload.get("attachments_omitted", 0)
    omitted = int(raw_omitted) if type(raw_omitted) is int and raw_omitted >= 0 else 0
    omitted = max(omitted, *(item.omitted_count for item in attachments), 0)
    event_type = payload.get("event_type")
    message_id = payload.get("message_id")
    channel_id = payload.get("channel_id")
    author_id = payload.get("author_id")
    timestamp = payload.get("timestamp")
    return SourceEventEvidence(
        event_type=event_type if isinstance(event_type, str) else "unknown",
        message_id=message_id if isinstance(message_id, str) else None,
        channel_id=channel_id if isinstance(channel_id, str) else None,
        author_id=author_id if isinstance(author_id, str) else None,
        timestamp=timestamp if isinstance(timestamp, str) else None,
        content=content if isinstance(content, str) else fallback_text,
        embeds=tuple(embeds),
        attachments=attachments,
        attachments_omitted=omitted,
        capture_status=capture_status,
        payload_bytes=payload_bytes,
    )


def _source_event_status(value: str) -> Literal["complete", "oversize", "missing"]:
    if value == "complete":
        return "complete"
    if value == "oversize":
        return "oversize"
    if value == "missing":
        return "missing"
    raise ValueError("Persisted source event has an invalid capture status")


def manual_source_evidence(database: Path, source_id: str) -> ManualSourceEvidence:
    """Read a complete live source and accepted review parse without mutating it."""
    if not database.exists():
        raise ValueError("manual_source_unavailable")
    with closing(sqlite3.connect(database.as_uri() + "?mode=ro", uri=True)) as db:
        row = db.execute(
            "SELECT capture.seq,capture.payload,capture.source_at,capture.mode,"
            "capture.confirmed,parser.result "
            "FROM source_captures capture LEFT JOIN parser_inbox parser ON parser.id=capture.id "
            "WHERE capture.id=?",
            (source_id,),
        ).fetchone()
    if row is None:
        raise ValueError("manual_source_unavailable")
    source_revision, raw, source_at, mode, confirmed, parsed = row
    if mode != "live" or not confirmed or parsed is None:
        raise ValueError("manual_source_unavailable")
    source = RawMessage.model_validate_json(raw)
    signal = StockSignal.model_validate_json(parsed)
    if source.identity != source_id or signal.text != source.text:
        raise ValueError("manual_source_unavailable")
    return ManualSourceEvidence(
        source_id=source_id,
        source_revision=source_revision,
        source_at=dt.datetime.fromisoformat(source_at),
        text=source.text,
        accepted_interpretation=signal,
    )


def historical_source_message(database: Path, source_id: str) -> RawMessage:
    """Read the exact captured historical payload without changing its timestamp or mode."""
    if not database.exists() or not 1 <= len(source_id) <= 256:
        raise ValueError("historical_source_unavailable")
    with closing(sqlite3.connect(database.as_uri() + "?mode=ro", uri=True)) as db:
        row = db.execute(
            "SELECT payload,mode FROM source_captures WHERE id=?", (source_id,)
        ).fetchone()
    if row is None or row[1] != "historical":
        raise ValueError("historical_source_unavailable")
    try:
        source = RawMessage.model_validate_json(row[0])
    except ValueError:
        raise ValueError("historical_source_unavailable") from None
    if source.identity != source_id:
        raise ValueError("historical_source_unavailable")
    return source


def retained_account(
    path: Path, *, before_seq: int | None = None, limit: int = 50
) -> tuple[AccountOverview, LedgerSnapshot, AccountEventPage]:
    """Read retained evidence without binding another broker or account writer."""
    if not 1 <= limit <= 100 or (before_seq is not None and before_seq < 1):
        raise ValueError("Invalid account event page")
    with closing(sqlite3.connect(path.as_uri() + "?mode=ro", uri=True)) as db:
        revision = db.execute(
            "SELECT revision FROM copytrading_engine_schema_revisions WHERE component='execution'"
        ).fetchone()
        if revision != (EXECUTION_SCHEMA.revision,):
            raise RuntimeError("Unsupported retained execution schema revision")
        identity = db.execute(
            "SELECT environment,account_id FROM identity WHERE singleton=1"
        ).fetchone()
        row = db.execute("SELECT data FROM snapshot WHERE singleton=1").fetchone()
        if identity is None or row is None:
            raise RuntimeError("Retained account evidence is incomplete")
        snapshot = decode_ledger_snapshot(row[0])
        if (snapshot.environment, snapshot.account_id) != identity:
            raise RuntimeError("Retained account identity mismatch")
        pending, oldest = db.execute(
            "SELECT count(*),min(enqueued_at) FROM journal WHERE published=0"
        ).fetchone()
        queue = QueueSnapshot(pending, dt.datetime.fromisoformat(oldest) if oldest else None, 0)
        rows = db.execute(
            "SELECT id,event FROM journal WHERE (? IS NULL OR id < ?) ORDER BY id DESC LIMIT ?",
            (before_seq, before_seq, limit),
        ).fetchall()
    overview = account_overview(
        snapshot,
        None,
        queue,
        local_account_id=path.parent.name,
        active_configuration=False,
        readiness="inactive_evidence",
        balance=None,
    )
    events = event_page(
        path.parent.name,
        tuple((seq, JournalEvent.model_validate_json(raw)) for seq, raw in rows),
        limit,
    )
    return overview, snapshot, events


class SQLiteOperatorEvidence:
    """The OperatorEvidence port over read-only SQLite connections."""

    def source_page(
        self,
        database: Path,
        *,
        before_seq: int | None,
        limit: int,
        destinations: dict[str, tuple[DestinationView, ...]],
    ) -> SourceActivityPage:
        return source_page(database, before_seq=before_seq, limit=limit, destinations=destinations)

    def retained_account(
        self, path: Path, *, before_seq: int | None = None, limit: int = 50
    ) -> tuple[AccountOverview, LedgerSnapshot, AccountEventPage]:
        return retained_account(path, before_seq=before_seq, limit=limit)

    def manual_source_evidence(self, database: Path, source_id: str) -> ManualSourceEvidence:
        return manual_source_evidence(database, source_id)

    def historical_source_message(self, database: Path, source_id: str) -> RawMessage:
        return historical_source_message(database, source_id)
