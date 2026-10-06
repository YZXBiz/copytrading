"""A backup is one fenced, verified cut across every store."""

import asyncio
import hashlib
import json
import sqlite3
import threading
import uuid
import zipfile
from contextlib import asynccontextmanager
from datetime import UTC, datetime

import pytest

from copytrading_engine.backup import service as service_module
from copytrading_engine.backup.manifest import BackupManifest, BackupManifestError

from .builders import application_database, backup_service


async def test_consistent_backup_waits_for_competing_writer_and_stages_isolated_restore(tmp_path):
    data_dir = tmp_path / "app-support"
    data_dir.mkdir()
    installation_id = str(uuid.uuid4())
    (data_dir / "installation-id").write_text(installation_id + "\n")
    application_database(data_dir / "application.db", installation_id)
    config_path = data_dir / "trading-configuration.json"
    config_path.write_text(
        json.dumps(
            {
                "version": 1,
                "configuration": {
                    "version": 6,
                    "accounts": [{"id": "paper-main", "environment": "paper", "policy": {}}],
                },
                "secretRevision": str(uuid.uuid4()),
                "pendingActivation": None,
            }
        )
    )

    writer_lock = asyncio.Lock()
    writer_entered = asyncio.Event()
    writer_release = asyncio.Event()
    evidence = b"source attachment committed with database write"
    digest = hashlib.sha256(evidence).hexdigest()

    @asynccontextmanager
    async def fence():
        async with writer_lock:
            yield

    async def competing_writer():
        async with writer_lock:
            writer_entered.set()
            await writer_release.wait()
            connection = sqlite3.connect(data_dir / "application.db")
            try:
                connection.execute("INSERT INTO parser_requests(day,count) VALUES ('2099-01-01',1)")
                connection.commit()
            finally:
                connection.close()
            attachment = data_dir / "attachments" / digest[:2] / digest
            attachment.parent.mkdir(parents=True)
            attachment.write_bytes(evidence)

    service = backup_service(data_dir, lambda: fence())
    archive = tmp_path / "backup.zip"
    writer = asyncio.create_task(competing_writer())
    await writer_entered.wait()
    backup = asyncio.create_task(service.create_backup(archive))
    await asyncio.sleep(0)
    assert not backup.done()
    writer_release.set()
    await writer
    manifest = await backup

    assert {member.path for member in manifest.members} == {
        "application.db",
        "trading-configuration.json",
        f"attachments/{digest[:2]}/{digest}",
    }
    with zipfile.ZipFile(archive) as saved:
        assert saved.namelist()[-1] == "manifest.json"
        restored_db = tmp_path / "restored.db"
        restored_db.write_bytes(saved.read("application.db"))
    connection = sqlite3.connect(restored_db)
    try:
        assert connection.execute(
            "SELECT count FROM parser_requests WHERE day='2099-01-01'"
        ).fetchone() == (1,)
    finally:
        connection.close()

    current_dir = tmp_path / "target-support"
    current_dir.mkdir()
    (current_dir / "installation-id").write_text(installation_id + "\n")
    restore_service = backup_service(current_dir, lambda: fence())
    staging_root = restore_service.staging_root
    staged, preview = restore_service.stage_restore(archive, staging_root)
    assert staged != current_dir
    assert staged.is_dir()
    assert preview.matches_installation
    assert preview.account_ids == ()
    assert preview.credential_references
    assert not (current_dir / "application.db").exists()


def test_failed_manifest_verification_does_not_publish_partial_backup(tmp_path, monkeypatch):
    import copytrading_engine.backup.snapshot as snapshot_module

    data_dir = tmp_path / "app-support"
    data_dir.mkdir()
    installation_id = str(uuid.uuid4())
    (data_dir / "installation-id").write_text(installation_id + "\n")
    application_database(data_dir / "application.db", installation_id)

    @asynccontextmanager
    async def fence():
        yield

    def interrupt(_archive, _schema_catalog, _snapshot_schema):
        raise BackupManifestError("interrupted verification")

    monkeypatch.setattr(snapshot_module, "inspect_backup_archive", interrupt)
    destination = tmp_path / "backup.zip"
    service = backup_service(data_dir, lambda: fence())

    with pytest.raises(BackupManifestError, match="interrupted"):
        asyncio.run(service.create_backup(destination))

    assert not destination.exists()


def test_backup_manifest_timestamp_marks_start_of_the_fenced_multi_store_cut(tmp_path, monkeypatch):
    import copytrading_engine.backup.snapshot as snapshot_module

    data_dir = tmp_path / "app-support"
    data_dir.mkdir()
    installation_id = str(uuid.uuid4())
    (data_dir / "installation-id").write_text(installation_id + "\n")
    snapshot_finished: datetime | None = None

    def slow_snapshot(_data_dir, _staging, _installation_id, _catalog, _snapshot_schema):
        nonlocal snapshot_finished
        import time

        time.sleep(0.02)
        snapshot_finished = datetime.now(UTC)
        return (), ()

    def verify_manifest(archive_path, _schema_catalog, _snapshot_schema):
        with zipfile.ZipFile(archive_path) as archive:
            raw = json.loads(archive.read("manifest.json"))
            return BackupManifest(
                raw["format_version"],
                datetime.fromisoformat(raw["created_at"]),
                raw["installation_id"],
                tuple(raw["environment_ids"]),
                (),
            )

    monkeypatch.setattr(snapshot_module, "_snapshot_members", slow_snapshot)
    monkeypatch.setattr(snapshot_module, "inspect_backup_archive", verify_manifest)

    @asynccontextmanager
    async def fence():
        yield

    manifest = asyncio.run(
        backup_service(data_dir, lambda: fence()).create_backup(tmp_path / "backup.zip")
    )

    assert snapshot_finished is not None
    assert manifest.created_at < snapshot_finished


async def test_cancelled_backup_keeps_writer_fence_until_snapshot_worker_stops(
    tmp_path, monkeypatch
):

    worker_started = threading.Event()
    worker_release = threading.Event()
    fence_entered = asyncio.Event()
    fence_released = asyncio.Event()

    def slow_snapshot(
        _data_dir,
        owner_support_root,
        _destination,
        _schema_catalog,
        _snapshot_schema,
    ):
        worker_started.set()
        assert worker_release.wait(3)
        return BackupManifest(1, datetime.now(UTC), str(uuid.uuid4()), (), ())

    @asynccontextmanager
    async def fence():
        fence_entered.set()
        try:
            yield
        finally:
            fence_released.set()

    monkeypatch.setattr(service_module, "create_backup", slow_snapshot)
    service = backup_service(tmp_path, lambda: fence())
    task = asyncio.create_task(service.create_backup(tmp_path / "backup.zip"))
    await fence_entered.wait()
    assert await asyncio.to_thread(worker_started.wait, 3)
    task.cancel()
    await asyncio.sleep(0)

    assert not task.done()
    assert not fence_released.is_set()
    worker_release.set()
    with pytest.raises(asyncio.CancelledError):
        await task
    assert fence_released.is_set()
