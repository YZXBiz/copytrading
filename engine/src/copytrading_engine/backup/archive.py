"""Reading a backup archive: bounded extraction, member hashing, and manifest validation."""

from __future__ import annotations

import hashlib
import json
import os
import re
import stat
import tempfile
import uuid
import zipfile
from collections.abc import Iterator
from contextlib import contextmanager
from datetime import UTC, datetime
from pathlib import Path, PurePosixPath
from typing import Any

from copytrading_engine.backup.databases import validate_sqlite
from copytrading_engine.backup.manifest import (
    ACCOUNT_DATABASE,
    APPLICATION_SCHEMA_PREFIX,
    ARCHIVE_FORMAT,
    DIGEST,
    FORMAT_VERSION,
    MANIFEST_NAME,
    MAX_MEMBER_BYTES,
    BackupManifest,
    BackupManifestError,
    BackupMember,
    account_schema_version,
    is_sqlite_member,
)
from copytrading_engine.backup.ports import AccountSnapshotSchemaProvider, SchemaCatalogProvider

_MAX_ARCHIVE_BYTES = 8 * 1024 * 1024 * 1024


_MAX_TOTAL_MEMBER_BYTES = 8 * 1024 * 1024 * 1024


_MAX_MEMBER_COUNT = 50_000


_MAX_MANIFEST_BYTES = 1024 * 1024


_ATTACHMENT = re.compile(r"^attachments/[0-9a-f]{2}/[0-9a-f]{64}$")


_TOP_LEVEL_MEMBERS = {
    "application.db",
    "trading-configuration.json",
    "trading-activation.json",
}


def inspect_backup_archive(
    archive_path: Path,
    schema_catalog: SchemaCatalogProvider,
    snapshot_schema: AccountSnapshotSchemaProvider,
) -> BackupManifest:
    """Read and verify every archive member before returning its manifest."""
    try:
        with open_archive(archive_path) as archive:
            entries = archive.infolist()
            if len(entries) > _MAX_MEMBER_COUNT + 1:
                raise BackupManifestError("backup contains too many members")
            names: dict[str, zipfile.ZipInfo] = {}
            for entry in entries:
                _validate_member_name(entry.filename)
                key = entry.filename.casefold()
                if key in names:
                    raise BackupManifestError("backup contains a duplicate member")
                names[key] = entry
                mode = entry.external_attr >> 16
                file_kind = stat.S_IFMT(mode)
                if (
                    file_kind == stat.S_IFLNK
                    or entry.is_dir()
                    or file_kind not in {0, stat.S_IFREG}
                ):
                    raise BackupManifestError("backup contains a non-regular member")
                if entry.file_size > MAX_MEMBER_BYTES:
                    raise BackupManifestError("backup member exceeds the supported size limit")
            manifest_info = names.get(MANIFEST_NAME)
            if manifest_info is None or manifest_info.file_size > _MAX_MANIFEST_BYTES:
                raise BackupManifestError("backup manifest is missing or too large")
            declared = parse_manifest(read_limited(archive, manifest_info, _MAX_MANIFEST_BYTES))

            expected = {member.path: member for member in declared.members}
            payload_entries = {
                entry.filename: entry for entry in entries if entry.filename != MANIFEST_NAME
            }
            if len(payload_entries) != len(declared.members) or set(payload_entries) != set(
                expected
            ):
                raise BackupManifestError("backup manifest does not match its archive members")

            total_size = 0
            for member_path, member in expected.items():
                entry = payload_entries[member_path]
                if entry.file_size != member.size:
                    raise BackupManifestError(f"backup member size mismatch: {member_path}")
                total_size += member.size
                if total_size > _MAX_TOTAL_MEMBER_BYTES:
                    raise BackupManifestError("backup exceeds the supported total size")
                digest, header = _hash_member(archive, entry, member.size)
                if digest != member.sha256:
                    raise BackupManifestError(f"backup member hash mismatch: {member_path}")
                _validate_member_schema(member, header, snapshot_schema)
                if is_sqlite_member(member_path):
                    _validate_archived_sqlite(
                        archive,
                        entry,
                        member,
                        declared.installation_id,
                        schema_catalog,
                        snapshot_schema,
                    )
            return declared
    except BackupManifestError:
        raise
    except (OSError, RuntimeError, ValueError, zipfile.BadZipFile, EOFError) as exc:
        raise BackupManifestError("backup archive cannot be read") from exc


