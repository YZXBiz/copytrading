"""What an installation's saved identity, configuration, and credential references say."""

from __future__ import annotations

import re
import uuid
from pathlib import Path

from copytrading_engine.backup.archive import open_archive, read_limited
from copytrading_engine.backup.files import require_regular_file
from copytrading_engine.backup.manifest import BackupManifest, BackupManifestError, json_object
from copytrading_engine.shared.configuration_version import CONFIGURATION_VERSION


def read_installation_id(data_dir: Path) -> str:
    path = data_dir / "installation-id"
    require_regular_file(path, "installation identity is unavailable")
    value = path.read_text(encoding="ascii").strip()
    try:
        canonical = str(uuid.UUID(value))
    except (ValueError, TypeError, AttributeError) as exc:
        raise BackupManifestError("installation identity is invalid") from exc
    if value.lower() != canonical:
        raise BackupManifestError("installation identity is invalid")
    return canonical


# The fields the app's TradingConfigurationStore writes; its persistence test pins the same set.
SAVED_CONFIGURATION_FIELDS = frozenset(
    {"version", "configuration", "revision", "secretRevision", "pendingActivation"}
)


def read_configuration_identities(content: bytes) -> tuple[str, ...]:
    raw = json_object(content)
    if set(raw) - SAVED_CONFIGURATION_FIELDS:
        raise BackupManifestError("saved configuration has unsupported fields")
    if type(raw.get("version")) is not int or raw.get("version") != 1:
        raise BackupManifestError("saved configuration schema is unsupported")
    revision = raw.get("revision")
    if revision is not None and (
        not isinstance(revision, str) or not re.fullmatch(r"[0-9a-f]{64}", revision)
    ):
        raise BackupManifestError("saved configuration revision is invalid")
    if raw.get("pendingActivation") is not None:
        raise BackupManifestError("saved configuration activation is incomplete")
    configuration = raw.get("configuration")
    if not isinstance(configuration, dict) or configuration.get("version") != CONFIGURATION_VERSION:
        raise BackupManifestError("saved trading configuration is unsupported")
    accounts = configuration.get("accounts")
    if not isinstance(accounts, list):
        raise BackupManifestError("saved trading account identities are invalid")
    identities: list[str] = []
    for account in accounts:
        if not isinstance(account, dict) or set(account) - {"id", "environment", "policy"}:
            raise BackupManifestError("saved trading account identity is invalid")
        account_id, environment = account.get("id"), account.get("environment")
        if (
            not isinstance(account_id, str)
            or not re.fullmatch(r"[A-Za-z0-9_-]{1,64}", account_id)
            or environment not in {"paper", "live"}
        ):
            raise BackupManifestError("saved trading account identity is invalid")
        identities.append(f"{environment}:{account_id}")
    if len({identity.split(":", 1)[1] for identity in identities}) != len(identities):
        raise BackupManifestError("saved trading account identities are duplicated")
    reference = raw.get("secretRevision")
    if reference is not None:
        try:
            canonical_reference = str(uuid.UUID(reference))
        except (ValueError, TypeError, AttributeError) as exc:
            raise BackupManifestError("saved credential reference is invalid") from exc
        if reference.lower() != canonical_reference:
            raise BackupManifestError("saved credential reference is invalid")
    return tuple(sorted(identities))


def validate_activation_json(content: bytes) -> None:
    raw = json_object(content)
    if (
        set(raw) != {"version", "record"}
        or type(raw.get("version")) is not int
        or raw.get("version") != 1
    ):
        raise BackupManifestError("trading activation journal is unsupported")
    record = raw["record"]
    required = {
        "activation_id",
        "candidate_revision",
        "committed_revision",
        "committed_activation_id",
        "phase",
        "error_code",
    }
    if not isinstance(record, dict) or set(record) != required:
        raise BackupManifestError("trading activation journal is invalid")
    try:
        activation_id = record["activation_id"]
        committed_activation_id = record["committed_activation_id"]
        if (
            not isinstance(activation_id, str)
            or str(uuid.UUID(activation_id)) != activation_id
            or (
                committed_activation_id is not None
                and (
                    not isinstance(committed_activation_id, str)
                    or str(uuid.UUID(committed_activation_id)) != committed_activation_id
                )
            )
        ):
            raise ValueError("invalid activation identity")
    except (ValueError, TypeError, AttributeError) as exc:
        raise BackupManifestError("trading activation journal is invalid") from exc
    candidate_revision = record["candidate_revision"]
    committed_revision = record["committed_revision"]
    error_code = record["error_code"]
    if (
        not isinstance(candidate_revision, str)
        or not re.fullmatch(r"[0-9a-f]{64}", candidate_revision)
        or (
            committed_revision is not None
            and (
                not isinstance(committed_revision, str)
                or not re.fullmatch(r"[0-9a-f]{64}", committed_revision)
            )
        )
        or not isinstance(record["phase"], str)
        or record["phase"] not in {"starting", "ready", "failed", "stopped", "interrupted"}
        or (error_code is not None and (not isinstance(error_code, str) or len(error_code) > 64))
    ):
        raise BackupManifestError("trading activation journal is invalid")


def archive_credential_references(archive_path: Path, manifest: BackupManifest) -> tuple[str, ...]:
    config_member = next(
        (member for member in manifest.members if member.path == "trading-configuration.json"),
        None,
    )
    if config_member is None:
        return ()
    with open_archive(archive_path) as archive:
        raw = json_object(
            read_limited(archive, archive.getinfo(config_member.path), config_member.size)
        )
    reference = raw.get("secretRevision")
    if reference is None:
        return ()
    try:
        return (str(uuid.UUID(reference)),)
    except (ValueError, TypeError, AttributeError) as exc:
        raise BackupManifestError("saved credential reference is invalid") from exc


def candidate_credential_references(
    candidate: Path,
    manifest: BackupManifest,
) -> tuple[str, ...]:
    config_member = next(
        (member for member in manifest.members if member.path == "trading-configuration.json"),
        None,
    )
    if config_member is None:
        return ()
    raw = json_object((candidate / config_member.path).read_bytes())
    reference = raw.get("secretRevision")
    if reference is None:
        return ()
    try:
        return (str(uuid.UUID(reference)),)
    except (ValueError, TypeError, AttributeError) as exc:
        raise BackupManifestError("saved credential reference is invalid") from exc
