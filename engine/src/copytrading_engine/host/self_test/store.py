"""Durable self-test workflows owned by one dedicated worker thread."""

import asyncio
import concurrent.futures
import contextlib
import json
import sqlite3
import threading
import uuid
from collections.abc import Callable, Iterator
from datetime import UTC, datetime
from typing import Any

from copytrading_engine.host.errors import (
    ForeignInstallation,
    IdentityConflict,
    InstallationAlreadyRunning,
    InvalidCommand,
    InvalidTransition,
    StoreClosed,
    StoreUnavailable,
    UnknownSchemaVersion,
    WorkflowNotFound,
)
from copytrading_engine.host.installation import Installation
from copytrading_engine.host.self_test.model import (
    DestinationOutcome,
    ParsedSelfTest,
    ParseRejected,
    SelfTestAccepted,
    SelfTestCompleted,
    SelfTestParsed,
    Stage,
    SubmitSelfTest,
    WorkflowAcceptance,
    WorkflowView,
)
from copytrading_engine.shared.sqlite import (
    SchemaComponent,
    SchemaMismatch,
    ensure_schema,
    verify_schema,
)

_PENDING_LIMIT = 100
SELF_TEST_SCHEMA = SchemaComponent(
    "self_test",
    1,
    """
    CREATE TABLE IF NOT EXISTS workflows (
        command_id TEXT PRIMARY KEY, canonical_command TEXT NOT NULL,
        stage TEXT NOT NULL CHECK (stage IN ('captured', 'parsed', 'completed', 'failed')),
        parsed_json TEXT, outcomes_json TEXT NOT NULL, trace_id TEXT NOT NULL UNIQUE,
        trace_anchor_exported INTEGER NOT NULL DEFAULT 0
        CHECK (trace_anchor_exported IN (0, 1)),
        created_at TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS jobs (
        command_id TEXT PRIMARY KEY REFERENCES workflows(command_id),
        status TEXT NOT NULL CHECK (status IN ('pending', 'completed')),
        created_at TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS audit_events (
        event_id INTEGER PRIMARY KEY AUTOINCREMENT,
        command_id TEXT NOT NULL REFERENCES workflows(command_id),
        event_type TEXT NOT NULL, payload_json TEXT NOT NULL, created_at TEXT NOT NULL);
    CREATE INDEX IF NOT EXISTS jobs_status_created ON jobs(status, created_at, command_id)
    """,
)