@contextmanager
def open_archive(archive_path: Path) -> Iterator[zipfile.ZipFile]:
    """Open one regular archive without following a path replaced by a symlink."""
    descriptor = os.open(
        archive_path,
        os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0),
    )
    try:
        info = os.fstat(descriptor)
        if not stat.S_ISREG(info.st_mode):
            raise BackupManifestError("backup archive must be a regular file")
        if info.st_size <= 0 or info.st_size > _MAX_ARCHIVE_BYTES:
            raise BackupManifestError("backup archive size is outside the supported limit")
        stream = os.fdopen(descriptor, "rb")
        descriptor = -1
        with stream, zipfile.ZipFile(stream, "r") as archive:
            yield archive
    finally:
        if descriptor >= 0:
            os.close(descriptor)


def read_limited(archive: zipfile.ZipFile, entry: zipfile.ZipInfo, limit: int) -> bytes:
    if entry.file_size > limit:
        raise BackupManifestError("backup member exceeds its declared size")
    with archive.open(entry, "r") as source:
        content = source.read(limit + 1)
    if len(content) > limit:
        raise BackupManifestError("backup member exceeds its declared size")
    return content


def _hash_member(
    archive: zipfile.ZipFile, entry: zipfile.ZipInfo, expected_size: int
) -> tuple[str, bytes]:
    digest = hashlib.sha256()
    size = 0
    header = bytearray()
    with archive.open(entry, "r") as source:
        while chunk := source.read(1024 * 1024):
            size += len(chunk)
            if size > expected_size:
                raise BackupManifestError("backup member exceeds its declared size")
            digest.update(chunk)
            if len(header) < 32:
                header.extend(chunk[: 32 - len(header)])
    if size != expected_size:
        raise BackupManifestError("backup member size mismatch")
    return digest.hexdigest(), bytes(header)


def _validate_member_name(name: str) -> None:
    if not name or "\\" in name or "\x00" in name or name.startswith("/") or ":" in name:
        raise BackupManifestError("backup contains an unsafe member path")
    path = PurePosixPath(name)
    if path.is_absolute() or any(part in {"", ".", ".."} for part in name.split("/")):
        raise BackupManifestError("backup contains an unsafe member path")
    if name == MANIFEST_NAME:
        return
    if (
        name in _TOP_LEVEL_MEMBERS
        or ACCOUNT_DATABASE.fullmatch(name)
        or _ATTACHMENT.fullmatch(name)
    ):
        return
    raise BackupManifestError("backup contains an unsupported member path")


