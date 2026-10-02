"""Preview and staging accept only archives whose members and schemas are exact."""

import hashlib
import json
import sqlite3
import uuid
import zipfile
from contextlib import asynccontextmanager

import pytest

from copytrading_engine.backup import archive as archive_module
from copytrading_engine.backup import manifest as manifest_module
from copytrading_engine.backup import service as service_module
from copytrading_engine.backup.manifest import BackupManifestError
from copytrading_engine.execution.adapters.sqlite_ledger import (
    EXECUTION_SCHEMA,
    current_execution_snapshot_schema,
)
from copytrading_engine.shared.sqlite import ensure_schema

from ..builders import (
    application_database,
    backup_service,
    inspect_backup_archive,
    sqlite_schema_version,
    write_archive,
)


def test_restore_preview_rejects_duplicate_archive_members(tmp_path):
    archive = tmp_path / "backup.zip"
    with pytest.warns(UserWarning, match="Duplicate name"):
        write_archive(archive, [("application.db", b"different database")])

    with pytest.raises(BackupManifestError, match="duplicate"):
        inspect_backup_archive(archive)


def test_restore_preview_reads_installation_identity_from_stable_owner_root(tmp_path):
    owner = tmp_path / "CopyTrading"
    generation = owner / "generations" / "candidate"
    generation.mkdir(parents=True)
    (owner / "installation-id").write_text(str(uuid.uuid4()), encoding="ascii")
    archive = tmp_path / "backup.zip"
    write_archive(archive, [])

    preview = backup_service(
        generation,
        None,
        owner_support_directory=owner,
    ).preview_restore(archive)

    assert not preview.matches_installation


@pytest.mark.parametrize("member_path", ["../escape", "/absolute", "accounts/../escape"])
def test_restore_preview_rejects_path_traversal_members(tmp_path, member_path):
    archive = tmp_path / "backup.zip"
    write_archive(archive, [(member_path, b"payload")])

    with pytest.raises(BackupManifestError, match=r"unsafe|unsupported"):
        inspect_backup_archive(archive)


def test_restore_preview_rejects_a_member_hash_mismatch(tmp_path):
    archive = tmp_path / "backup.zip"
    attachment = b"captured evidence"
    digest = hashlib.sha256(attachment).hexdigest()
    member_path = f"attachments/{digest[:2]}/{digest}"
    write_archive(archive, [(member_path, attachment)], digest_overrides={member_path: "0" * 64})

    with pytest.raises(BackupManifestError, match="hash mismatch"):
        inspect_backup_archive(archive)


def test_restore_preview_rejects_an_incompatible_database_schema(tmp_path):
    archive = tmp_path / "backup.zip"
    write_archive(
        archive,
        [],
        schema_override={"application.db": "sqlite:application:99;components="},
    )

    with pytest.raises(BackupManifestError, match="schema is unsupported"):
        inspect_backup_archive(archive)


def test_restore_preview_rejects_a_database_missing_application_components(tmp_path):
    archive = tmp_path / "incomplete.sqlite.zip"
    write_archive(archive, [], minimal_database=True)

    with pytest.raises(BackupManifestError, match="component schema is incomplete"):
        inspect_backup_archive(archive)


def test_restore_preview_rejects_required_application_tables_with_forged_columns(tmp_path):
    archive = tmp_path / "forged-columns.zip"
    write_archive(archive, [], forged_table="parser_inbox")

    with pytest.raises(BackupManifestError, match="schema structure is incompatible"):
        inspect_backup_archive(archive)


def test_restore_preview_rejects_application_tables_with_forged_constraints(tmp_path):
    archive = tmp_path / "forged-constraints.zip"
    write_archive(archive, [], forged_ddl=True)

    with pytest.raises(BackupManifestError, match="schema structure"):
        inspect_backup_archive(archive)