class SQLiteSelfTestStore:
    """Self-test workflow tables on one worker thread, inside an opened installation."""

    def __init__(self, installation: Installation) -> None:
        self.installation = installation
        self.path = installation.path
        self._busy_timeout_ms = installation.busy_timeout_ms
        self._read_only = installation.read_only
        self._executor = concurrent.futures.ThreadPoolExecutor(
            max_workers=1, thread_name_prefix="desktop-sqlite-owner"
        )
        self._state_lock = threading.Lock()
        self._connection: sqlite3.Connection | None = None
        self._owner_thread_id: int | None = None
        self._entered = False
        self._closing = False
        self._closed = False
        self._usable = True
        self._close_future: concurrent.futures.Future[None] | None = None

    def __enter__(self) -> SQLiteSelfTestStore:
        _ = self.installation.instance_id  # the installation must already be open
        with self._state_lock:
            if self._entered or self._closed:
                raise StoreClosed("store cannot be opened more than once")
            self._entered = True
        future = self._executor.submit(self._run, self._open)
        try:
            future.result()
        except BaseException:
            cleanup = self._executor.submit(self._run, self._release_resources)
            try:
                cleanup.result()
            except BaseException:  # noqa: BLE001 - cleanup must not mask the primary outcome
                pass
            self._executor.shutdown(wait=True)
            with self._state_lock:
                self._closed = True
            raise
        return self

    def __exit__(self, exc_type: object, exc: object, traceback: object) -> None:
        self.close()

    def accept(self, command: SubmitSelfTest) -> WorkflowAcceptance:
        return self._call(self._accept, command)

    def get(self, command_id: str) -> WorkflowView:
        return self._call(self._get, command_id)

    def pending(self, limit: int | None = None) -> tuple[str, ...]:
        return self._call(self._pending, limit)

    def advance(
        self,
        command_id: str,
        expected: Stage,
        next_stage: Stage,
        outcomes: tuple[DestinationOutcome, ...],
        *,
        parsed: ParsedSelfTest | None = None,
        parse_rejection: ParseRejected | None = None,
    ) -> WorkflowView:
        return self._call(
            self._advance,
            command_id,
            expected,
            next_stage,
            outcomes,
            parsed,
            parse_rejection,
        )

    def load_command(self, command_id: str) -> SubmitSelfTest:
        return self._call(self._load_command, command_id)

    def load_parsed(self, command_id: str) -> ParsedSelfTest:
        return self._call(self._load_parsed, command_id)

    def counts(self) -> tuple[int, int, int]:
        return self._call(self._counts)

    def mark_trace_anchor_exported(self, command_id: str) -> None:
        self._call(self._mark_trace_anchor_exported, command_id)

    async def accept_async(self, command: SubmitSelfTest) -> WorkflowAcceptance:
        return await self._call_async(self._accept, command)

    async def get_async(self, command_id: str) -> WorkflowView:
        return await self._call_async(self._get, command_id)

    async def pending_async(self, limit: int | None = None) -> tuple[str, ...]:
        return await self._call_async(self._pending, limit)

    async def advance_async(
        self,
        command_id: str,
        expected: Stage,
        next_stage: Stage,
        outcomes: tuple[DestinationOutcome, ...],
        *,
        parsed: ParsedSelfTest | None = None,
        parse_rejection: ParseRejected | None = None,
    ) -> WorkflowView:
        return await self._call_async(
            self._advance,
            command_id,
            expected,
            next_stage,
            outcomes,
            parsed,
            parse_rejection,
        )

    async def load_command_async(self, command_id: str) -> SubmitSelfTest:
        return await self._call_async(self._load_command, command_id)

    async def load_parsed_async(self, command_id: str) -> ParsedSelfTest:
        return await self._call_async(self._load_parsed, command_id)

    async def counts_async(self) -> tuple[int, int, int]:
        return await self._call_async(self._counts)

    async def trace_anchor_exported_async(self, command_id: str) -> bool:
        return await self._call_async(self._trace_anchor_exported, command_id)

    async def aclose(self) -> None:
        future = self._begin_close()
        if future is None:
            return
        try:
            await _await_without_abandoning(future)
        finally:
            self._finish_close()

    def close(self) -> None:
        future = self._begin_close()
        if future is None:
            return
        try:
            future.result()
        finally:
            self._finish_close()

    def _call[T](self, operation: Callable[..., T], *args: object) -> T:
        return self._schedule(operation, *args).result()

    async def _call_async[T](self, operation: Callable[..., T], *args: object) -> T:
        return await _await_without_abandoning(self._schedule(operation, *args))

    def _schedule[T](
        self, operation: Callable[..., T], *args: object
    ) -> concurrent.futures.Future[T]:
        with self._state_lock:
            if not self._entered or self._closing or self._closed:
                raise StoreClosed("store is not accepting operations")

            def run() -> T:
                return self._run(lambda: operation(*args))

            return self._executor.submit(run)

    def _run[T](self, operation: Callable[[], T]) -> T:
        self._assert_owner_thread()
        if not self._usable:
            raise StoreUnavailable("database outcome is uncertain; reopen the store")
        try:
            return operation()
        except (
            IdentityConflict,
            InstallationAlreadyRunning,
            ForeignInstallation,
            UnknownSchemaVersion,
            InvalidCommand,
            InvalidTransition,
            WorkflowNotFound,
            StoreClosed,
            StoreUnavailable,
        ):
            raise
        except (sqlite3.Error, OSError) as exc:
            raise StoreUnavailable("durable storage is unavailable") from exc

    def _assert_owner_thread(self) -> None:
        current_thread = threading.get_ident()
        if self._owner_thread_id is None:
            self._owner_thread_id = current_thread
        elif self._owner_thread_id != current_thread:
            raise RuntimeError("SQLite worker ownership was violated")

    def _open(self) -> None:
        try:
            self._connection = connection = self.installation.connect()
            connection.execute("PRAGMA foreign_keys = ON")
            if self._read_only:
                try:
                    verify_schema(connection, SELF_TEST_SCHEMA)
                except SchemaMismatch as exc:
                    raise UnknownSchemaVersion("restore candidate self-test schema") from exc
                return
            connection.execute("PRAGMA journal_mode = WAL")
            connection.execute("PRAGMA synchronous = FULL")
            with self._transaction(connection):
                try:
                    ensure_schema(connection, SELF_TEST_SCHEMA)
                except SchemaMismatch as exc:
                    raise UnknownSchemaVersion("database self-test schema is unsupported") from exc
        except BaseException:
            self._release_resources()
            raise

    @contextlib.contextmanager
    def _transaction(self, connection: sqlite3.Connection, *, write: bool = True) -> Iterator[None]:
        connection.execute("BEGIN IMMEDIATE" if write else "BEGIN")
        try:
            yield
        except BaseException:
            try:
                connection.execute("ROLLBACK")
            except sqlite3.Error:
                self._usable = False
            raise
        else:
            try:
                connection.execute("COMMIT")
            except BaseException as exc:
                self._usable = False
                try:
                    connection.close()
                except sqlite3.Error:
                    pass
                self._connection = None
                raise StoreUnavailable("commit outcome is uncertain; reopen the store") from exc

    def _accept(self, command: SubmitSelfTest) -> WorkflowAcceptance:
        connection = self._require_connection()
        canonical = _canonical_command(command)
        trace_id = str(uuid.uuid4())
        now = _now()
        newly_accepted = False
        with self._transaction(connection):
            existing = connection.execute(
                "SELECT canonical_command FROM workflows WHERE command_id = ?",
                (command.command_id,),
            ).fetchone()
            if existing is not None:
                if existing[0] != canonical:
                    raise IdentityConflict("command ID belongs to different command content")
            else:
                newly_accepted = True
                connection.execute(
                    "INSERT INTO workflows(command_id, canonical_command, stage, parsed_json, "
                    "outcomes_json, trace_id, created_at) "
                    "VALUES (?, ?, 'captured', NULL, '[]', ?, ?)",
                    (command.command_id, canonical, trace_id, now),
                )
                connection.execute(
                    "INSERT INTO jobs(command_id, status, created_at) VALUES (?, 'pending', ?)",
                    (command.command_id, now),
                )
                accepted = SelfTestAccepted(command.command_id, trace_id)
                self._append_audit(connection, "SelfTestAccepted", accepted, now)
            view = self._read_view(connection, command.command_id)
        return WorkflowAcceptance(view, newly_accepted)

    def _get(self, command_id: str) -> WorkflowView:
        connection = self._require_connection()
        with self._transaction(connection, write=False):
            view = self._read_view(connection, command_id)
        return view

    def _pending(self, limit: int | None) -> tuple[str, ...]:
        if limit is not None and limit < 0:
            raise InvalidCommand("pending limit must not be negative")
        connection = self._require_connection()
        sql = "SELECT command_id FROM jobs WHERE status = 'pending' ORDER BY created_at, command_id"
        with self._transaction(connection, write=False):
            if limit is not None:
                sql += " LIMIT ?"
                rows = connection.execute(sql, (limit,)).fetchall()
            else:
                rows = connection.execute(sql).fetchall()
        return tuple(row[0] for row in rows)

    def _advance(
        self,
        command_id: str,
        expected: Stage,
        next_stage: Stage,
        outcomes: tuple[DestinationOutcome, ...],
        parsed: ParsedSelfTest | None,
        parse_rejection: ParseRejected | None,
    ) -> WorkflowView:
        allowed = {
            (Stage.CAPTURED, Stage.PARSED),
            (Stage.CAPTURED, Stage.FAILED),
            (Stage.PARSED, Stage.COMPLETED),
        }
        if (expected, next_stage) not in allowed:
            raise InvalidTransition("workflow transition is not allowed")

        connection = self._require_connection()
        with self._transaction(connection):
            row = connection.execute(
                "SELECT canonical_command, stage, parsed_json FROM workflows WHERE command_id = ?",
                (command_id,),
            ).fetchone()
            if row is None:
                raise WorkflowNotFound("workflow was not found")
            if row[1] != expected.value:
                raise InvalidTransition("workflow stage changed before transition")
            command = _decode_command(command_id, row[0])
            now = _now()
            if next_stage is Stage.PARSED:
                if parsed is None or parse_rejection is not None or outcomes:
                    raise InvalidTransition("parsed transition requires parsed evidence only")
                parsed_json = _json(_parsed_payload(parsed))
                event: object = SelfTestParsed(command_id, parsed)
                changed = connection.execute(
                    "UPDATE workflows SET stage = ?, parsed_json = ? "
                    "WHERE command_id = ? AND stage = ?",
                    (next_stage.value, parsed_json, command_id, expected.value),
                ).rowcount
            elif next_stage is Stage.FAILED:
                if parse_rejection != ParseRejected(command_id) or parsed is not None or outcomes:
                    raise InvalidTransition("failed transition requires a parse rejection")
                event = parse_rejection
                changed = connection.execute(
                    "UPDATE workflows SET stage = ? WHERE command_id = ? AND stage = ?",
                    (next_stage.value, command_id, expected.value),
                ).rowcount
                updated = connection.execute(
                    "UPDATE jobs SET status = 'completed' "
                    "WHERE command_id = ? AND status = 'pending'",
                    (command_id,),
                ).rowcount
                if updated != 1:
                    raise InvalidTransition("pending job was not available to complete")
            else:
                if parsed is not None or parse_rejection is not None:
                    raise InvalidTransition("completed transition cannot replace parsed evidence")
                persisted = _decode_parsed(row[2]) if row[2] else None
                if persisted is None:
                    raise InvalidTransition("parsed evidence is required before completion")
                expected_accounts = command.destination_ids
                actual_accounts = tuple(outcome.account_id for outcome in outcomes)
                if actual_accounts != expected_accounts or any(
                    outcome.result != "simulated" for outcome in outcomes
                ):
                    raise InvalidTransition(
                        "completion requires one simulated outcome per destination"
                    )
                event = SelfTestCompleted(command_id, outcomes)
                outcomes_json = _json([_outcome_payload(outcome) for outcome in outcomes])
                changed = connection.execute(
                    "UPDATE workflows SET stage = ?, outcomes_json = ? "
                    "WHERE command_id = ? AND stage = ?",
                    (next_stage.value, outcomes_json, command_id, expected.value),
                ).rowcount
                updated = connection.execute(
                    "UPDATE jobs SET status = 'completed' "
                    "WHERE command_id = ? AND status = 'pending'",
                    (command_id,),
                ).rowcount
                if updated != 1:
                    raise InvalidTransition("pending job was not available to complete")

            if changed != 1:
                raise InvalidTransition("workflow compare-and-set failed")
            event_type = type(event).__name__
            self._append_audit(connection, event_type, event, now)
            view = self._read_view(connection, command_id)
        return view

    def _load_command(self, command_id: str) -> SubmitSelfTest:
        connection = self._require_connection()
        with self._transaction(connection, write=False):
            row = connection.execute(
                "SELECT canonical_command FROM workflows WHERE command_id = ?", (command_id,)
            ).fetchone()
        if row is None:
            raise WorkflowNotFound("workflow was not found")
        return _decode_command(command_id, row[0])

    def _load_parsed(self, command_id: str) -> ParsedSelfTest:
        connection = self._require_connection()
        with self._transaction(connection, write=False):
            row = connection.execute(
                "SELECT parsed_json FROM workflows WHERE command_id = ?", (command_id,)
            ).fetchone()
        if row is None:
            raise WorkflowNotFound("workflow was not found")
        if row[0] is None:
            raise StoreUnavailable("workflow has no persisted parse evidence")
        return _decode_parsed(row[0])

    def _counts(self) -> tuple[int, int, int]:
        connection = self._require_connection()
        with self._transaction(connection, write=False):
            row = connection.execute(
                "SELECT (SELECT COUNT(*) FROM workflows), "
                "(SELECT COUNT(*) FROM jobs WHERE status = 'pending'), "
                "(SELECT COUNT(*) FROM workflows WHERE stage = 'completed')"
            ).fetchone()
        return int(row[0]), int(row[1]), int(row[2])

    def _trace_anchor_exported(self, command_id: str) -> bool:
        connection = self._require_connection()
        with self._transaction(connection, write=False):
            row = connection.execute(
                "SELECT trace_anchor_exported FROM workflows WHERE command_id = ?",
                (command_id,),
            ).fetchone()
        if row is None:
            raise WorkflowNotFound("workflow was not found")
        return bool(row[0])

    def _mark_trace_anchor_exported(self, command_id: str) -> None:
        connection = self._open_receipt_connection()
        try:
            connection.execute("BEGIN IMMEDIATE")
            cursor = connection.execute(
                "UPDATE workflows SET trace_anchor_exported = 1 WHERE command_id = ?",
                (command_id,),
            )
            if cursor.rowcount == 0:
                raise WorkflowNotFound("workflow was not found")
            connection.execute("COMMIT")
        except BaseException as exc:
            if connection.in_transaction:
                try:
                    connection.execute("ROLLBACK")
                except sqlite3.Error:
                    pass
            if isinstance(exc, (WorkflowNotFound, StoreUnavailable)):
                raise
            if isinstance(exc, sqlite3.Error):
                raise StoreUnavailable("diagnostics anchor receipt could not be committed") from exc
            raise
        finally:
            connection.close()

    def _open_receipt_connection(self) -> sqlite3.Connection:
        """Open a bounded connection isolated from operational transaction state."""
        connection = sqlite3.connect(
            self.path,
            timeout=self._busy_timeout_ms / 1000,
            isolation_level=None,
        )
        try:
            connection.execute(f"PRAGMA busy_timeout = {self._busy_timeout_ms}")
        except BaseException:
            connection.close()
            raise
        return connection

    def _read_view(self, connection: sqlite3.Connection, command_id: str) -> WorkflowView:
        row = connection.execute(
            "SELECT stage, outcomes_json, trace_id FROM workflows WHERE command_id = ?",
            (command_id,),
        ).fetchone()
        if row is None:
            raise WorkflowNotFound("workflow was not found")
        try:
            stage = Stage(row[0])
            outcomes = tuple(
                DestinationOutcome(account_id=item["account_id"], result=item["result"])
                for item in json.loads(row[1])
            )
            return WorkflowView(command_id, stage, outcomes, row[2])
        except (InvalidCommand, KeyError, TypeError, ValueError, json.JSONDecodeError) as exc:
            raise StoreUnavailable("persisted workflow data is invalid") from exc

    def _append_audit(
        self, connection: sqlite3.Connection, event_type: str, event: object, timestamp: str
    ) -> None:
        payload = _audit_payload(event)
        connection.execute(
            "INSERT INTO audit_events(command_id, event_type, payload_json, created_at) "
            "VALUES (?, ?, ?, ?)",
            (payload["command_id"], event_type, _json(payload), timestamp),
        )

    def _require_connection(self) -> sqlite3.Connection:
        if not self._usable or self._connection is None:
            raise StoreUnavailable("durable store must be reopened")
        return self._connection

    def _begin_close(self) -> concurrent.futures.Future[None] | None:
        with self._state_lock:
            if self._closed:
                return None
            if self._close_future is not None:
                return self._close_future
            if not self._entered:
                self._closing = True
                self._closed = True
                self._executor.shutdown(wait=True)
                return None
            self._closing = True
            self._close_future = self._executor.submit(self._close_task)
            return self._close_future

    def _close_task(self) -> None:
        self._assert_owner_thread()
        self._close_on_worker()

    def _finish_close(self) -> None:
        self._executor.shutdown(wait=True)
        with self._state_lock:
            self._closed = True

    def _close_on_worker(self) -> None:
        connection = self._connection
        try:
            if connection is not None:
                if not self._read_only:
                    try:
                        connection.execute("PRAGMA wal_checkpoint(TRUNCATE)")
                    except sqlite3.Error:
                        pass
                try:
                    connection.close()
                finally:
                    self._connection = None
        finally:
            self._usable = False

    def _release_resources(self) -> None:
        connection, self._connection = self._connection, None
        if connection is not None:
            try:
                connection.close()
            except sqlite3.Error:
                pass


