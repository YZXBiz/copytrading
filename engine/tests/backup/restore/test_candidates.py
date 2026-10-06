"""Restore candidates publish atomically, survive restarts, and reap their leftovers."""

import hashlib
import json
import shutil
import sqlite3
import subprocess
import sys
import uuid
from contextlib import asynccontextmanager
from pathlib import Path
from types import SimpleNamespace

import pytest

from copytrading_engine.backup import manifest as manifest_module
from copytrading_engine.backup import service as service_module
from copytrading_engine.backup.manifest import BackupManifestError
from copytrading_engine.backup.restore import candidates as candidates_module

from ..builders import backup_service, execution_database_bytes, write_archive


def test_restore_candidate_uses_bounded_staging_id_and_preserves_preview(tmp_path):
    owner = tmp_path / "stable-owner"
    generation = owner / "generations" / str(uuid.uuid4())
    generation.mkdir(parents=True)
    installation_id = str(uuid.uuid4())
    (owner / "installation-id").write_text(installation_id + "\n")
    current_generation = generation.name
    (owner / "active-generation").write_text(current_generation + "\n")
    archive = tmp_path / "backup.zip"
    write_archive(archive, [], installation_id=installation_id)

    @asynccontextmanager
    async def fence():
        yield

    service = backup_service(
        generation,
        lambda: fence(),
        owner_support_directory=owner,
    )
    staged, _ = service.stage_restore(archive, service.staging_root)
    preview_before = {
        member.relative_to(staged).as_posix(): hashlib.sha256(member.read_bytes()).hexdigest()
        for member in staged.rglob("*")
        if member.is_file()
    }

    candidate_id = service.prepare_restore_candidate(staged.name)

    assert candidate_id == str(uuid.UUID(candidate_id))
    candidate = owner / "generations" / candidate_id
    assert candidate.is_dir()
    assert candidate != staged
    assert (owner / "active-generation").read_text().strip() == current_generation
    assert (owner / ".restore-manual-disabled").is_file()
    assert preview_before == {
        member.relative_to(staged).as_posix(): hashlib.sha256(member.read_bytes()).hexdigest()
        for member in staged.rglob("*")
        if member.is_file()
    }

    with pytest.raises(BackupManifestError, match="staging identifier"):
        service.prepare_restore_candidate("../" + current_generation)


def test_restore_candidate_keeps_published_candidate_when_gate_persistence_raises_after_install(
    tmp_path, monkeypatch
):
    from copytrading_engine.backup.restore.gate import restore_manual_disabled

    owner = tmp_path / "stable-owner"
    generation = owner / "generations" / str(uuid.uuid4())
    generation.mkdir(parents=True)
    installation_id = str(uuid.uuid4())
    (owner / "installation-id").write_text(installation_id + "\n")
    (owner / "active-generation").write_text(generation.name + "\n")
    archive = tmp_path / "backup.zip"
    write_archive(archive, [], installation_id=installation_id)

    @asynccontextmanager
    async def fence():
        yield

    service = backup_service(generation, lambda: fence(), owner_support_directory=owner)
    staged, _ = service.stage_restore(archive, service.staging_root)
    persist_gate = service_module.persist_restore_manual_disabled

    def install_then_fail(marker_path, payload):
        persist_gate(marker_path, payload)
        raise OSError("injected directory fsync failure after marker install")

    monkeypatch.setattr(service_module, "persist_restore_manual_disabled", install_then_fail)
    with pytest.raises(OSError, match="after marker install"):
        service.prepare_restore_candidate(staged.name)

    marker_path = owner / ".restore-manual-disabled"
    assert restore_manual_disabled(marker_path)
    candidate_id = json.loads(marker_path.read_text())["candidate_generation"]
    assert (owner / "generations" / candidate_id).is_dir()


