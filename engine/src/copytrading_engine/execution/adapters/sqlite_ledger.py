"""Durable, account-scoped execution ledger and local notification outbox."""

import datetime as dt
import json
import sqlite3
from collections.abc import Iterator
from contextlib import contextmanager
from pathlib import Path

from copytrading_engine.execution.domain.events import JournalEvent
from copytrading_engine.execution.domain.ledger_state import LedgerSnapshot
from copytrading_engine.execution.domain.values import BrokerAccountNumber
from copytrading_engine.execution.presentation.notifications import execution_notification
from copytrading_engine.shared.notification_models import NotificationIntent
from copytrading_engine.shared.sqlite import SchemaComponent, ensure_schema

EXECUTION_SCHEMA = SchemaComponent(
    "execution",
    5,
    """
                CREATE TABLE IF NOT EXISTS identity (
                    singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
                    environment TEXT NOT NULL CHECK (environment IN ('paper', 'live')),
                    account_id TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS snapshot (
                    singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
                    data TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS journal (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    event TEXT NOT NULL,
                    published INTEGER NOT NULL DEFAULT 0 CHECK (published IN (0, 1)),
                    enqueued_at TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS journal_waiting ON journal(id) WHERE published=0;
                CREATE TABLE IF NOT EXISTS notifications (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    key TEXT NOT NULL UNIQUE,
                    stream_id TEXT NOT NULL,
                    payload TEXT NOT NULL,
                    attempts INTEGER NOT NULL DEFAULT 0,
                    retry_at REAL NOT NULL DEFAULT 0,
                    delivered_at REAL,
                    enqueued_at TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS notifications_waiting
                    ON notifications(id) WHERE delivered_at IS NULL;
                """,
)


def decode_ledger_snapshot(raw: str) -> LedgerSnapshot:
    """Decode the persisted snapshot row; its format version and control must be explicit."""
    payload = json.loads(raw)
    if not isinstance(payload, dict) or type(payload.get("schema_version")) is not int:
        raise RuntimeError("Execution snapshot schema version is missing")
    if payload["schema_version"] != LedgerSnapshot.model_fields["schema_version"].default:
        raise ValueError("Unsupported execution snapshot schema version")
    if "control" not in payload:
        raise ValueError("Execution snapshot is missing account control evidence")
    return LedgerSnapshot.model_validate_json(raw)


class CurrentExecutionSnapshotSchema:
    """Expose authoritative execution and snapshot schema metadata to outer services."""

    @property
    def execution_schema_revision(self) -> int:
        return EXECUTION_SCHEMA.revision

    @property
    def snapshot_json_schema_version(self) -> int:
        version = LedgerSnapshot.model_fields["schema_version"].default
        if type(version) is not int:
            raise RuntimeError("Execution snapshot schema version is invalid")
        return version

    def validate_snapshot(self, serialized: str) -> tuple[str | None, str | None]:
        snapshot = decode_ledger_snapshot(serialized)
        return snapshot.environment, snapshot.account_id


current_execution_snapshot_schema = CurrentExecutionSnapshotSchema()