def test_restore_preview_rejects_case_changed_check_literal(tmp_path):
    archive = tmp_path / "forged-check-literal.zip"
    write_archive(archive, [], forged_literal=True)

    with pytest.raises(BackupManifestError, match="schema structure"):
        inspect_backup_archive(archive)


def test_restore_preview_validates_execution_sqlite_members(tmp_path):
    archive = tmp_path / "invalid-account-db.zip"
    write_archive(
        archive,
        [("accounts/paper_main/execution.sqlite3", b"not a SQLite database")],
    )

    with pytest.raises(BackupManifestError, match=r"SQLite|database|schema"):
        inspect_backup_archive(archive)


def test_restore_staging_revalidates_execution_sqlite_members(tmp_path, monkeypatch):
    archive = tmp_path / "invalid-account-db.zip"
    write_archive(
        archive,
        [("accounts/paper_main/execution.sqlite3", b"not a SQLite database")],
    )
    with zipfile.ZipFile(archive) as saved:
        manifest = archive_module.parse_manifest(saved.read("manifest.json"))

    current_dir = tmp_path / "support"
    current_dir.mkdir()
    (current_dir / "installation-id").write_text(manifest.installation_id + "\n")
    staging_root = current_dir / ".restore-staging"
    staging_root.mkdir(mode=0o700)

    @asynccontextmanager
    async def fence():
        yield

    monkeypatch.setattr(
        service_module,
        "inspect_backup_archive",
        lambda _archive, _schema_catalog, _snapshot_schema: manifest,
    )
    service = backup_service(current_dir, lambda: fence())

    with pytest.raises(BackupManifestError, match=r"SQLite|database|schema"):
        service.stage_restore(archive, staging_root)

    assert list(staging_root.iterdir()) == []


def test_restore_preview_rejects_an_extra_application_table(tmp_path):
    archive = tmp_path / "extra-table.zip"
    write_archive(archive, [], extra_table=True)

    with pytest.raises(BackupManifestError, match="schema structure"):
        inspect_backup_archive(archive)


def test_restore_schema_rejects_an_extra_application_index(tmp_path):
    path = tmp_path / "application.db"
    installation_id = str(uuid.uuid4())
    application_database(path, installation_id)
    connection = sqlite3.connect(path)
    try:
        connection.execute("CREATE INDEX injected_workflow_index ON workflows(created_at)")
        connection.commit()
    finally:
        connection.close()

    with pytest.raises(BackupManifestError, match="schema structure"):
        sqlite_schema_version(path, "application.db")


def test_account_restore_schema_rejects_forged_execution_constraints(tmp_path):
    path = tmp_path / "execution.sqlite3"

    connection = sqlite3.connect(path)
    try:
        ensure_schema(connection, EXECUTION_SCHEMA)
        connection.execute(
            "INSERT INTO identity(singleton,environment,account_id) VALUES (1,'paper','broker-1')"
        )
        connection.commit()
    finally:
        connection.close()
    member_path = "accounts/paper_main/execution.sqlite3"
    assert sqlite_schema_version(path, member_path) == manifest_module.account_schema_version(
        current_execution_snapshot_schema
    )

    connection = sqlite3.connect(path)
    try:
        connection.execute("CREATE INDEX injected_notification_index ON notifications(enqueued_at)")
        connection.commit()
    finally:
        connection.close()
    with pytest.raises(BackupManifestError, match="schema structure"):
        sqlite_schema_version(path, member_path)

    connection = sqlite3.connect(path)
    try:
        connection.execute("DROP INDEX injected_notification_index")
        connection.execute("DROP TABLE notifications")
        connection.execute(
            "CREATE TABLE notifications ("
            "id TEXT,key TEXT,stream_id TEXT,payload TEXT,attempts TEXT,retry_at TEXT,"
            "delivered_at TEXT,enqueued_at TEXT)"
        )
        connection.commit()
    finally:
        connection.close()
    with pytest.raises(BackupManifestError, match="schema structure"):
        sqlite_schema_version(path, member_path)