def test_restore_candidate_retains_intent_when_published_candidate_cleanup_fails(
    tmp_path, monkeypatch
):
    owner = tmp_path / "stable-owner"
    generations = owner / "generations"
    generation = generations / str(uuid.uuid4())
    generation.mkdir(parents=True)
    installation_id = str(uuid.uuid4())
    (owner / "installation-id").write_text(installation_id + "\n")
    (owner / "active-generation").write_text(generation.name + "\n")
    archive = tmp_path / "backup.zip"
    write_archive(archive, [], installation_id=installation_id)

    @asynccontextmanager
    async def fence():
        yield

    service = backup_service(generation, lambda: fence(), owner_support_directory=owner)
    staged, _ = service.stage_restore(archive, service.staging_root)

    def fail_gate_persistence(marker_path, payload):
        raise OSError("injected gate publication failure")

    original_rmtree = shutil.rmtree

    def fail_candidate_removal(path, *args, **kwargs):
        candidate = Path(path)
        if candidate.parent == generations and candidate.name != generation.name:
            raise OSError("injected candidate cleanup failure")
        original_rmtree(path, *args, **kwargs)

    with monkeypatch.context() as injected:
        injected.setattr(service_module, "persist_restore_manual_disabled", fail_gate_persistence)
        injected.setattr(shutil, "rmtree", fail_candidate_removal)
        with pytest.raises(BackupManifestError, match="could not be removed"):
            service.prepare_restore_candidate(staged.name)

    intent_path = owner / candidates_module._CANDIDATE_INTENT_NAME
    assert intent_path.is_file()
    intent = json.loads(intent_path.read_text())
    orphan = generations / intent["candidate_generation"]
    assert orphan.is_dir()
    assert not (owner / ".restore-manual-disabled").exists()

    candidate_id = service.prepare_restore_candidate(staged.name)
    assert not orphan.exists()
    assert json.loads(intent_path.read_text())["candidate_generation"] == candidate_id
    assert (generations / candidate_id).is_dir()
    assert (owner / ".restore-manual-disabled").is_file()


def test_pending_restore_candidate_status_and_guarded_abort(tmp_path):
    from copytrading_engine.backup.restore.gate import restore_manual_disabled

    owner = tmp_path / "stable-owner"
    generations = owner / "generations"
    generation = generations / str(uuid.uuid4())
    generation.mkdir(parents=True)
    installation_id = str(uuid.uuid4())
    (owner / "installation-id").write_text(installation_id + "\n")
    (owner / "active-generation").write_text(generation.name + "\n")
    archive = tmp_path / "backup.zip"
    write_archive(archive, [], installation_id=installation_id)

    @asynccontextmanager
    async def fence():
        yield

    service = backup_service(generation, lambda: fence(), owner_support_directory=owner)
    staged, _ = service.stage_restore(archive, service.staging_root)
    candidate_id = service.prepare_restore_candidate(staged.name)
    candidate_directory = generations / candidate_id

    status = service.pending_restore_candidate()
    assert status is not None
    assert status.candidate_id == candidate_id
    assert status.previous_generation == generation.name
    assert status.active_generation == generation.name
    assert status.candidate_valid is True
    assert status.environment_ids == ()

    (owner / "active-generation").write_text(candidate_id + "\n")
    with pytest.raises(BackupManifestError, match="switched back"):
        service.abort_restore_candidate(candidate_id)
    assert candidate_directory.is_dir()
    assert restore_manual_disabled(owner / ".restore-manual-disabled")

    (owner / "active-generation").write_text(generation.name + "\n")
    service.abort_restore_candidate(candidate_id)
    assert not candidate_directory.exists()
    assert not restore_manual_disabled(owner / ".restore-manual-disabled")
    assert not (owner / candidates_module._CANDIDATE_INTENT_NAME).exists()
    assert service.pending_restore_candidate() is None


def test_restore_candidate_persists_canonical_manifest_and_candidate_hashes(tmp_path):
    owner = tmp_path / "stable-owner"
    generation = owner / "generations" / str(uuid.uuid4())
    generation.mkdir(parents=True)
    installation_id = str(uuid.uuid4())
    (owner / "installation-id").write_text(installation_id + "\n")
    (owner / "active-generation").write_text(generation.name + "\n")
    archive = tmp_path / "backup.zip"
    write_archive(archive, [], installation_id=installation_id)

    @asynccontextmanager
    async def fence():
        yield

    service = backup_service(generation, lambda: fence(), owner_support_directory=owner)
    staged, preview = service.stage_restore(archive, service.staging_root)
    candidate_id = service.prepare_restore_candidate(staged.name)
    candidate = owner / "generations" / candidate_id
    manifest_path = candidate / ".restore-candidate-manifest.json"

    assert manifest_path.is_file()
    record = json.loads(manifest_path.read_text())
    assert record["manifest"] == manifest_module.manifest_dict(preview.manifest)
    assert record["manifest_sha256"] == manifest_module.manifest_digest(preview.manifest)
    assert record["candidate_members"] == [
        {
            "path": member.path,
            "size": (candidate / member.path).stat().st_size,
            "sha256": hashlib.sha256((candidate / member.path).read_bytes()).hexdigest(),
        }
        for member in preview.manifest.members
    ]
    marker = json.loads((owner / ".restore-manual-disabled").read_text())
    assert (
        marker["candidate_manifest_sha256"]
        == hashlib.sha256(manifest_path.read_bytes()).hexdigest()
    )


