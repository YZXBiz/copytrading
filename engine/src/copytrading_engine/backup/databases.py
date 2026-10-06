"""SQLite snapshots and the schema checks every backed-up database must pass."""

from __future__ import annotations

import os
import sqlite3
from pathlib import Path

from copytrading_engine.backup.files import require_regular_file
from copytrading_engine.backup.manifest import (
    ACCOUNT_DATABASE,
    APPLICATION_SCHEMA_PREFIX,
    BackupManifestError,
    account_schema_version,
    json_object,
)
from copytrading_engine.backup.ports import AccountSnapshotSchemaProvider, SchemaCatalogProvider
from copytrading_engine.backup.schema_catalog import (
    APPLICATION_COMPONENTS,
    APPLICATION_DATABASE_VERSION,
)

_SUPPORTED_APPLICATION_COMPONENTS = {
    component.name: component.revision for component in APPLICATION_COMPONENTS
}


def snapshot_database(source: Path, destination: Path) -> None:
    require_regular_file(source, "operational database is invalid")
    destination.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    source_db = sqlite3.connect(source, timeout=5)
    target_db = sqlite3.connect(destination, timeout=5)
    try:
        source_db.backup(target_db, pages=256, sleep=0.01)
    finally:
        target_db.close()
        source_db.close()
    os.chmod(destination, 0o600)


def sqlite_schema_version(
    path: Path,
    member_path: str,
    schema_catalog: SchemaCatalogProvider,
    snapshot_schema: AccountSnapshotSchemaProvider,
) -> str:
    connection = sqlite3.connect(path)
    try:
        if connection.execute("PRAGMA integrity_check").fetchone() != ("ok",):
            raise BackupManifestError(f"operational SQLite database is corrupt: {member_path}")
        if member_path == "application.db":
            user_version = connection.execute("PRAGMA user_version").fetchone()[0]
            if user_version != APPLICATION_DATABASE_VERSION:
                raise BackupManifestError("operational database schema is unsupported")
            rows = _component_revisions(connection)
            if set(rows) != set(_SUPPORTED_APPLICATION_COMPONENTS):
                raise BackupManifestError("operational component schema is incomplete")
            if rows != _SUPPORTED_APPLICATION_COMPONENTS:
                raise BackupManifestError("operational component schema is unsupported")
            if _schema_catalog(connection) != schema_catalog(member_path):
                raise BackupManifestError("operational database schema structure is incompatible")
            components = ",".join(f"{name}:{revision}" for name, revision in sorted(rows.items()))
            return f"{APPLICATION_SCHEMA_PREFIX}{components}"
        if ACCOUNT_DATABASE.fullmatch(member_path):
            rows = _component_revisions(connection)
            execution_revision = snapshot_schema.execution_schema_revision
            if type(execution_revision) is not int or execution_revision <= 0:
                raise BackupManifestError("account execution schema is unsupported")
            if rows != {"execution": execution_revision}:
                raise BackupManifestError("account execution schema is unsupported")
            if _schema_catalog(connection) != schema_catalog(member_path):
                raise BackupManifestError(
                    "account execution database schema structure is incompatible"
                )
            snapshot_row = connection.execute(
                "SELECT data FROM snapshot WHERE singleton=1"
            ).fetchone()
            identity_row = connection.execute(
                "SELECT environment,account_id FROM identity WHERE singleton=1"
            ).fetchone()
            if snapshot_row is not None:
                serialized_snapshot = snapshot_row[0]
                if not isinstance(serialized_snapshot, str):
                    raise BackupManifestError("account ledger snapshot is invalid")
                try:
                    snapshot_environment, snapshot_account_id = snapshot_schema.validate_snapshot(
                        serialized_snapshot
                    )
                except (BackupManifestError, UnicodeError, TypeError, ValueError) as exc:
                    raise BackupManifestError(
                        "account ledger snapshot is invalid or unsupported"
                    ) from exc
                if identity_row is None or (
                    snapshot_environment,
                    snapshot_account_id,
                ) != (identity_row[0], identity_row[1]):
                    raise BackupManifestError(
                        "account ledger snapshot identity does not match its database"
                    )
            if identity_row is not None and identity_row[0] not in {"paper", "live"}:
                raise BackupManifestError("account environment identity is invalid")
            return account_schema_version(snapshot_schema)
    except sqlite3.Error as exc:
        raise BackupManifestError(f"SQLite database is invalid: {member_path}") from exc
    finally:
        connection.close()
    raise BackupManifestError("unsupported SQLite member")


