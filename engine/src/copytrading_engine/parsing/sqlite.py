"""SQLite parser inbox, request budget, diagnostics and atomic decision outboxes."""

import datetime as dt
import hashlib
import json
import sqlite3
from contextlib import closing
from pathlib import Path
from uuid import uuid4

from pydantic import TypeAdapter

from copytrading_engine.parsing.contracts import (
    DestinationIdentity,
    DestinationRegistration,
    ExtractionJob,
    PendingSignal,
    RequestReservation,
)
from copytrading_engine.parsing.diagnostics import ValidationIssue
from copytrading_engine.parsing.history import PastCall
from copytrading_engine.parsing.notifications import decision_notification
from copytrading_engine.shared.notification_models import NotificationIntent, NotificationPayload
from copytrading_engine.shared.queue_snapshot import QueueSnapshot
from copytrading_engine.shared.raw_message import RawMessage
from copytrading_engine.shared.signals import Instruction, SourceIdentityConflict, StockSignal
from copytrading_engine.shared.sqlite import SchemaComponent, SQLiteUnit, ensure_schema

PARSER_SCHEMA = SchemaComponent(
    "parser",
    2,
    """
CREATE TABLE IF NOT EXISTS parser_inbox (
    seq INTEGER PRIMARY KEY AUTOINCREMENT,
    id TEXT NOT NULL UNIQUE,
    source TEXT NOT NULL,
    channel_id TEXT NOT NULL,
    hash TEXT NOT NULL,
    payload TEXT NOT NULL,
    attempts INTEGER NOT NULL DEFAULT 0,
    retry_at REAL NOT NULL DEFAULT 0,
    result TEXT,
    enqueued_at TEXT NOT NULL,
    completed_at TEXT
);
CREATE TABLE IF NOT EXISTS parser_workflows (
    message_id TEXT PRIMARY KEY REFERENCES parser_inbox(id),
    workflow_id TEXT NOT NULL UNIQUE,
    trace_id TEXT NOT NULL UNIQUE,
    created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS parser_destinations (
    message_id TEXT NOT NULL REFERENCES parser_inbox(id),
    account_id TEXT NOT NULL,
    destination_id TEXT NOT NULL UNIQUE,
    configuration_revision TEXT NOT NULL,
    attempts INTEGER NOT NULL DEFAULT 0 CHECK(attempts >= 0),
    PRIMARY KEY(message_id, account_id)
);
CREATE INDEX IF NOT EXISTS parser_inbox_waiting ON parser_inbox(seq) WHERE result IS NULL;
CREATE TABLE IF NOT EXISTS parser_requests (day TEXT PRIMARY KEY, count INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS parser_diagnostics (
    message_id TEXT NOT NULL REFERENCES parser_inbox(id),
    attempt INTEGER NOT NULL,
    at TEXT NOT NULL,
    reason TEXT NOT NULL,
    issues TEXT NOT NULL,
    PRIMARY KEY(message_id,attempt)
);
CREATE TABLE IF NOT EXISTS parser_signal_deliveries (
    message_id TEXT PRIMARY KEY REFERENCES parser_inbox(id),
    result TEXT NOT NULL,
    delivered_at TEXT
);
CREATE TABLE IF NOT EXISTS parser_notifications (
    message_id TEXT PRIMARY KEY REFERENCES parser_inbox(id),
    stream_id TEXT NOT NULL,
    payload TEXT NOT NULL,
    delivered_at TEXT
);
""",
)


# The owner's corrections of what a post said, which the reader's history prefers to its own
# reading (ADR-0010). Its own component, so adding it leaves the parser's revision as it was.
PARSER_CORRECTIONS_SCHEMA = SchemaComponent(
    "parser_corrections",
    1,
    """
CREATE TABLE IF NOT EXISTS parser_corrections (
    message_id TEXT PRIMARY KEY REFERENCES parser_inbox(id),
    instructions TEXT NOT NULL,
    recorded_at TEXT NOT NULL
);
""",
)

# How many of a channel's latest posts the reader's history is replayed from.
HISTORY_POSTS = 300

_INSTRUCTIONS = TypeAdapter(tuple[Instruction, ...])