def test_restore_candidate_validation_survives_service_restart_and_detects_member_changes(tmp_path):
    owner = tmp_path / "stable-owner"
    generation = owner / "generations" / str(uuid.uuid4())
    generation.mkdir(parents=True)
    installation_id = str(uuid.uuid4())
    (owner / "installation-id").write_text(installation_id + "\n")
    (owner / "active-generation").write_text(generation.name + "\n")
    archive = tmp_path / "backup.zip"
    write_archive(archive, [], installation_id=installation_id)

    @asynccontextmanager
    async def fence():
        yield

    service = backup_service(generation, lambda: fence(), owner_support_directory=owner)
    staged, preview = service.stage_restore(archive, service.staging_root)
    candidate_id = service.prepare_restore_candidate(staged.name)
    restarted_service = backup_service(generation, lambda: fence(), owner_support_directory=owner)

    assert restarted_service.validate_restore_candidate(candidate_id) == preview.manifest

    candidate_database = owner / "generations" / candidate_id / "application.db"
    candidate_database.write_bytes(b"changed after service restart")
    with pytest.raises(BackupManifestError, match="candidate member changed"):
        restarted_service.validate_restore_candidate(candidate_id)


def test_gated_candidate_bootstrap_and_read_only_preflight_preserve_candidate_hashes(tmp_path):
    from pydantic import SecretStr

    from copytrading_engine.backup.restore.inspector import SQLiteRestoreCandidateInspector
    from copytrading_engine.execution.application.restore_preflight import (
        RestoreBrokerCredential,
        RestoreCandidatePreflight,
    )
    from copytrading_engine.host.installation import Installation
    from copytrading_engine.host.self_test.model import SubmitSelfTest
    from copytrading_engine.host.self_test.store import SQLiteSelfTestStore

    owner = tmp_path / "stable-owner"
    generation = owner / "generations" / str(uuid.uuid4())
    generation.mkdir(parents=True)
    installation_id = str(uuid.uuid4())
    (owner / "installation-id").write_text(installation_id + "\n")
    (owner / "active-generation").write_text(generation.name + "\n")

    account_id = "acct-a"
    configuration = json.dumps(
        {
            "version": 1,
            "configuration": {
                "version": 6,
                "accounts": [{"id": account_id, "environment": "paper", "policy": {}}],
            },
            "secretRevision": None,
            "pendingActivation": None,
        }
    ).encode()
    archive = tmp_path / "backup.zip"
    write_archive(
        archive,
        [
            ("trading-configuration.json", configuration),
            (
                f"accounts/{account_id}/execution.sqlite3",
                execution_database_bytes(tmp_path / "execution.sqlite3", account_id, "paper"),
            ),
        ],
        installation_id=installation_id,
        environment_ids=(f"paper:{account_id}",),
    )

    @asynccontextmanager
    async def fence():
        yield

    backups = backup_service(
        generation,
        lambda: fence(),
        owner_support_directory=owner,
    )
    staged, _ = backups.stage_restore(archive, backups.staging_root)
    candidate_id = backups.prepare_restore_candidate(staged.name)
    (owner / "active-generation").write_text(candidate_id + "\n")
    candidate = owner / "generations" / candidate_id
    candidate_hashes = {
        member.path: hashlib.sha256((candidate / member.path).read_bytes()).hexdigest()
        for member in backups.validate_restore_candidate(candidate_id).members
    }

    # This is the gated bootstrap path: it opens the selected candidate store
    # without switching SQLite journal mode or creating files in the generation.
    with (
        Installation(
            candidate / "application.db",
            instance_id=installation_id,
            lock_path=owner / ".engine.lock",
            read_only=True,
        ) as installation,
        SQLiteSelfTestStore(installation) as store,
    ):
        assert store.counts() == (0, 0, 0)
    assert backups.validate_restore_candidate(candidate_id)

    class ReadOnlyBroker:
        def restore_evidence(self, snapshot, created_at):
            assert snapshot.control.entry_permission == "disabled"
            assert snapshot.control.recovery_preference == "manual"
            return SimpleNamespace(
                complete=True,
                account=SimpleNamespace(id=snapshot.account_id, active=True),
                environment=snapshot.environment,
                positions={},
                open_order_client_ids=(),
                known_orders={},
                orders_after_snapshot=(),
                activity_ids_after_snapshot=(),
            )

        def close(self):
            return None

    service = RestoreCandidatePreflight(
        SQLiteRestoreCandidateInspector(backups),
        lambda credential: ReadOnlyBroker(),
    )
    result = service.preflight_restore_candidate(
        candidate_id,
        (
            RestoreBrokerCredential(
                account_id=account_id,
                environment="paper",
                key=SecretStr("restore-key"),
                secret=SecretStr("restore-secret"),
            ),
        ),
    )
    actual_candidate_files = {
        path.relative_to(candidate).as_posix() for path in candidate.rglob("*") if path.is_file()
    }
    assert actual_candidate_files == {*candidate_hashes, manifest_module.CANDIDATE_MANIFEST_NAME}
    backups.resolve_active_restore_candidate(candidate_id)

    assert result.eligible
    assert result.checked_account_count == 1
    assert result.blockers == ()
    assert candidate_hashes == {
        member.path: hashlib.sha256((candidate / member.path).read_bytes()).hexdigest()
        for member in backups.validate_restore_candidate(candidate_id).members
    }

    # A gated candidate exits after clearing the gate. The owner then relaunches
    # this same generation with a normal writable store; the account stays manual.
    backups.complete_restore_candidate(candidate_id)
    assert not (owner / ".restore-manual-disabled").exists()
    account_database = candidate / "accounts" / account_id / "execution.sqlite3"
    connection = sqlite3.connect(f"{account_database.as_uri()}?mode=ro&immutable=1", uri=True)
    try:
        restored_state = json.loads(
            connection.execute("SELECT data FROM snapshot WHERE singleton=1").fetchone()[0]
        )
    finally:
        connection.close()
    assert restored_state["control"]["entry_permission"] == "disabled"
    assert restored_state["control"]["recovery_preference"] == "manual"
    with (
        Installation(
            candidate / "application.db",
            instance_id=installation_id,
            lock_path=owner / ".engine.lock",
        ) as installation,
        SQLiteSelfTestStore(installation) as writable_store,
    ):
        accepted = writable_store.accept(
            SubmitSelfTest(
                "restore-writable-relaunch",
                "Bought AAPL 1/6 at 200",
                ("self-test-a",),
            )
        )
        assert accepted.workflow.command_id == "restore-writable-relaunch"


