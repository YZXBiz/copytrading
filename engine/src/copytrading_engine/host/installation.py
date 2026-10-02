"""Single-engine ownership and the persisted identity of one installation's database."""

import fcntl
import os
import sqlite3
import uuid
from pathlib import Path
from types import TracebackType
from typing import Self

from copytrading_engine.host.errors import (
    ForeignInstallation,
    InstallationAlreadyRunning,
    InvalidCommand,
    StoreClosed,
    StoreUnavailable,
    UnknownSchemaVersion,
)
from copytrading_engine.shared.sqlite import (
    SchemaComponent,
    SchemaMismatch,
    ensure_schema,
    verify_schema,
)

APPLICATION_DATABASE_VERSION = 3
"""`PRAGMA user_version` of application.db; the app compares it before accepting an update."""

INSTALLATION_SCHEMA = SchemaComponent(
    "installation",
    1,
    "CREATE TABLE IF NOT EXISTS engine_metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)",
)


class Installation:
    """Hold the engine lock and confirm application.db belongs to this installation.

    Open it before any store that writes application.db, and close it after them:
    the lock is what keeps a second engine from writing the same database.
    """

    def __init__(
        self,
        path: Path,
        *,
        instance_id: str | None = None,
        lock_path: Path | None = None,
        read_only: bool = False,
        busy_timeout_ms: int = 500,
    ) -> None:
        if busy_timeout_ms <= 0:
            raise ValueError("busy_timeout_ms must be positive")
        self.path = Path(path)
        self.read_only = read_only
        self.busy_timeout_ms = busy_timeout_ms
        self._lock_path = (
            Path(lock_path) if lock_path else self.path.with_suffix(self.path.suffix + ".lock")
        )
        self._requested_id = canonical_instance_id(instance_id) if instance_id is not None else None
        self._lock_fd: int | None = None
        self._instance_id: str | None = None

    @property
    def instance_id(self) -> str:
        if self._instance_id is None:
            raise StoreClosed("installation has not been opened")
        return self._instance_id

    def connect(self) -> sqlite3.Connection:
        """Open a connection to application.db in this installation's access mode."""
        if self.read_only:
            uri = f"{self.path.resolve(strict=True).as_uri()}?mode=ro&immutable=1"
            connection = sqlite3.connect(
                uri, uri=True, timeout=self.busy_timeout_ms / 1000, isolation_level=None
            )
        else:
            connection = sqlite3.connect(
                self.path, timeout=self.busy_timeout_ms / 1000, isolation_level=None
            )
        try:
            connection.execute(f"PRAGMA busy_timeout = {self.busy_timeout_ms}")
        except BaseException:
            connection.close()
            raise
        return connection

    def __enter__(self) -> Self:
        if self._lock_fd is not None or self._instance_id is not None:
            raise StoreClosed("installation cannot be opened more than once")
        self._acquire_lock()
        try:
            self._instance_id = self._open_identity()
        except BaseException:
            self._release_lock()
            raise
        return self

    def __exit__(
        self,
        exc_type: type[BaseException] | None,
        exc: BaseException | None,
        traceback: TracebackType | None,
    ) -> None:
        self._release_lock()

    def _acquire_lock(self) -> None:
        self._lock_path.parent.mkdir(parents=True, exist_ok=True)
        fd = os.open(self._lock_path, os.O_CREAT | os.O_RDWR, 0o600)
        try:
            os.fchmod(fd, 0o600)
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as exc:
            os.close(fd)
            raise InstallationAlreadyRunning("installation already has an engine owner") from exc
        except BaseException:
            os.close(fd)
            raise
        self._lock_fd = fd

    def _release_lock(self) -> None:
        fd, self._lock_fd = self._lock_fd, None
        if fd is not None:
            try:
                fcntl.flock(fd, fcntl.LOCK_UN)
            finally:
                os.close(fd)

    def _open_identity(self) -> str:
        try:
            if not self.read_only:
                self.path.parent.mkdir(parents=True, exist_ok=True)
                db_fd = os.open(self.path, os.O_CREAT | os.O_RDWR, 0o600)
                os.fchmod(db_fd, 0o600)
                os.close(db_fd)
            connection = self.connect()
            try:
                return self._verify_or_create(connection)
            finally:
                connection.close()
        except (sqlite3.Error, OSError) as exc:
            raise StoreUnavailable("durable storage is unavailable") from exc

    def _verify_or_create(self, connection: sqlite3.Connection) -> str:
        version = connection.execute("PRAGMA user_version").fetchone()[0]
        if self.read_only:
            if version != APPLICATION_DATABASE_VERSION:
                raise UnknownSchemaVersion("restore candidate database schema is not supported")
            _verify(connection)
        elif version == 0:
            if connection.execute(
                "SELECT 1 FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
            ).fetchone():
                raise UnknownSchemaVersion("unversioned database contains unknown tables")
            self._create(connection)
        elif version == APPLICATION_DATABASE_VERSION:
            connection.execute("PRAGMA journal_mode = WAL")
            _verify(connection)
        else:
            raise UnknownSchemaVersion("database schema version is not supported")

        row = connection.execute(
            "SELECT value FROM engine_metadata WHERE key = 'instance_id'"
        ).fetchone()
        if row is None:
            raise UnknownSchemaVersion("database has no installation identity")
        persisted = canonical_instance_id(row[0])
        if self._requested_id and persisted != self._requested_id:
            raise ForeignInstallation("database belongs to a different installation")
        return persisted

    def _create(self, connection: sqlite3.Connection) -> None:
        connection.execute("PRAGMA journal_mode = WAL")
        connection.execute("PRAGMA synchronous = FULL")
        connection.execute("BEGIN IMMEDIATE")
        try:
            ensure_schema(connection, INSTALLATION_SCHEMA)
            connection.execute(
                "INSERT INTO engine_metadata(key, value) VALUES ('instance_id', ?)",
                (self._requested_id or str(uuid.uuid4()),),
            )
            connection.execute(f"PRAGMA user_version = {APPLICATION_DATABASE_VERSION}")
        except BaseException:
            connection.execute("ROLLBACK")
            raise
        connection.execute("COMMIT")


def _verify(connection: sqlite3.Connection) -> None:
    try:
        verify_schema(connection, INSTALLATION_SCHEMA)
    except SchemaMismatch as exc:
        raise UnknownSchemaVersion("database installation schema is incomplete") from exc


def canonical_instance_id(value: str | None) -> str:
    """Return the canonical UUID text; reject missing or non-canonical spellings."""
    if value is None:
        raise InvalidCommand("instance_id is required")
    try:
        parsed = uuid.UUID(value)
    except (ValueError, AttributeError) as exc:
        raise InvalidCommand("instance_id must be a UUID") from exc
    canonical = str(parsed)
    if value.lower() != canonical:
        raise InvalidCommand("instance_id must use canonical UUID formatting")
    return canonical