def record_owner_correction(
    database: Path, source_id: str, instructions: tuple[Instruction, ...], at: dt.datetime
) -> None:
    """Keep the owner's latest reading of a post, which the guru's history then uses."""
    _aware(at)
    with closing(sqlite3.connect(database, timeout=5, isolation_level=None)) as db:
        ensure_schema(db, PARSER_CORRECTIONS_SCHEMA)
        db.execute(
            "INSERT INTO parser_corrections(message_id,instructions,recorded_at) VALUES (?,?,?) "
            "ON CONFLICT(message_id) DO UPDATE SET "
            "instructions=excluded.instructions,recorded_at=excluded.recorded_at",
            (source_id, _INSTRUCTIONS.dump_json(instructions).decode(), at.isoformat()),
        )


def _past_calls(
    rows: list[tuple[str, str, str | None]],
) -> tuple[PastCall, ...]:
    """The calls a channel's posts made: the owner's correction where there is one, otherwise
    each post the engine traded."""
    calls: list[PastCall] = []
    for key, result, corrected in rows:
        signal = StockSignal.model_validate_json(result)
        if corrected is not None:
            instructions = _INSTRUCTIONS.validate_json(corrected)
        elif signal.decision == "trade":
            instructions = signal.instructions
        else:
            continue
        calls.extend(
            PastCall(source_key=key, index=index, at=signal.timestamp, instruction=instruction)
            for index, instruction in enumerate(instructions)
        )
    return tuple(calls)


def _aware(now: dt.datetime) -> None:
    if now.tzinfo is None or now.utcoffset() is None:
        raise ValueError("Parser time must be timezone-aware")


