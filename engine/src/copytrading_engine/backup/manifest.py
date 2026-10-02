"""The backup archive format: its manifest, members, limits, and the previews built from them."""

from __future__ import annotations

import hashlib
import json
import re
from dataclasses import dataclass
from datetime import datetime
from typing import Any

from copytrading_engine.backup.ports import AccountSnapshotSchemaProvider
from copytrading_engine.backup.schema_catalog import APPLICATION_DATABASE_VERSION

ARCHIVE_FORMAT = "copytrading-backup"


FORMAT_VERSION = 1


MANIFEST_NAME = "manifest.json"


MAX_MEMBER_BYTES = 2 * 1024 * 1024 * 1024


CANDIDATE_MANIFEST_NAME = ".restore-candidate-manifest.json"


DIGEST = re.compile(r"^[0-9a-f]{64}$")


ACCOUNT_DATABASE = re.compile(r"^accounts/([A-Za-z0-9_-]{1,64})/execution\.sqlite3$")


RESTORE_STAGE = re.compile(r"^restore-[0-9a-f]{32}$")


APPLICATION_SCHEMA_PREFIX = f"sqlite:application:{APPLICATION_DATABASE_VERSION};components="


def is_sqlite_member(member_path: str) -> bool:
    return member_path == "application.db" or ACCOUNT_DATABASE.fullmatch(member_path) is not None


class BackupManifestError(ValueError):
    """A backup is incomplete, corrupt, unsafe, or incompatible."""


def account_schema_version(snapshot_schema: AccountSnapshotSchemaProvider) -> str:
    execution_revision = snapshot_schema.execution_schema_revision
    snapshot_version = snapshot_schema.snapshot_json_schema_version
    if (
        type(execution_revision) is not int
        or execution_revision <= 0
        or type(snapshot_version) is not int
        or snapshot_version <= 0
    ):
        raise BackupManifestError("account database schema version is invalid")
    return f"sqlite:execution:{execution_revision};ledger_snapshot_json:{snapshot_version}"


@dataclass(frozen=True, slots=True)
class BackupMember:
    path: str
    size: int
    sha256: str
    schema_version: str


@dataclass(frozen=True, slots=True)
class BackupManifest:
    format_version: int
    created_at: datetime
    installation_id: str
    environment_ids: tuple[str, ...]
    members: tuple[BackupMember, ...]


@dataclass(frozen=True, slots=True)
class RestorePreview:
    manifest: BackupManifest
    matches_installation: bool
    account_ids: tuple[str, ...]
    credential_references: tuple[str, ...]


@dataclass(frozen=True, slots=True)
class PendingRestoreCandidate:
    candidate_id: str
    previous_generation: str
    active_generation: str
    installation_id: str
    environment_ids: tuple[str, ...]
    account_ids: tuple[str, ...]
    credential_references: tuple[str, ...]
    candidate_valid: bool


def manifest_dict(manifest: BackupManifest) -> dict[str, Any]:
    return {
        "format": ARCHIVE_FORMAT,
        "format_version": manifest.format_version,
        "created_at": manifest.created_at.isoformat(),
        "installation_id": manifest.installation_id,
        "environment_ids": list(manifest.environment_ids),
        "members": [
            {
                "path": member.path,
                "size": member.size,
                "sha256": member.sha256,
                "schema_version": member.schema_version,
            }
            for member in manifest.members
        ],
    }


def backup_manifest_payload(manifest: BackupManifest) -> dict[str, Any]:
    """Return the public IPC view of a completed archive manifest."""
    return manifest_dict(manifest)


def restore_preview_payload(preview: RestorePreview, staging_id: str) -> dict[str, Any]:
    return {
        "format_version": preview.manifest.format_version,
        "created_at": preview.manifest.created_at.isoformat(),
        "installation_id": preview.manifest.installation_id,
        "matches_installation": preview.matches_installation,
        "environment_ids": list(preview.manifest.environment_ids),
        "account_ids": list(preview.account_ids),
        "credential_references": list(preview.credential_references),
        "staging_id": staging_id,
        "members": [
            {
                "path": member.path,
                "size": member.size,
                "sha256": member.sha256,
                "schema_version": member.schema_version,
            }
            for member in preview.manifest.members
        ],
    }


def json_object(content: bytes) -> dict[str, Any]:
    def unique_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in pairs:
            if key in result:
                raise BackupManifestError("JSON contains a duplicate field")
            result[key] = value
        return result

    try:
        raw = json.loads(content, object_pairs_hook=unique_object)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise BackupManifestError("operational JSON is invalid") from exc
    if not isinstance(raw, dict):
        raise BackupManifestError("operational JSON must be an object")
    return raw


def manifest_digest(manifest: BackupManifest) -> str:
    payload = json.dumps(manifest_dict(manifest), sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()
