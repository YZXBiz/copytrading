"""Writing a backup archive from a fenced, consistent snapshot of the installation."""

from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import sqlite3
import tempfile
import zipfile
from datetime import UTC, datetime
from pathlib import Path, PurePosixPath
from zipfile import ZIP_DEFLATED

from copytrading_engine.backup.archive import inspect_backup_archive
from copytrading_engine.backup.configuration import (
    read_configuration_identities,
    read_installation_id,
    validate_activation_json,
)
from copytrading_engine.backup.databases import (
    account_environment,
    snapshot_database,
    sqlite_schema_version,
    validate_sqlite,
)
from copytrading_engine.backup.files import (
    copy_private_bytes,
    copy_private_file,
    require_directory,
    require_regular_file,
)
from copytrading_engine.backup.manifest import (
    FORMAT_VERSION,
    MANIFEST_NAME,
    MAX_MEMBER_BYTES,
    BackupManifest,
    BackupManifestError,
    BackupMember,
    is_sqlite_member,
    manifest_dict,
)
from copytrading_engine.backup.ports import AccountSnapshotSchemaProvider, SchemaCatalogProvider


def create_backup(
    data_dir: Path,
    owner_support_directory: Path,
    destination: Path,
    schema_catalog: SchemaCatalogProvider,
    snapshot_schema: AccountSnapshotSchemaProvider,
) -> BackupManifest:
    installation_id = read_installation_id(owner_support_directory)
    parent = destination.parent.resolve(strict=True)
    if destination.name in {"", ".", ".."}:
        raise BackupManifestError("backup destination is invalid")
    destination = parent / destination.name
    try:
        destination.lstat()
    except FileNotFoundError:
        pass
    else:
        raise BackupManifestError("backup destination already exists")

    work: Path | None = None
    try:
        work = Path(tempfile.mkdtemp(prefix=".copytrading-backup-work-", dir=parent))
        os.chmod(work, 0o700)
        staging = work / "files"
        staging.mkdir(mode=0o700)
        # Mark the start of the fenced multi-store cut. Restore reconciliation
        # checks broker activity from this point, including writes during copying.
        snapshot_started_at = datetime.now(UTC)
        members, environment_ids = _snapshot_members(
            data_dir,
            staging,
            installation_id,
            schema_catalog,
            snapshot_schema,
        )
        manifest = BackupManifest(
            format_version=FORMAT_VERSION,
            created_at=snapshot_started_at,
            installation_id=installation_id,
            environment_ids=environment_ids,
            members=members,
        )
        archive_temp = work / "backup.zip"
        with zipfile.ZipFile(
            archive_temp, "w", compression=ZIP_DEFLATED, compresslevel=6
        ) as archive:
            for member in members:
                archive.write(staging.joinpath(*PurePosixPath(member.path).parts), member.path)
            # The manifest is appended only after every payload hash and schema was captured.
            archive.writestr(
                MANIFEST_NAME,
                json.dumps(manifest_dict(manifest), sort_keys=True, separators=(",", ":")),
            )
        os.chmod(archive_temp, 0o600)
        with archive_temp.open("rb") as stream:
            os.fsync(stream.fileno())
        verified = inspect_backup_archive(archive_temp, schema_catalog, snapshot_schema)
        if verified != manifest:
            raise BackupManifestError("backup manifest changed during publication")
        # A same-volume hard link publishes atomically and fails if the chosen name exists.
        os.link(archive_temp, destination, follow_symlinks=False)
        archive_temp.unlink()
        directory_fd = os.open(parent, os.O_RDONLY)
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
        return manifest
    except BackupManifestError:
        raise
    except (OSError, sqlite3.Error, ValueError, zipfile.BadZipFile) as exc:
        raise BackupManifestError("backup could not be completed") from exc
    finally:
        if work is not None:
            shutil.rmtree(work, ignore_errors=True)