def test_restore_candidate_reaps_only_unpublished_temporary_generations(tmp_path):
    owner = tmp_path / "stable-owner"
    generations = owner / "generations"
    generation = generations / str(uuid.uuid4())
    generation.mkdir(parents=True)
    installation_id = str(uuid.uuid4())
    (owner / "installation-id").write_text(installation_id + "\n")
    (owner / "active-generation").write_text(generation.name + "\n")
    interrupted = generations / ".restore-candidate-interrupted"
    interrupted.mkdir()
    (interrupted / "partial.sqlite3").write_bytes(b"partial copy")
    external = tmp_path / "external"
    external.mkdir()
    sentinel = external / "keep.txt"
    sentinel.write_text("outside candidate")
    interrupted_link = generations / ".restore-candidate-link"
    interrupted_link.symlink_to(external, target_is_directory=True)
    archive = tmp_path / "backup.zip"
    write_archive(archive, [], installation_id=installation_id)

    @asynccontextmanager
    async def fence():
        yield

    service = backup_service(generation, lambda: fence(), owner_support_directory=owner)
    staged, _ = service.stage_restore(archive, service.staging_root)
    candidate_id = service.prepare_restore_candidate(staged.name)

    assert not interrupted.exists()
    assert not interrupted_link.exists()
    assert sentinel.read_text() == "outside candidate"
    assert generation.is_dir()
    assert (generations / candidate_id).is_dir()