def _schema_catalog(
    connection: sqlite3.Connection,
) -> tuple[tuple[str, str, str, str], ...]:
    objects = connection.execute(
        "SELECT type,name,tbl_name,sql FROM sqlite_master "
        "WHERE name NOT LIKE 'sqlite_%' ORDER BY type,name"
    ).fetchall()
    return tuple(
        (
            kind,
            name,
            table_name,
            statement.strip(),
        )
        for kind, name, table_name, statement in objects
        if isinstance(statement, str)
    )


def _component_revisions(connection: sqlite3.Connection) -> dict[str, int]:
    exists = connection.execute(
        "SELECT 1 FROM sqlite_master WHERE type='table' "
        "AND name='copytrading_engine_schema_revisions'"
    ).fetchone()
    if exists is None:
        return {}
    rows = connection.execute(
        "SELECT component,revision FROM copytrading_engine_schema_revisions ORDER BY component"
    ).fetchall()
    if any(not isinstance(name, str) or type(revision) is not int for name, revision in rows):
        raise BackupManifestError("SQLite component schema table is invalid")
    return {name: revision for name, revision in rows}


def account_environment(path: Path) -> str:
    """The ledger's environment. Its broker account number is checked against the broker, never
    against the account's folder, which holds the app's own name for the account."""
    connection = sqlite3.connect(path)
    try:
        row = connection.execute(
            "SELECT environment,account_id FROM identity WHERE singleton=1"
        ).fetchone()
    except sqlite3.Error as exc:
        raise BackupManifestError("account identity is unavailable") from exc
    finally:
        connection.close()
    if row is None or row[0] not in {"paper", "live"} or not isinstance(row[1], str):
        raise BackupManifestError("account identity is invalid")
    return row[0]


def validate_sqlite(
    path: Path,
    member_path: str,
    installation_id: str,
    schema_catalog: SchemaCatalogProvider,
    snapshot_schema: AccountSnapshotSchemaProvider,
) -> str:
    schema_version = sqlite_schema_version(path, member_path, schema_catalog, snapshot_schema)
    if member_path == "application.db":
        connection = sqlite3.connect(path)
        try:
            row = connection.execute(
                "SELECT value FROM engine_metadata WHERE key='instance_id'"
            ).fetchone()
        except sqlite3.Error as exc:
            raise BackupManifestError("operational installation identity is unavailable") from exc
        finally:
            connection.close()
        if row is None or row[0] != installation_id:
            raise BackupManifestError("operational database belongs to a different installation")
    elif ACCOUNT_DATABASE.fullmatch(member_path):
        account_environment(path)
        connection = sqlite3.connect(path)
        try:
            snapshot_row = connection.execute(
                "SELECT data FROM snapshot WHERE singleton=1"
            ).fetchone()
        except sqlite3.Error as exc:
            raise BackupManifestError("account ledger state is unavailable") from exc
        finally:
            connection.close()
        if snapshot_row is None:
            raise BackupManifestError("account ledger state is incomplete")
    return schema_version


def require_manual_disabled_account(path: Path) -> None:
    connection = sqlite3.connect(path)
    try:
        row = connection.execute("SELECT data FROM snapshot WHERE singleton=1").fetchone()
        if row is None or not isinstance(row[0], str):
            raise BackupManifestError("restored account state is unavailable")
        snapshot = json_object(row[0].encode("utf-8"))
        control = snapshot.get("control")
        if not isinstance(control, dict) or (
            control.get("entry_permission"),
            control.get("recovery_preference"),
        ) != ("disabled", "manual"):
            raise BackupManifestError("restored account is not durably manual-disabled")
        commands = control.get("commands")
        manual_command = (
            next(
                (
                    result
                    for result in commands.values()
                    if isinstance(result, dict)
                    and isinstance(result.get("command"), dict)
                    and result["command"].get("action") == "restore_manual"
                    and result.get("entry_permission") == "disabled"
                    and result.get("recovery_preference") == "manual"
                ),
                None,
            )
            if isinstance(commands, dict)
            else None
        )
        journal_row = connection.execute(
            "SELECT event FROM journal ORDER BY id DESC LIMIT 1"
        ).fetchone()
        if manual_command is None or journal_row is None:
            raise BackupManifestError("restored account manual state lacks its audit event")
        event = json_object(journal_row[0].encode("utf-8"))
        payload = event.get("payload")
        if (
            not isinstance(payload, dict)
            or payload.get("kind") != "account_control_changed"
            or payload.get("result") != manual_command
        ):
            raise BackupManifestError("restored account manual state lacks its audit event")
    except sqlite3.Error as exc:
        raise BackupManifestError("restored account state is unavailable") from exc
    finally:
        connection.close()