async def _await_without_abandoning[T](future: concurrent.futures.Future[T]) -> T:
    wrapped = asyncio.wrap_future(future)
    cancelled = False
    while True:
        try:
            result = await asyncio.shield(wrapped)
            break
        except asyncio.CancelledError:
            cancelled = True
            if wrapped.done():
                break
        except BaseException:  # noqa: BLE001 - keep draining until the worker settles
            break
    try:
        result = wrapped.result()
    except BaseException:
        if cancelled:
            raise asyncio.CancelledError from None
        raise
    if cancelled:
        raise asyncio.CancelledError from None
    return result


def _canonical_command(command: SubmitSelfTest) -> str:
    return _json({"text": command.text, "destination_ids": list(command.destination_ids)})


def _decode_command(command_id: str, canonical: str) -> SubmitSelfTest:
    try:
        payload = json.loads(canonical)
        return SubmitSelfTest(
            command_id=command_id,
            text=payload["text"],
            destination_ids=tuple(payload["destination_ids"]),
        )
    except (InvalidCommand, KeyError, TypeError, ValueError, json.JSONDecodeError) as exc:
        raise StoreUnavailable("persisted command is invalid") from exc


def _parsed_payload(parsed: ParsedSelfTest) -> dict[str, object]:
    return {
        "symbol": parsed.symbol,
        "action": parsed.action,
        "quantity_numerator": parsed.quantity.numerator,
        "quantity_denominator": parsed.quantity.denominator,
        "unit_price": str(parsed.unit_price),
    }