def test_restore_candidate_reaps_uuid_orphan_after_process_dies_between_rename_and_marker(tmp_path):
    owner = tmp_path / "stable-owner"
    generations = owner / "generations"
    generation = generations / str(uuid.uuid4())
    generation.mkdir(parents=True)
    installation_id = str(uuid.uuid4())
    (owner / "installation-id").write_text(installation_id + "\n")
    (owner / "active-generation").write_text(generation.name + "\n")
    published = generations / str(uuid.uuid4())
    published.mkdir()
    (published / "publication-record").write_text("preserve")
    archive = tmp_path / "backup.zip"
    write_archive(archive, [], installation_id=installation_id)

    crash_script = """
import os, sys
from contextlib import asynccontextmanager
from pathlib import Path
from copytrading_engine.backup.schema_catalog import current_operational_schema_catalog
from copytrading_engine.backup.service import BackupRestoreService
from copytrading_engine.execution.adapters.restore_preparer import prepare_restored_account
from copytrading_engine.execution.adapters.sqlite_ledger import current_execution_snapshot_schema

owner, generation, archive = map(Path, sys.argv[1:])
@asynccontextmanager
async def fence():
    yield
service = BackupRestoreService(
    generation,
    lambda: fence(),
    schema_catalog=current_operational_schema_catalog,
    snapshot_schema=current_execution_snapshot_schema,
    owner_support_directory=owner,
    account_preparer=prepare_restored_account,
)
staged, _ = service.stage_restore(archive, service.staging_root)
rename = os.rename
def publish_then_exit(source, destination):
    rename(source, destination)
    os._exit(87)
os.rename = publish_then_exit
service.prepare_restore_candidate(staged.name)
raise SystemExit(88)
"""
    process = subprocess.run(
        [sys.executable, "-c", crash_script, str(owner), str(generation), str(archive)],
        check=False,
        timeout=20,
    )
    assert process.returncode == 87

    candidates_before_retry = {
        child
        for child in generations.iterdir()
        if child.is_dir() and child not in {generation, published}
    }
    assert len(candidates_before_retry) == 1
    orphan = candidates_before_retry.pop()
    assert not (owner / ".restore-manual-disabled").exists()

    @asynccontextmanager
    async def fence():
        yield

    service = backup_service(generation, lambda: fence(), owner_support_directory=owner)
    staged, _ = service.stage_restore(archive, service.staging_root)
    next_candidate = service.prepare_restore_candidate(staged.name)

    assert not orphan.exists()
    assert published.is_dir()
    assert (published / "publication-record").read_text() == "preserve"
    assert (generations / next_candidate).is_dir()


def test_restore_candidate_persists_each_account_disabled_manual_after_gate_clearance(tmp_path):
    from copytrading_engine.backup.restore.gate import clear_restore_manual_disabled

    owner = tmp_path / "stable-owner"
    generation = owner / "generations" / str(uuid.uuid4())
    generation.mkdir(parents=True)
    installation_id = str(uuid.uuid4())
    (owner / "installation-id").write_text(installation_id + "\n")
    current_generation = generation.name
    (owner / "active-generation").write_text(current_generation + "\n")
    account_id = "paper_main"
    configuration = json.dumps(
        {
            "version": 1,
            "configuration": {
                "version": 6,
                "accounts": [{"id": account_id, "environment": "paper", "policy": {}}],
            },
            "secretRevision": None,
            "pendingActivation": None,
        }
    ).encode()
    account_database = execution_database_bytes(tmp_path / "execution.sqlite3", account_id, "paper")
    archive = tmp_path / "backup-with-account.zip"
    write_archive(
        archive,
        [
            ("trading-configuration.json", configuration),
            (f"accounts/{account_id}/execution.sqlite3", account_database),
        ],
        installation_id=installation_id,
        environment_ids=(f"paper:{account_id}",),
    )

    @asynccontextmanager
    async def fence():
        yield

    service = backup_service(generation, lambda: fence(), owner_support_directory=owner)
    staged, _ = service.stage_restore(archive, service.staging_root)
    staged_before = {
        member.relative_to(staged).as_posix(): hashlib.sha256(member.read_bytes()).hexdigest()
        for member in staged.rglob("*")
        if member.is_file()
    }

    candidate_id = service.prepare_restore_candidate(staged.name)
    candidate_database = (
        owner / "generations" / candidate_id / "accounts" / account_id / "execution.sqlite3"
    )
    connection = sqlite3.connect(candidate_database)
    try:
        raw_snapshot = connection.execute("SELECT data FROM snapshot WHERE singleton=1").fetchone()[
            0
        ]
        latest_event = connection.execute(
            "SELECT event FROM journal ORDER BY id DESC LIMIT 1"
        ).fetchone()[0]
    finally:
        connection.close()
    state = json.loads(raw_snapshot)
    event = json.loads(latest_event)
    assert state["control"]["entry_permission"] == "disabled"
    assert state["control"]["recovery_preference"] == "manual"
    assert event["payload"]["result"]["command"]["action"] == "restore_manual"
    assert service.prepare_restore_candidate(staged.name) == candidate_id
    assert {path.name for path in (owner / "generations").iterdir()} == {
        current_generation,
        candidate_id,
    }

    clear_restore_manual_disabled(owner / ".restore-manual-disabled")
    connection = sqlite3.connect(candidate_database)
    try:
        cleared_state = json.loads(
            connection.execute("SELECT data FROM snapshot WHERE singleton=1").fetchone()[0]
        )
    finally:
        connection.close()
    assert cleared_state["control"]["entry_permission"] == "disabled"
    assert cleared_state["control"]["recovery_preference"] == "manual"
    assert staged_before == {
        member.relative_to(staged).as_posix(): hashlib.sha256(member.read_bytes()).hexdigest()
        for member in staged.rglob("*")
        if member.is_file()
    }