class Store:
    """One SQLite connection confined to one execution owner thread.

    A failed COMMIT has an uncertain outcome. The connection is discarded and the
    owner must stop; it cannot safely retry the transition in this process.
    """

    def __init__(self, path: Path) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        self.db = sqlite3.connect(path, timeout=5, isolation_level=None)
        self._usable = True
        self._closed = False
        self._expected_identity: tuple[str, str] | None = None
        try:
            self.db.execute("PRAGMA journal_mode=WAL")
            self.db.execute("PRAGMA synchronous=FULL")
            self.db.execute("PRAGMA foreign_keys=ON")
            self.db.execute("PRAGMA busy_timeout=5000")
            ensure_schema(self.db, EXECUTION_SCHEMA)
        except BaseException:
            self.db.close()
            raise

    @property
    def usable(self) -> bool:
        return self._usable and not self._closed

    def _require_usable(self) -> None:
        if not self.usable:
            raise RuntimeError("Execution SQLite session is closed or unusable")

    def _discard(self) -> None:
        self._usable = False
        self.close()

    def bind_identity(self, account_id: BrokerAccountNumber, environment: str) -> None:
        if not account_id or environment not in {"paper", "live"}:
            raise ValueError("Verified broker account and environment are required")
        self._require_usable()
        row = self.db.execute(
            "SELECT environment, account_id FROM identity WHERE singleton=1"
        ).fetchone()
        if row is not None and row != (environment, account_id):
            raise RuntimeError(
                "Execution state belongs to a different broker account or environment"
            )
        snapshot = self.db.execute("SELECT data FROM snapshot WHERE singleton=1").fetchone()
        if snapshot is not None:
            ledger = decode_ledger_snapshot(snapshot[0])
            if (ledger.account_id, ledger.environment) != (account_id, environment):
                raise RuntimeError("Execution snapshot belongs to a different broker account")
        if (row is None) != (snapshot is None):
            raise RuntimeError("Execution identity and snapshot are incomplete")
        self._expected_identity = (environment, account_id)

    def load(self) -> LedgerSnapshot:
        self._require_usable()
        row = self.db.execute("SELECT data FROM snapshot WHERE singleton=1").fetchone()
        return decode_ledger_snapshot(row[0]) if row else LedgerSnapshot()

    def save(self, snapshot: LedgerSnapshot, event: JournalEvent) -> None:
        with self._transaction():
            if (
                self._expected_identity is None
                or (snapshot.environment, snapshot.account_id) != self._expected_identity
            ):
                raise RuntimeError("Execution snapshot identity was not verified")
            identity = self.db.execute(
                "SELECT environment, account_id FROM identity WHERE singleton=1"
            ).fetchone()
            if identity is None:
                self.db.execute(
                    "INSERT INTO identity(singleton, environment, account_id) VALUES (1, ?, ?)",
                    self._expected_identity,
                )
            elif identity != self._expected_identity:
                raise RuntimeError(
                    "Execution snapshot account does not match verified broker account"
                )
            self.db.execute(
                "INSERT INTO snapshot(singleton, data) VALUES (1, ?) "
                "ON CONFLICT(singleton) DO UPDATE SET data=excluded.data",
                (snapshot.model_dump_json(),),
            )
            self.db.execute(
                "INSERT INTO journal(event, enqueued_at) VALUES (?, ?)",
                (event.model_dump_json(), dt.datetime.now(dt.UTC).isoformat()),
            )
            notification = execution_notification(snapshot, event)
            if notification is not None:
                self._enqueue_notification(notification)

    def _enqueue_notification(self, notification: NotificationIntent) -> None:
        payload = notification.payload
        self.db.execute(
            "INSERT OR IGNORE INTO notifications(key, stream_id, payload, enqueued_at) "
            "VALUES (?, ?, ?, ?)",
            (
                notification.key,
                notification.stream_id,
                json.dumps(
                    {
                        "labels": dict(payload.labels),
                        "annotations": dict(payload.annotations),
                        "starts_at": payload.starts_at.isoformat(),
                    },
                    ensure_ascii=False,
                ),
                dt.datetime.now(dt.UTC).isoformat(),
            ),
        )

    def message_events(self, message_ids: set[str]) -> tuple[JournalEvent, ...]:
        """Every journal event of these posts, plus the account's control changes over the
        same span, for Activity's timeline."""
        self._require_usable()
        return message_events(self.db, message_ids)

    def event_page(
        self, before_seq: int | None, limit: int
    ) -> tuple[tuple[int, JournalEvent], ...]:
        if not 1 <= limit <= 100 or (before_seq is not None and before_seq < 1):
            raise ValueError("Invalid account event page")
        self._require_usable()
        rows = self.db.execute(
            "SELECT id,event FROM journal WHERE (? IS NULL OR id < ?) ORDER BY id DESC LIMIT ?",
            (before_seq, before_seq, limit),
        ).fetchall()
        return tuple((seq, JournalEvent.model_validate_json(raw)) for seq, raw in rows)

    def pending_notifications(self) -> tuple[tuple[int, str, str, dict[str, object]], ...]:
        self._require_usable()
        rows = self.db.execute(
            "SELECT id, key, stream_id, payload FROM notifications "
            "WHERE delivered_at IS NULL ORDER BY id LIMIT 100"
        ).fetchall()
        return tuple(
            (id_, key, stream_id, json.loads(payload)) for id_, key, stream_id, payload in rows
        )

    def confirm_notification(self, notification_id: int) -> None:
        with self._transaction():
            self.db.execute(
                "UPDATE notifications SET delivered_at=? WHERE id=? AND delivered_at IS NULL",
                (dt.datetime.now(dt.UTC).timestamp(), notification_id),
            )

    def close(self) -> None:
        if not self._closed:
            self._closed = True
            self.db.close()

    @contextmanager
    def _transaction(self) -> Iterator[None]:
        self._require_usable()
        self.db.execute("BEGIN IMMEDIATE")
        try:
            yield
        except BaseException as failure:
            try:
                self.db.execute("ROLLBACK")
            except BaseException as rollback_failure:
                self._discard()
                failure.add_note(f"SQLite rollback failed: {type(rollback_failure).__name__}")
                raise failure from rollback_failure
            raise
        else:
            try:
                self.db.execute("COMMIT")
            except BaseException:
                self._discard()
                raise


def message_events(db: sqlite3.Connection, message_ids: set[str]) -> tuple[JournalEvent, ...]:
    """The journal events of these posts in order, with the account's control changes between
    the first and the last of them (a resume explains a held buy)."""
    if not message_ids:
        return ()
    marks = ",".join("?" * len(message_ids))
    rows = db.execute(
        "SELECT event FROM journal WHERE json_extract(event, '$.payload.message_id') "
        f"IN ({marks}) ORDER BY id",
        tuple(sorted(message_ids)),
    ).fetchall()
    events = tuple(JournalEvent.model_validate_json(raw) for (raw,) in rows)
    if not events:
        return ()
    first, last = min(event.at for event in events), max(event.at for event in events)
    controls = db.execute(
        "SELECT event FROM journal WHERE json_extract(event, '$.payload.kind') = "
        "'account_control_changed' ORDER BY id"
    ).fetchall()
    changes = tuple(
        event
        for event in (JournalEvent.model_validate_json(raw) for (raw,) in controls)
        if first <= event.at <= last
    )
    return events + changes
