"""A brand-new installation can be backed up before trading has ever started."""

from contextlib import asynccontextmanager

import pytest

from copytrading_engine.backup.manifest import BackupManifestError
from copytrading_engine.backup.schema_catalog import (
    create_application_schema,
    current_operational_schema_catalog,
)
from copytrading_engine.backup.service import BackupRestoreService
from copytrading_engine.execution.adapters.restore_preparer import prepare_restored_account
from copytrading_engine.execution.adapters.sqlite_ledger import current_execution_snapshot_schema
from copytrading_engine.host.installation import Installation
from copytrading_engine.host.self_test.store import SQLiteSelfTestStore


@asynccontextmanager
async def _no_writers():
    yield


def _service(data_dir, owner_support_directory):
    return BackupRestoreService(
        data_dir,
        _no_writers,
        schema_catalog=current_operational_schema_catalog,
        snapshot_schema=current_execution_snapshot_schema,
        owner_support_directory=owner_support_directory,
        account_preparer=prepare_restored_account,
    )


async def test_a_new_installation_is_backup_ready_once_its_schema_is_created(tmp_path):
    data = tmp_path / "data"
    owner = tmp_path / "owner"
    data.mkdir()
    owner.mkdir()
    with (
        Installation(data / "application.db") as installation,
        SQLiteSelfTestStore(installation),
    ):
        (owner / "installation-id").write_text(installation.instance_id + "\n")
        service = _service(data, owner)
        with pytest.raises(BackupManifestError, match="incomplete"):
            await service.create_backup(tmp_path / "before.zip")

        create_application_schema(data / "application.db")
        create_application_schema(data / "application.db")  # starting again changes nothing
        manifest = await service.create_backup(tmp_path / "after.zip")

    assert (tmp_path / "after.zip").is_file()
    assert manifest.installation_id == installation.instance_id


async def test_a_connected_account_is_backed_up_under_its_local_name(tmp_path):
    """The ledger records the broker's account number; its folder holds the app's account name."""
    from .builders import execution_database_bytes

    data = tmp_path / "data"
    owner = tmp_path / "owner"
    data.mkdir()
    owner.mkdir()
    with (
        Installation(data / "application.db") as installation,
        SQLiteSelfTestStore(installation),
    ):
        (owner / "installation-id").write_text(installation.instance_id + "\n")
        create_application_schema(data / "application.db")
        account_dir = data / "accounts" / "primary"
        account_dir.mkdir(parents=True)
        execution_database_bytes(
            account_dir / "execution.sqlite3", "8f3c1a52-alpaca-paper-account", "paper"
        )
        manifest = await _service(data, owner).create_backup(tmp_path / "backup.zip")

    assert any(m.path == "accounts/primary/execution.sqlite3" for m in manifest.members)