class SQLiteExtractionStore:
    def __init__(self, unit: SQLiteUnit) -> None:
        self._unit = unit

    @classmethod
    async def open(cls, path: Path) -> SQLiteExtractionStore:
        unit = await SQLiteUnit.open(path)
        try:
            await unit.run(
                lambda db: (
                    ensure_schema(db, PARSER_SCHEMA),
                    ensure_schema(db, PARSER_CORRECTIONS_SCHEMA),
                ),
                write=True,
            )
        except BaseException:
            await unit.close()
            raise
        return cls(unit)

    async def add(self, event: RawMessage) -> None:
        key = event.identity
        payload = json.dumps(event.model_dump(mode="json"), sort_keys=True, ensure_ascii=False)
        digest = hashlib.sha256(payload.encode()).hexdigest()
        workflow_id = uuid4().hex
        trace_id = uuid4().hex

        def save(db: sqlite3.Connection) -> None:
            row = db.execute("SELECT hash FROM parser_inbox WHERE id=?", (key,)).fetchone()
            if row:
                if row[0] != digest:
                    raise SourceIdentityConflict("Source ID reused with a different payload")
                return
            source_lineage = None
            source_store_exists = db.execute(
                "SELECT 1 FROM sqlite_master WHERE type='table' AND name='source_captures'"
            ).fetchone()
            if source_store_exists:
                source_lineage = db.execute(
                    "SELECT workflow_id,trace_id FROM source_captures WHERE id=?", (key,)
                ).fetchone()
            saved_workflow_id, saved_trace_id = (
                (source_lineage[0], source_lineage[1])
                if source_lineage is not None
                else (workflow_id, trace_id)
            )
            db.execute(
                "INSERT INTO parser_inbox(id,source,channel_id,hash,payload,enqueued_at) "
                "VALUES (?,?,?,?,?,?)",
                (
                    key,
                    event.source,
                    event.channel_id,
                    digest,
                    payload,
                    dt.datetime.now(dt.UTC).isoformat(),
                ),
            )
            db.execute(
                "INSERT INTO parser_workflows(message_id,workflow_id,trace_id,created_at) "
                "VALUES (?,?,?,?)",
                (
                    key,
                    saved_workflow_id,
                    saved_trace_id,
                    dt.datetime.now(dt.UTC).isoformat(),
                ),
            )

        await self._unit.run(save, write=True)

    async def next(self, now: dt.datetime) -> ExtractionJob | None:
        _aware(now)

        def read(db: sqlite3.Connection) -> ExtractionJob | None:
            row = db.execute(
                "SELECT current.id,current.payload,current.attempts,workflow.workflow_id,"
                "workflow.trace_id FROM parser_inbox current JOIN parser_workflows workflow "
                "ON workflow.message_id=current.id "
                "WHERE current.result IS NULL AND current.retry_at<=? AND NOT EXISTS ("
                "SELECT 1 FROM parser_inbox prior WHERE prior.result IS NULL "
                "AND prior.seq<current.seq AND prior.source=current.source "
                "AND prior.channel_id=current.channel_id) ORDER BY current.seq LIMIT 1",
                (now.timestamp(),),
            ).fetchone()
            return (
                None
                if row is None
                else ExtractionJob(
                    row[0], RawMessage.model_validate_json(row[1]), row[2], row[3], row[4]
                )
            )

        return await self._unit.run(read)

    async def reserve(self, request: RequestReservation) -> bool:
        _aware(request.retry_at)
        if request.daily_limit < 0 or request.expected_attempts < 0:
            raise ValueError("Invalid parser request reservation")

        def save(db: sqlite3.Connection) -> bool:
            row = db.execute(
                "SELECT attempts,result FROM parser_inbox WHERE id=?", (request.key,)
            ).fetchone()
            if row is None:
                raise ValueError("Cannot reserve an unknown source message")
            if row[0] != request.expected_attempts or row[1] is not None:
                raise ValueError("Cannot reserve with stale extraction attempts")
            day = request.day.isoformat()
            db.execute("INSERT OR IGNORE INTO parser_requests VALUES (?,0)", (day,))
            count = db.execute("SELECT count FROM parser_requests WHERE day=?", (day,)).fetchone()[
                0
            ]
            if count >= request.daily_limit:
                return False
            db.execute("UPDATE parser_requests SET count=count+1 WHERE day=?", (day,))
            updated = db.execute(
                "UPDATE parser_inbox SET attempts=attempts+1,retry_at=? "
                "WHERE id=? AND attempts=? AND result IS NULL",
                (request.retry_at.timestamp(), request.key, request.expected_attempts),
            )
            if updated.rowcount != 1:
                raise ValueError("Cannot reserve with stale extraction attempts")
            return True

        return await self._unit.run(save, write=True)

    async def prepare_destinations(
        self,
        key: str,
        registrations: tuple[DestinationRegistration, ...],
    ) -> tuple[DestinationIdentity, ...]:
        """Commit stable route identities for every account before any account receipt."""
        accounts = tuple(sorted(registrations, key=lambda item: item.account_id))
        if len({item.account_id for item in accounts}) != len(accounts):
            raise ValueError("A workflow cannot route to the same account twice")
        generated = {item.account_id: uuid4().hex for item in accounts}

        def save(db: sqlite3.Connection) -> tuple[DestinationIdentity, ...]:
            workflow = db.execute(
                "SELECT workflow_id,trace_id FROM parser_workflows WHERE message_id=?", (key,)
            ).fetchone()
            if workflow is None:
                raise ValueError("Cannot route a workflow without persisted lineage")
            existing = db.execute(
                "SELECT account_id,configuration_revision FROM parser_destinations "
                "WHERE message_id=? ORDER BY account_id",
                (key,),
            ).fetchall()
            expected = [(item.account_id, item.configuration_revision) for item in accounts]
            if existing and existing != expected:
                raise SourceIdentityConflict(
                    "Persisted workflow destinations differ from active route"
                )
            for item in accounts:
                db.execute(
                    "INSERT OR IGNORE INTO parser_destinations"
                    "(message_id,account_id,destination_id,configuration_revision) "
                    "VALUES (?,?,?,?)",
                    (key, item.account_id, generated[item.account_id], item.configuration_revision),
                )
            rows = db.execute(
                "SELECT message_id,account_id,destination_id,configuration_revision,attempts "
                "FROM parser_destinations WHERE message_id=? ORDER BY account_id",
                (key,),
            ).fetchall()
            return tuple(
                DestinationIdentity(
                    row[0], row[1], row[2], row[3], workflow[0], workflow[1], row[4]
                )
                for row in rows
            )

        return await self._unit.run(save, write=True)

    async def reserve_destination_attempt(self, key: str, account_id: str) -> DestinationIdentity:
        """Persist one destination retry admission before calling its account owner."""

        def save(db: sqlite3.Connection) -> DestinationIdentity:
            row = db.execute(
                "SELECT destination.message_id,destination.account_id,destination.destination_id,"
                "destination.configuration_revision,destination.attempts,workflow.workflow_id,"
                "workflow.trace_id FROM parser_destinations destination "
                "JOIN parser_workflows workflow "
                "ON workflow.message_id=destination.message_id "
                "WHERE destination.message_id=? AND destination.account_id=?",
                (key, account_id),
            ).fetchone()
            if row is None:
                raise ValueError("Cannot admit an unregistered destination")
            changed = db.execute(
                "UPDATE parser_destinations SET attempts=attempts+1 "
                "WHERE message_id=? AND account_id=? AND destination_id=?",
                (key, account_id, row[2]),
            )
            if changed.rowcount != 1:
                raise RuntimeError("Destination attempt admission was lost")
            return DestinationIdentity(row[0], row[1], row[2], row[3], row[5], row[6], row[4] + 1)

        return await self._unit.run(save, write=True)

    async def finish(self, key: str, result: StockSignal) -> None:
        if key != f"{result.source}:{result.channel_id}:{result.id}":
            raise ValueError("Parser result identity differs from source")
        payload = result.model_dump_json()

        def save(db: sqlite3.Connection) -> None:
            row = db.execute("SELECT result FROM parser_inbox WHERE id=?", (key,)).fetchone()
            if row is None:
                raise ValueError("Cannot finish an unknown source message")
            if row[0] is not None:
                if row[0] != payload:
                    raise SourceIdentityConflict("Parser result differs from persisted decision")
                return
            completed_at = dt.datetime.now(dt.UTC)
            db.execute(
                "UPDATE parser_inbox SET result=?,completed_at=? WHERE id=? AND result IS NULL",
                (payload, completed_at.isoformat(), key),
            )
            db.execute(
                "INSERT INTO parser_signal_deliveries(message_id,result) VALUES (?,?)",
                (key, payload),
            )
            diagnostic = db.execute(
                "SELECT issues FROM parser_diagnostics WHERE message_id=? "
                "ORDER BY attempt DESC LIMIT 1",
                (key,),
            ).fetchone()
            issues = (
                tuple(ValidationIssue.model_validate(item) for item in json.loads(diagnostic[0]))
                if diagnostic
                else ()
            )
            notification = decision_notification(key, result, issues, observed_at=completed_at)
            notification_payload = json.dumps(
                {
                    "labels": dict(notification.payload.labels),
                    "annotations": dict(notification.payload.annotations),
                    "starts_at": notification.payload.starts_at.isoformat(),
                },
                ensure_ascii=False,
            )
            db.execute(
                "INSERT INTO parser_notifications(message_id,stream_id,payload) VALUES (?,?,?)",
                (key, notification.stream_id, notification_payload),
            )

        await self._unit.run(save, write=True)

    async def past_calls(self, channel_id: str, before: str) -> tuple[PastCall, ...]:
        """The calls the channel's guru made before the post `before`, newest posts first."""

        def read(db: sqlite3.Connection) -> tuple[PastCall, ...]:
            rows = db.execute(
                "SELECT inbox.id,inbox.result,correction.instructions FROM parser_inbox inbox "
                "LEFT JOIN parser_corrections correction ON correction.message_id=inbox.id "
                "WHERE inbox.channel_id=? AND inbox.result IS NOT NULL AND inbox.id<>? "
                "AND inbox.seq<(SELECT seq FROM parser_inbox WHERE id=?) "
                "ORDER BY inbox.seq DESC LIMIT ?",
                (channel_id, before, before, HISTORY_POSTS),
            ).fetchall()
            return _past_calls(rows)

        return await self._unit.run(read)

    async def diagnose(
        self,
        key: str,
        attempt: int,
        at: dt.datetime,
        reason: str,
        issues: tuple[ValidationIssue, ...],
    ) -> None:
        _aware(at)
        payload = json.dumps([issue.model_dump() for issue in issues])
        await self._unit.run(
            lambda db: db.execute(
                "INSERT OR IGNORE INTO parser_diagnostics VALUES (?,?,?,?,?)",
                (key, attempt, at.isoformat(), reason, payload),
            ),
            write=True,
        )

    async def claim_pending_signals(
        self, limit: int = 100, after_seq: int = 0
    ) -> tuple[PendingSignal, ...]:
        if limit < 1 or type(after_seq) is not int or after_seq < 0:
            raise ValueError("Delivery limit must be positive and cursor nonnegative")

        def read(db: sqlite3.Connection) -> tuple[PendingSignal, ...]:
            rows = db.execute(
                "SELECT inbox.seq,delivery.message_id,delivery.result "
                "FROM parser_signal_deliveries delivery "
                "JOIN parser_inbox inbox ON inbox.id=delivery.message_id "
                "WHERE delivery.delivered_at IS NULL AND inbox.seq>? "
                "ORDER BY inbox.seq LIMIT ?",
                (after_seq, limit),
            ).fetchall()
            return tuple(
                PendingSignal(key, StockSignal.model_validate_json(payload), seq)
                for seq, key, payload in rows
            )

        return await self._unit.run(read)

    async def pending_delivery_count(self) -> int:
        return await self._unit.run(
            lambda db: db.execute(
                "SELECT count(*) FROM parser_signal_deliveries WHERE delivered_at IS NULL"
            ).fetchone()[0]
        )

    async def pending_snapshot(self) -> QueueSnapshot:
        def read(db: sqlite3.Connection) -> QueueSnapshot:
            count, oldest = db.execute(
                "SELECT count(*),min(enqueued_at) FROM ("
                "SELECT enqueued_at FROM parser_inbox WHERE result IS NULL "
                "UNION ALL SELECT inbox.enqueued_at FROM parser_signal_deliveries delivery "
                "JOIN parser_inbox inbox ON inbox.id=delivery.message_id "
                "WHERE delivery.delivered_at IS NULL)"
            ).fetchone()
            return QueueSnapshot(count, dt.datetime.fromisoformat(oldest) if oldest else None, 0)

        return await self._unit.run(read)

    async def confirm_signal(self, key: str) -> None:
        await self._unit.run(
            lambda db: db.execute(
                "UPDATE parser_signal_deliveries "
                "SET delivered_at=COALESCE(delivered_at,?) WHERE message_id=?",
                (dt.datetime.now(dt.UTC).isoformat(), key),
            ),
            write=True,
        )

    async def claim_pending_notifications(self, limit: int = 100) -> tuple[NotificationIntent, ...]:
        if limit < 1:
            raise ValueError("Delivery limit must be positive")

        def read(db: sqlite3.Connection) -> tuple[NotificationIntent, ...]:
            rows = db.execute(
                "SELECT notifications.message_id,notifications.stream_id,notifications.payload "
                "FROM parser_notifications notifications JOIN parser_inbox inbox "
                "ON inbox.id=notifications.message_id WHERE notifications.delivered_at IS NULL "
                "ORDER BY inbox.seq LIMIT ?",
                (limit,),
            ).fetchall()
            return tuple(
                NotificationIntent(
                    key=key,
                    stream_id=stream_id,
                    payload=NotificationPayload(
                        labels=(data := json.loads(payload))["labels"],
                        annotations=data["annotations"],
                        starts_at=dt.datetime.fromisoformat(data["starts_at"]),
                    ),
                )
                for key, stream_id, payload in rows
            )

        return await self._unit.run(read)

    async def confirm_notification(self, key: str) -> None:
        await self._unit.run(
            lambda db: db.execute(
                "UPDATE parser_notifications "
                "SET delivered_at=COALESCE(delivered_at,?) WHERE message_id=?",
                (dt.datetime.now(dt.UTC).isoformat(), key),
            ),
            write=True,
        )

    async def pending_count(self) -> int:
        return await self._unit.run(
            lambda db: db.execute(
                "SELECT count(*) FROM parser_inbox WHERE result IS NULL"
            ).fetchone()[0]
        )

    async def close(self) -> None:
        await self._unit.close()
