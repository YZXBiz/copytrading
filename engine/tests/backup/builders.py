"""Application and execution databases and archives the backup tests restore from."""

import hashlib
import json
import sqlite3
import uuid
import zipfile
from pathlib import Path

from copytrading_engine.backup import archive as archive_module
from copytrading_engine.backup import databases as databases_module
from copytrading_engine.backup import manifest as manifest_module
from copytrading_engine.backup.schema_catalog import (
    APPLICATION_COMPONENTS,
    APPLICATION_DATABASE_VERSION,
    current_operational_schema_catalog,
)
from copytrading_engine.backup.service import BackupRestoreService
from copytrading_engine.execution.adapters.restore_preparer import prepare_restored_account
from copytrading_engine.execution.adapters.sqlite_ledger import (
    EXECUTION_SCHEMA,
    current_execution_snapshot_schema,
)
from copytrading_engine.host.self_test.store import SELF_TEST_SCHEMA
from copytrading_engine.shared.sqlite import SchemaComponent, ensure_schema

_APPLICATION_SCHEMA_VERSION = f"sqlite:application:{APPLICATION_DATABASE_VERSION};components=" + (
    ",".join(
        f"{component.name}:{component.revision}"
        for component in sorted(APPLICATION_COMPONENTS, key=lambda component: component.name)
    )
)


def inspect_backup_archive(archive_path: Path):
    return archive_module.inspect_backup_archive(
        archive_path,
        current_operational_schema_catalog,
        current_execution_snapshot_schema,
    )


def sqlite_schema_version(path: Path, member_path: str) -> str:
    return databases_module.sqlite_schema_version(
        path,
        member_path,
        current_operational_schema_catalog,
        current_execution_snapshot_schema,
    )


def backup_service(data_dir: Path, fence, *, owner_support_directory: Path | None = None):
    """Tests without generations use one directory as both owner root and data directory."""
    return BackupRestoreService(
        data_dir,
        fence,
        schema_catalog=current_operational_schema_catalog,
        snapshot_schema=current_execution_snapshot_schema,
        owner_support_directory=owner_support_directory or data_dir,
        account_preparer=prepare_restored_account,
    )


def application_database(
    path: Path,
    installation_id: str,
    *,
    minimal: bool = False,
    forged_table: str | None = None,
    forged_ddl: bool = False,
    forged_literal: bool = False,
    extra_table: bool = False,
) -> None:
    connection = sqlite3.connect(path)
    try:
        if minimal:
            connection.execute(
                "CREATE TABLE engine_metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)"
            )
            connection.execute("CREATE TABLE marker (value TEXT NOT NULL)")
        else:
            for component in APPLICATION_COMPONENTS:
                if forged_literal and component is SELF_TEST_SCHEMA:
                    component = SchemaComponent(
                        component.name,
                        component.revision,
                        component.ddl.replace("'captured'", "'CAPTURED'"),
                    )
                ensure_schema(connection, component)
            if forged_table is not None:
                connection.execute(f'DROP TABLE "{forged_table}"')
                connection.execute(f'CREATE TABLE "{forged_table}" (value TEXT)')
            if forged_ddl:
                connection.execute("DROP TABLE parser_requests")
                connection.execute("CREATE TABLE parser_requests (day TEXT, count TEXT)")
            if extra_table:
                connection.execute("CREATE TABLE marker (value TEXT NOT NULL)")
        connection.execute(
            "INSERT INTO engine_metadata VALUES ('instance_id', ?)", (installation_id,)
        )
        connection.execute(f"PRAGMA user_version = {APPLICATION_DATABASE_VERSION}")
        connection.commit()
    finally:
        connection.close()


def _database_bytes(
    path: Path,
    installation_id: str,
    *,
    minimal: bool = False,
    forged_table: str | None = None,
    forged_ddl: bool = False,
    forged_literal: bool = False,
    extra_table: bool = False,
) -> bytes:
    application_database(
        path,
        installation_id,
        minimal=minimal,
        forged_table=forged_table,
        forged_ddl=forged_ddl,
        forged_literal=forged_literal,
        extra_table=extra_table,
    )
    return path.read_bytes()


def write_archive(
    path,
    members,
    *,
    installation_id=None,
    environment_ids=(),
    schema_override=None,
    digest_overrides=None,
    minimal_database=False,
    forged_table=None,
    forged_ddl=False,
    forged_literal=False,
    extra_table=False,
):
    installation_id = installation_id or str(uuid.uuid4())
    payload = _database_bytes(
        path.with_suffix(".db"),
        installation_id,
        minimal=minimal_database,
        forged_table=forged_table,
        forged_ddl=forged_ddl,
        forged_literal=forged_literal,
        extra_table=extra_table,
    )
    schema_override = schema_override or {}
    digest_overrides = digest_overrides or {}
    entries = [("application.db", payload), *members]
    declared_members = []
    for name, content in entries:
        declared_members.append(
            {
                "path": name,
                "size": len(content),
                "sha256": digest_overrides.get(name, hashlib.sha256(content).hexdigest()),
                "schema_version": schema_override.get(
                    name,
                    _APPLICATION_SCHEMA_VERSION
                    if name == "application.db"
                    else manifest_module.account_schema_version(current_execution_snapshot_schema)
                    if name.startswith("accounts/") and name.endswith("/execution.sqlite3")
                    else "json:1"
                    if name in {"trading-configuration.json", "trading-activation.json"}
                    else "blob:1",
                ),
            }
        )
    manifest = {
        "format": "copytrading-backup",
        "format_version": 1,
        "created_at": "2026-09-27T12:00:00+00:00",
        "installation_id": installation_id,
        "environment_ids": list(environment_ids),
        "members": declared_members,
    }
    with zipfile.ZipFile(path, "w") as archive:
        for name, content in entries:
            archive.writestr(name, content)
        archive.writestr("manifest.json", json.dumps(manifest))


def execution_database_bytes(path: Path, account_id: str, environment: str) -> bytes:
    from copytrading_engine.execution.domain.ledger_state import LedgerSnapshot
    from copytrading_engine.execution.domain.lifecycle import AccountControl

    connection = sqlite3.connect(path)
    try:
        ensure_schema(connection, EXECUTION_SCHEMA)
        connection.execute(
            "INSERT INTO identity(singleton,environment,account_id) VALUES (1,?,?)",
            (environment, account_id),
        )
        snapshot = LedgerSnapshot(
            account_id=account_id,
            environment=environment,
            control=AccountControl(entry_permission="enabled", recovery_preference="automatic"),
        )
        connection.execute(
            "INSERT INTO snapshot(singleton,data) VALUES (1,?)", (snapshot.model_dump_json(),)
        )
        connection.commit()
    finally:
        connection.close()
    return path.read_bytes()
