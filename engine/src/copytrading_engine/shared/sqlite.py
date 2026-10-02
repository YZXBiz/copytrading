"""Small async boundary for one owned SQLite connection.

The complete database operation, including commit or rollback, runs on a worker
thread. Cancellation waits for that operation to settle before releasing the lock.
"""

import asyncio
import re
import sqlite3
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path
from typing import TypeVar

T = TypeVar("T")


class SQLiteUnit:
    def __init__(self, connection: sqlite3.Connection) -> None:
        self.connection = connection
        self._lock = asyncio.Lock()
        self._closing = False
        self._close_task: asyncio.Task[None] | None = None
        self._closed = False
        self._usable = True

    @classmethod
    async def open(cls, path: Path) -> SQLiteUnit:
        def connect() -> sqlite3.Connection:
            path.parent.mkdir(parents=True, exist_ok=True)
            db = sqlite3.connect(path, timeout=5, isolation_level=None, check_same_thread=False)
            try:
                db.execute("PRAGMA journal_mode=WAL")
                db.execute("PRAGMA synchronous=FULL")
                db.execute("PRAGMA foreign_keys=ON")
                db.execute("PRAGMA busy_timeout=5000")
            except BaseException:
                db.close()
                raise
            return db

        task = asyncio.create_task(asyncio.to_thread(connect))
        try:
            return cls(await asyncio.shield(task))
        except asyncio.CancelledError:
            while not task.done():
                try:
                    await asyncio.shield(task)
                except asyncio.CancelledError:
                    pass
            if not task.cancelled():
                error = task.exception()
                if error is None:
                    closer = asyncio.create_task(asyncio.to_thread(task.result().close))
                    while not closer.done():
                        try:
                            await asyncio.shield(closer)
                        except asyncio.CancelledError:
                            pass
                    closer.result()
            raise

    async def run(self, operation: Callable[[sqlite3.Connection], T], *, write: bool = False) -> T:
        if self._closing:
            raise RuntimeError("SQLite session is unusable")
        async with self._lock:
            if self._closing or self._closed or not self._usable:
                raise RuntimeError("SQLite session is unusable")

            def execute() -> T:
                try:
                    if write:
                        self.connection.execute("BEGIN IMMEDIATE")
                    result = operation(self.connection)
                    if write:
                        try:
                            self.connection.commit()
                        except sqlite3.Error:
                            # The caller cannot know whether COMMIT reached disk.
                            self._usable = False
                            raise
                    return result
                except BaseException:
                    if write:
                        try:
                            self.connection.rollback()
                        except sqlite3.Error:
                            self._usable = False
                    raise

            task = asyncio.create_task(asyncio.to_thread(execute))
            try:
                return await asyncio.shield(task)
            except asyncio.CancelledError:
                # Repeated cancellation must not release the lock while the
                # worker still owns a transaction or allow close() to race it.
                while not task.done():
                    try:
                        await asyncio.shield(task)
                    except asyncio.CancelledError:
                        pass
                if not task.cancelled():
                    task.exception()
                raise

    async def _close_owned(self) -> None:
        async with self._lock:
            if not self._closed:
                self._closed = True
                self._usable = False
                await asyncio.to_thread(self.connection.close)

    async def close(self) -> None:
        if self._close_task is None:
            self._closing = True
            self._close_task = asyncio.create_task(self._close_owned())
        task = self._close_task
        cancelled = False
        while True:
            try:
                await asyncio.shield(task)
                break
            except asyncio.CancelledError:
                cancelled = True
                if task.done():
                    break
            except BaseException:  # noqa: BLE001 - keep draining until the worker settles
                break
        task.result()
        if cancelled:
            raise asyncio.CancelledError


class SchemaMismatch(RuntimeError):
    """A database component's recorded revision or objects differ from this build."""


@dataclass(frozen=True, slots=True)
class SchemaComponent:
    """One store's named, revisioned set of SQLite objects."""

    name: str
    revision: int
    ddl: str

    def __post_init__(self) -> None:
        if not self.name or self.revision < 1:
            raise ValueError("Schema component needs a name and a positive revision")
        for statement in self.statements():
            if _object_identity(statement) is None:
                raise ValueError(f"Schema component {self.name} has an unsupported statement")

    def statements(self) -> tuple[str, ...]:
        return tuple(part.strip() for part in self.ddl.split(";") if part.strip())


_REVISIONS_TABLE = (
    "CREATE TABLE IF NOT EXISTS copytrading_engine_schema_revisions "
    "(component TEXT PRIMARY KEY, revision INTEGER NOT NULL)"
)


def ensure_schema(db: sqlite3.Connection, component: SchemaComponent) -> None:
    """Reject incompatible component objects, then create missing ones and record the revision."""
    db.execute(_REVISIONS_TABLE)
    recorded = _recorded_revision(db, component)
    if recorded is not None and recorded != component.revision:
        raise SchemaMismatch(f"Unsupported {component.name} schema revision: {recorded}")
    for statement in component.statements():
        name, existing = _existing_sql(db, statement)
        if existing is not None and _normalized(existing) != _normalized(statement):
            raise SchemaMismatch(f"Incompatible {component.name} schema object: {name}")
        db.execute(statement)
    db.execute(
        "INSERT OR IGNORE INTO copytrading_engine_schema_revisions VALUES (?,?)",
        (component.name, component.revision),
    )


def verify_schema(db: sqlite3.Connection, component: SchemaComponent) -> None:
    """Check a component's recorded revision and every object without writing."""
    revisions_table = db.execute(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",
        ("copytrading_engine_schema_revisions",),
    ).fetchone()
    if revisions_table is None:
        raise SchemaMismatch(f"Missing {component.name} schema revision")
    if _recorded_revision(db, component) != component.revision:
        raise SchemaMismatch(f"Unsupported {component.name} schema revision")
    for statement in component.statements():
        name, existing = _existing_sql(db, statement)
        if existing is None or _normalized(existing) != _normalized(statement):
            raise SchemaMismatch(f"Incompatible {component.name} schema object: {name}")


def _recorded_revision(db: sqlite3.Connection, component: SchemaComponent) -> int | None:
    row = db.execute(
        "SELECT revision FROM copytrading_engine_schema_revisions WHERE component=?",
        (component.name,),
    ).fetchone()
    return None if row is None else row[0]


def _object_identity(statement: str) -> tuple[str, str] | None:
    match = re.match(r"CREATE\s+(TABLE|INDEX)\s+IF\s+NOT\s+EXISTS\s+(\w+)", statement, re.I)
    return None if match is None else (match.group(1).lower(), match.group(2))


def _existing_sql(db: sqlite3.Connection, statement: str) -> tuple[str, str | None]:
    identity = _object_identity(statement)
    if identity is None:
        raise ValueError("Schema contains an unsupported statement")
    row = db.execute("SELECT sql FROM sqlite_master WHERE type=? AND name=?", identity).fetchone()
    return identity[1], None if row is None else row[0]


def _normalized(sql: str) -> str:
    sql = re.sub(r"\bIF NOT EXISTS\b", "", sql, flags=re.I)
    return re.sub(r"\s+", " ", sql).strip().rstrip(";").upper()