def parse_manifest(content: bytes) -> BackupManifest:
    def unique_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in pairs:
            if key in result:
                raise BackupManifestError("backup manifest contains a duplicate field")
            result[key] = value
        return result

    try:
        raw = json.loads(content, object_pairs_hook=unique_object)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise BackupManifestError("backup manifest is invalid JSON") from exc
    if not isinstance(raw, dict):
        raise BackupManifestError("backup manifest must be an object")
    expected_fields = {
        "format",
        "format_version",
        "created_at",
        "installation_id",
        "environment_ids",
        "members",
    }
    if set(raw) != expected_fields or raw.get("format") != ARCHIVE_FORMAT:
        raise BackupManifestError("backup manifest format is unsupported")
    version = raw.get("format_version")
    if type(version) is not int or version != FORMAT_VERSION:
        raise BackupManifestError("backup manifest version is unsupported")
    installation_id = raw.get("installation_id")
    try:
        canonical_id = str(uuid.UUID(installation_id))
    except (ValueError, TypeError, AttributeError) as exc:
        raise BackupManifestError("backup installation identity is invalid") from exc
    if installation_id.lower() != canonical_id:
        raise BackupManifestError("backup installation identity is invalid")
    created_value = raw.get("created_at")
    if not isinstance(created_value, str):
        raise BackupManifestError("backup timestamp is invalid")
    try:
        created_at = datetime.fromisoformat(created_value)
    except ValueError as exc:
        raise BackupManifestError("backup timestamp is invalid") from exc
    if created_at.tzinfo is None or created_at.utcoffset() is None:
        raise BackupManifestError("backup timestamp must include a timezone")
    environment_ids_raw = raw.get("environment_ids")
    if (
        not isinstance(environment_ids_raw, list)
        or any(
            not isinstance(item, str) or not item or len(item) > 128 for item in environment_ids_raw
        )
        or len(environment_ids_raw) != len(set(environment_ids_raw))
    ):
        raise BackupManifestError("backup account identities are invalid")
    members_raw = raw.get("members")
    if not isinstance(members_raw, list) or not members_raw or len(members_raw) > _MAX_MEMBER_COUNT:
        raise BackupManifestError("backup member list is invalid")
    members: list[BackupMember] = []
    seen_paths: set[str] = set()
    for entry in members_raw:
        if not isinstance(entry, dict) or set(entry) != {
            "path",
            "size",
            "sha256",
            "schema_version",
        }:
            raise BackupManifestError("backup member metadata is invalid")
        member_path = entry["path"]
        _validate_member_name(member_path)
        if member_path == MANIFEST_NAME or member_path in seen_paths:
            raise BackupManifestError("backup manifest contains a duplicate member")
        seen_paths.add(member_path)
        size = entry["size"]
        digest = entry["sha256"]
        schema_version = entry["schema_version"]
        if type(size) is not int or size < 0 or size > MAX_MEMBER_BYTES:
            raise BackupManifestError("backup member size is invalid")
        if not isinstance(digest, str) or not DIGEST.fullmatch(digest):
            raise BackupManifestError("backup member hash is invalid")
        if not isinstance(schema_version, str) or not schema_version or len(schema_version) > 256:
            raise BackupManifestError("backup member schema version is invalid")
        members.append(BackupMember(member_path, size, digest, schema_version))
    if "application.db" not in seen_paths:
        raise BackupManifestError("backup is missing the operational database")
    return BackupManifest(
        format_version=version,
        created_at=created_at.astimezone(UTC),
        installation_id=canonical_id,
        environment_ids=tuple(environment_ids_raw),
        members=tuple(members),
    )


def _validate_member_schema(
    member: BackupMember,
    header: bytes,
    snapshot_schema: AccountSnapshotSchemaProvider,
) -> None:
    if is_sqlite_member(member.path):
        if not member.schema_version.startswith("sqlite:") or not header.startswith(
            b"SQLite format 3\x00"
        ):
            raise BackupManifestError(f"backup SQLite schema is missing: {member.path}")
        if member.path == "application.db" and not member.schema_version.startswith(
            APPLICATION_SCHEMA_PREFIX
        ):
            raise BackupManifestError("backup application database schema is unsupported")
        if ACCOUNT_DATABASE.fullmatch(
            member.path
        ) and member.schema_version != account_schema_version(snapshot_schema):
            raise BackupManifestError("backup account database schema is unsupported")
    elif member.path.endswith(".json") and member.schema_version != "json:1":
        raise BackupManifestError(f"backup JSON schema is unsupported: {member.path}")
    elif member.path.startswith("attachments/") and member.schema_version != "blob:1":
        raise BackupManifestError(f"backup attachment schema is unsupported: {member.path}")


def _validate_archived_sqlite(
    archive: zipfile.ZipFile,
    entry: zipfile.ZipInfo,
    member: BackupMember,
    installation_id: str,
    schema_catalog: SchemaCatalogProvider,
    snapshot_schema: AccountSnapshotSchemaProvider,
) -> None:
    with tempfile.TemporaryDirectory(prefix="copytrading-backup-check-") as temporary:
        target = Path(temporary) / "member.sqlite3"
        size = 0
        with archive.open(entry, "r") as source, target.open("xb") as destination:
            while chunk := source.read(1024 * 1024):
                size += len(chunk)
                if size > member.size:
                    raise BackupManifestError("backup SQLite member exceeds its declared size")
                destination.write(chunk)
        if size != member.size:
            raise BackupManifestError("backup SQLite member size mismatch")
        os.chmod(target, 0o600)
        actual_schema = validate_sqlite(
            target,
            member.path,
            installation_id,
            schema_catalog,
            snapshot_schema,
        )
        if actual_schema != member.schema_version:
            raise BackupManifestError(f"backup SQLite schema mismatch: {member.path}")