def _snapshot_members(
    data_dir: Path,
    staging: Path,
    installation_id: str,
    schema_catalog: SchemaCatalogProvider,
    snapshot_schema: AccountSnapshotSchemaProvider,
) -> tuple[tuple[BackupMember, ...], tuple[str, ...]]:
    members: list[BackupMember] = []
    environment_ids: set[str] = set()
    configured_environments: dict[str, str] = {}
    database = data_dir / "application.db"
    require_regular_file(database, "operational database is unavailable")
    snapshot_database(database, staging / "application.db")
    validate_sqlite(
        staging / "application.db",
        "application.db",
        installation_id,
        schema_catalog,
        snapshot_schema,
    )
    members.append(_member_for(staging, "application.db", schema_catalog, snapshot_schema))

    for name in ("trading-configuration.json", "trading-activation.json"):
        source = data_dir / name
        if source.exists() or source.is_symlink():
            require_regular_file(source, "operational configuration is invalid")
            content = source.read_bytes()
            if len(content) > MAX_MEMBER_BYTES:
                raise BackupManifestError("operational configuration exceeds the supported size")
            copy_private_bytes(staging / name, content)
            if name == "trading-configuration.json":
                identities = read_configuration_identities(content)
                environment_ids.update(identities)
                configured_environments = {
                    identity.split(":", 1)[1]: identity.split(":", 1)[0] for identity in identities
                }
            else:
                validate_activation_json(content)
            members.append(_member_for(staging, name, schema_catalog, snapshot_schema))

    accounts_root = data_dir / "accounts"
    if accounts_root.exists() or accounts_root.is_symlink():
        require_directory(accounts_root, "account evidence path is invalid")
        for account_dir in sorted(accounts_root.iterdir()):
            if not re.fullmatch(r"[A-Za-z0-9_-]{1,64}", account_dir.name):
                raise BackupManifestError("account evidence identity is invalid")
            require_directory(account_dir, "account evidence path is invalid")
            source = account_dir / "execution.sqlite3"
            if not source.exists() and not source.is_symlink():
                raise BackupManifestError("account evidence database is missing")
            require_regular_file(source, "account evidence database is invalid")
            member_path = f"accounts/{account_dir.name}/execution.sqlite3"
            target = staging.joinpath(*PurePosixPath(member_path).parts)
            target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
            snapshot_database(source, target)
            validate_sqlite(
                target,
                member_path,
                installation_id,
                schema_catalog,
                snapshot_schema,
            )
            account_id, environment = account_dir.name, account_environment(target)
            if configured_environments.get(account_id, environment) != environment:
                raise BackupManifestError(
                    "account database environment conflicts with configuration"
                )
            environment_ids.add(f"{environment}:{account_id}")
            members.append(_member_for(staging, member_path, schema_catalog, snapshot_schema))

    attachments_root = data_dir / "attachments"
    if attachments_root.exists() or attachments_root.is_symlink():
        require_directory(attachments_root, "source attachments path is invalid")
        for prefix_dir in sorted(attachments_root.iterdir()):
            if not re.fullmatch(r"[0-9a-f]{2}", prefix_dir.name):
                raise BackupManifestError("source attachment path is invalid")
            require_directory(prefix_dir, "source attachment path is invalid")
            for source in sorted(prefix_dir.iterdir()):
                if (
                    not re.fullmatch(r"[0-9a-f]{64}", source.name)
                    or source.name[:2] != prefix_dir.name
                ):
                    raise BackupManifestError("source attachment path is invalid")
                require_regular_file(source, "source attachment is invalid")
                member_path = f"attachments/{prefix_dir.name}/{source.name}"
                target = staging.joinpath(*PurePosixPath(member_path).parts)
                target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
                digest, _ = copy_private_file(source, target, MAX_MEMBER_BYTES)
                if digest != source.name:
                    raise BackupManifestError("source attachment content hash is invalid")
                members.append(_member_for(staging, member_path, schema_catalog, snapshot_schema))
    return tuple(sorted(members, key=lambda member: member.path)), tuple(sorted(environment_ids))


def _member_for(
    staging: Path,
    member_path: str,
    schema_catalog: SchemaCatalogProvider,
    snapshot_schema: AccountSnapshotSchemaProvider,
) -> BackupMember:
    path = staging.joinpath(*PurePosixPath(member_path).parts)
    digest = hashlib.sha256()
    size = 0
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            size += len(chunk)
            if size > MAX_MEMBER_BYTES:
                raise BackupManifestError("backup member exceeds the supported size")
            digest.update(chunk)
    if is_sqlite_member(member_path):
        schema_version = sqlite_schema_version(path, member_path, schema_catalog, snapshot_schema)
    elif member_path.endswith(".json"):
        schema_version = "json:1"
    else:
        schema_version = "blob:1"
    return BackupMember(member_path, size, digest.hexdigest(), schema_version)