def test_account_restore_reads_authoritative_execution_and_snapshot_versions(tmp_path):
    from copytrading_engine.execution.domain.ledger_state import LedgerSnapshot
    from copytrading_engine.execution.domain.lifecycle import AccountControl

    path = tmp_path / "execution.sqlite3"
    connection = sqlite3.connect(path)
    try:
        ensure_schema(connection, EXECUTION_SCHEMA)
        connection.execute(
            "INSERT INTO identity(singleton,environment,account_id) VALUES (1,'paper','broker-1')"
        )
        snapshot = LedgerSnapshot(
            account_id="broker-1",
            environment="paper",
            control=AccountControl(entry_permission="enabled", recovery_preference="automatic"),
        )
        connection.execute(
            "INSERT INTO snapshot(singleton,data) VALUES (1,?)", (snapshot.model_dump_json(),)
        )
        connection.commit()
    finally:
        connection.close()

    assert sqlite_schema_version(path, "accounts/paper_main/execution.sqlite3") == (
        manifest_module.account_schema_version(current_execution_snapshot_schema)
    )


def test_account_restore_fails_closed_on_unsupported_or_mismatched_snapshot(tmp_path):

    path = tmp_path / "execution.sqlite3"
    connection = sqlite3.connect(path)
    try:
        ensure_schema(connection, EXECUTION_SCHEMA)
        connection.execute(
            "INSERT INTO identity(singleton,environment,account_id) VALUES (1,'paper','broker-1')"
        )
        connection.execute(
            "INSERT INTO snapshot(singleton,data) VALUES (1,?)",
            (json.dumps({"schema_version": 8, "account_id": "broker-1", "environment": "paper"}),),
        )
        connection.commit()
    finally:
        connection.close()

    with pytest.raises(BackupManifestError, match="snapshot is invalid or unsupported"):
        sqlite_schema_version(path, "accounts/paper_main/execution.sqlite3")


def test_restore_staging_retains_only_the_latest_validated_generation(tmp_path):
    archive = tmp_path / "backup.zip"
    write_archive(archive, [])
    current_dir = tmp_path / "target-support"
    current_dir.mkdir()
    (current_dir / "installation-id").write_text(str(uuid.uuid4()) + "\n")

    @asynccontextmanager
    async def fence():
        yield

    service = backup_service(current_dir, lambda: fence())
    staging_root = service.staging_root
    previous, _ = service.stage_restore(archive, staging_root)
    latest, _ = service.stage_restore(archive, staging_root)

    assert not previous.exists()
    assert latest.is_dir()
    assert list(staging_root.iterdir()) == [latest]


def test_restore_staging_can_live_under_stable_owner_root(tmp_path):
    data_dir = tmp_path / "generations" / "active"
    data_dir.mkdir(parents=True)
    owner_support = tmp_path / "stable-owner"
    owner_support.mkdir()

    @asynccontextmanager
    async def fence():
        yield

    service = backup_service(
        data_dir,
        lambda: fence(),
        owner_support_directory=owner_support,
    )

    assert service.staging_root == owner_support / ".restore-staging"
    assert not (data_dir / ".restore-staging").exists()


def test_restore_staging_rejects_caller_selected_root(tmp_path):
    archive = tmp_path / "backup.zip"
    write_archive(archive, [])
    owner = tmp_path / "stable-owner"
    owner.mkdir()
    (owner / "installation-id").write_text(str(uuid.uuid4()) + "\n")
    caller_root = tmp_path / "caller-staging"
    caller_root.mkdir(mode=0o700)

    @asynccontextmanager
    async def fence():
        yield

    service = backup_service(owner, lambda: fence(), owner_support_directory=owner)

    with pytest.raises(BackupManifestError, match="service-owned"):
        service.stage_restore(archive, caller_root)

    assert list(caller_root.iterdir()) == []