def _decode_parsed(value: str) -> ParsedSelfTest:
    from decimal import Decimal
    from fractions import Fraction

    try:
        payload = json.loads(value)
        return ParsedSelfTest(
            symbol=payload["symbol"],
            action=payload["action"],
            quantity=Fraction(payload["quantity_numerator"], payload["quantity_denominator"]),
            unit_price=Decimal(payload["unit_price"]),
        )
    except (KeyError, TypeError, ValueError, ZeroDivisionError, json.JSONDecodeError) as exc:
        raise StoreUnavailable("persisted parse evidence is invalid") from exc


def _outcome_payload(outcome: DestinationOutcome) -> dict[str, str]:
    return {"account_id": outcome.account_id, "result": outcome.result}


def _audit_payload(event: object) -> dict[str, Any]:
    if isinstance(event, SelfTestAccepted):
        return {"command_id": event.command_id, "trace_id": event.trace_id}
    if isinstance(event, SelfTestParsed):
        return {"command_id": event.command_id, "parsed": _parsed_payload(event.parsed)}
    if isinstance(event, SelfTestCompleted):
        return {
            "command_id": event.command_id,
            "outcomes": [_outcome_payload(outcome) for outcome in event.outcomes],
        }
    if isinstance(event, ParseRejected):
        return {"command_id": event.command_id, "reason": event.reason}
    raise InvalidTransition("unknown audit event type")


def _json(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def _now() -> str:
    return datetime.now(UTC).isoformat(timespec="microseconds")