def test_restore_candidate_revalidates_staging_before_copy_or_marker(tmp_path):
    owner = tmp_path / "stable-owner"
    generation = owner / "generations" / str(uuid.uuid4())
    generation.mkdir(parents=True)
    installation_id = str(uuid.uuid4())
    (owner / "installation-id").write_text(installation_id + "\n")
    (owner / "active-generation").write_text(generation.name + "\n")
    archive = tmp_path / "backup.zip"
    write_archive(archive, [], installation_id=installation_id)

    @asynccontextmanager
    async def fence():
        yield

    service = backup_service(generation, lambda: fence(), owner_support_directory=owner)
    staged, _ = service.stage_restore(archive, service.staging_root)
    (staged / "application.db").write_bytes(b"changed after preview")

    with pytest.raises(BackupManifestError, match="changed after validation"):
        service.prepare_restore_candidate(staged.name)

    assert (owner / "active-generation").read_text().strip() == generation.name
    assert not (owner / ".restore-manual-disabled").exists()
    assert list((owner / "generations").iterdir()) == [generation]


def test_restore_candidate_preparation_failure_publishes_no_candidate_or_marker(tmp_path):
    from copytrading_engine.backup.restore.gate import restore_manual_disabled

    owner = tmp_path / "stable-owner"
    generation = owner / "generations" / str(uuid.uuid4())
    generation.mkdir(parents=True)
    installation_id = str(uuid.uuid4())
    (owner / "installation-id").write_text(installation_id + "\n")
    (owner / "active-generation").write_text(generation.name + "\n")
    account_id = "paper_main"
    configuration = json.dumps(
        {
            "version": 1,
            "configuration": {
                "version": 6,
                "accounts": [{"id": account_id, "environment": "paper", "policy": {}}],
            },
            "secretRevision": None,
            "pendingActivation": None,
        }
    ).encode()
    account_database = execution_database_bytes(tmp_path / "execution.sqlite3", account_id, "paper")
    archive = tmp_path / "backup-with-account.zip"
    write_archive(
        archive,
        [
            ("trading-configuration.json", configuration),
            (f"accounts/{account_id}/execution.sqlite3", account_database),
        ],
        installation_id=installation_id,
        environment_ids=(f"paper:{account_id}",),
    )

    @asynccontextmanager
    async def fence():
        yield

    service = backup_service(generation, lambda: fence(), owner_support_directory=owner)
    staged, _ = service.stage_restore(archive, service.staging_root)

    def fail_preparation(_path):
        raise RuntimeError("injected account preparation failure")

    service._account_preparer = fail_preparation
    with pytest.raises(BackupManifestError, match="manual-disabled"):
        service.prepare_restore_candidate(staged.name)

    assert {path.name for path in (owner / "generations").iterdir()} == {generation.name}
    assert not restore_manual_disabled(owner / ".restore-manual-disabled")
