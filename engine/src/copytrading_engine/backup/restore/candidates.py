"""Restore staging and candidate generations: intents, manifests, and checks before activation."""

from __future__ import annotations

import hashlib
import json
import os
import shutil
import stat
import uuid
from pathlib import Path, PurePosixPath

from copytrading_engine.backup.archive import open_archive, parse_manifest
from copytrading_engine.backup.configuration import (
    read_configuration_identities,
    read_installation_id,
    validate_activation_json,
)
from copytrading_engine.backup.databases import (
    account_environment,
    require_manual_disabled_account,
    validate_sqlite,
)
from copytrading_engine.backup.files import (
    copy_private_bytes,
    fsync_directory,
    require_directory,
    require_regular_file,
    sha256_file,
    tree_paths,
)
from copytrading_engine.backup.manifest import (
    ACCOUNT_DATABASE,
    CANDIDATE_MANIFEST_NAME,
    DIGEST,
    MAX_MEMBER_BYTES,
    RESTORE_STAGE,
    BackupManifest,
    BackupManifestError,
    is_sqlite_member,
    json_object,
    manifest_dict,
    manifest_digest,
)
from copytrading_engine.backup.ports import AccountSnapshotSchemaProvider, SchemaCatalogProvider
from copytrading_engine.backup.restore.gate import (
    restore_manual_disabled,
    restore_manual_disabled_path,
)

_MAX_CANDIDATE_MANIFEST_BYTES = 16 * 1024 * 1024


_CANDIDATE_INTENT_NAME = ".restore-candidate-intent"


def stage_restore(
    archive_path: Path,
    staging_root: Path,
    manifest: BackupManifest,
    schema_catalog: SchemaCatalogProvider,
    snapshot_schema: AccountSnapshotSchemaProvider,
) -> Path:
    require_directory(staging_root, "restore staging directory is unavailable")
    destination = staging_root / f"restore-{uuid.uuid4().hex}"
    destination.mkdir(mode=0o700)
    try:
        with open_archive(archive_path) as archive:
            configured_environments: dict[str, str] = {}
            ledger_environments: dict[str, str] = {}
            for member in manifest.members:
                target = destination.joinpath(*PurePosixPath(member.path).parts)
                target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
                entry = archive.getinfo(member.path)
                digest = hashlib.sha256()
                size = 0
                descriptor = os.open(
                    target,
                    os.O_CREAT | os.O_EXCL | os.O_WRONLY | getattr(os, "O_NOFOLLOW", 0),
                    0o600,
                )
                with archive.open(entry, "r") as source, os.fdopen(descriptor, "wb") as output:
                    while chunk := source.read(1024 * 1024):
                        size += len(chunk)
                        if size > member.size:
                            raise BackupManifestError("restore member exceeds its declared size")
                        digest.update(chunk)
                        output.write(chunk)
                    output.flush()
                    os.fsync(output.fileno())
                if size != member.size or digest.hexdigest() != member.sha256:
                    raise BackupManifestError("restore member changed after validation")
                os.chmod(target, 0o600)
                if is_sqlite_member(member.path):
                    validate_sqlite(
                        target,
                        member.path,
                        manifest.installation_id,
                        schema_catalog,
                        snapshot_schema,
                    )
                    if account_match := ACCOUNT_DATABASE.fullmatch(member.path):
                        ledger_environments[account_match.group(1)] = account_environment(target)
                elif member.path == "trading-configuration.json":
                    identities = read_configuration_identities(target.read_bytes())
                    configured_environments = {
                        identity.split(":", 1)[1]: identity.split(":", 1)[0]
                        for identity in identities
                    }
                elif member.path.startswith("attachments/"):
                    expected_digest = PurePosixPath(member.path).name
                    if sha256_file(target) != expected_digest:
                        raise BackupManifestError("restore attachment hash does not match its path")
            if any(
                account_id in configured_environments
                and configured_environments[account_id] != environment
                for account_id, environment in ledger_environments.items()
            ):
                raise BackupManifestError(
                    "restored account environment conflicts with configuration"
                )
            environment_ids = {
                *(
                    f"{environment}:{account_id}"
                    for account_id, environment in ledger_environments.items()
                ),
                *(
                    f"{environment}:{account_id}"
                    for account_id, environment in configured_environments.items()
                ),
            }
            if tuple(sorted(environment_ids)) != manifest.environment_ids:
                raise BackupManifestError("restore account identities do not match the manifest")
        return destination
    except BaseException:
        shutil.rmtree(destination, ignore_errors=True)
        raise


def clear_restore_staging(staging_root: Path) -> None:
    require_directory(staging_root, "restore staging directory is unavailable")
    for entry in staging_root.iterdir():
        if not RESTORE_STAGE.fullmatch(entry.name):
            raise BackupManifestError("restore staging contains an unexpected entry")
        try:
            info = entry.lstat()
        except OSError as exc:
            raise BackupManifestError("restore staging entry is unavailable") from exc
        if not stat.S_ISDIR(info.st_mode) or stat.S_ISLNK(info.st_mode):
            raise BackupManifestError("restore staging entry is unsafe")
        shutil.rmtree(entry)


def candidate_intent_payload(
    manifest: BackupManifest,
    previous_generation: str,
    candidate_generation: str,
    candidate_manifest_sha256: str,
) -> bytes:
    return json.dumps(
        {
            "version": 1,
            "installation_id": manifest.installation_id,
            "previous_generation": previous_generation,
            "candidate_generation": candidate_generation,
            "manifest_sha256": manifest_digest(manifest),
            "candidate_manifest_sha256": candidate_manifest_sha256,
        },
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")


def persist_candidate_intent(owner: Path, payload: bytes) -> None:
    path = owner / _CANDIDATE_INTENT_NAME
    try:
        path.lstat()
    except FileNotFoundError:
        pass
    else:
        raise BackupManifestError("another restore candidate intent is already present")
    temporary = owner / f".{_CANDIDATE_INTENT_NAME}.{uuid.uuid4().hex}.tmp"
    directory_flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0)
    directory_descriptor = os.open(owner, directory_flags)
    file_descriptor = -1
    try:
        file_descriptor = os.open(
            temporary,
            os.O_CREAT | os.O_EXCL | os.O_WRONLY | getattr(os, "O_NOFOLLOW", 0),
            0o600,
        )
        remaining = memoryview(payload)
        while remaining:
            written = os.write(file_descriptor, remaining)
            if written <= 0:
                raise OSError("restore candidate intent could not be written")
            remaining = remaining[written:]
        os.fsync(file_descriptor)
        os.close(file_descriptor)
        file_descriptor = -1
        os.replace(temporary, path)
        os.fsync(directory_descriptor)
    finally:
        if file_descriptor >= 0:
            os.close(file_descriptor)
        try:
            temporary.unlink()
        except FileNotFoundError:
            pass
        os.close(directory_descriptor)


def read_candidate_intent(owner: Path) -> dict[str, str | int] | None:
    path = owner / _CANDIDATE_INTENT_NAME
    try:
        path.lstat()
    except FileNotFoundError:
        return None
    require_regular_file(path, "restore candidate intent is unsafe")
    if path.stat().st_size > 4096:
        raise BackupManifestError("restore candidate intent is oversized")
    intent = json_object(path.read_bytes())
    expected_fields = {
        "version",
        "installation_id",
        "previous_generation",
        "candidate_generation",
        "manifest_sha256",
        "candidate_manifest_sha256",
    }
    if (
        set(intent) != expected_fields
        or type(intent.get("version")) is not int
        or intent["version"] != 1
    ):
        raise BackupManifestError("restore candidate intent is invalid")
    for key in ("installation_id", "previous_generation", "candidate_generation"):
        value = intent[key]
        try:
            canonical = str(uuid.UUID(value))
        except (ValueError, TypeError, AttributeError) as exc:
            raise BackupManifestError("restore candidate intent identity is invalid") from exc
        if value != canonical:
            raise BackupManifestError("restore candidate intent identity is invalid")
    if intent["previous_generation"] == intent["candidate_generation"]:
        raise BackupManifestError("restore candidate intent generations are invalid")
    for key in ("manifest_sha256", "candidate_manifest_sha256"):
        if not isinstance(intent[key], str) or not DIGEST.fullmatch(intent[key]):
            raise BackupManifestError("restore candidate intent digest is invalid")
    return intent


def remove_candidate_intent(owner: Path, candidate_generation: str | None = None) -> None:
    path = owner / _CANDIDATE_INTENT_NAME
    intent = read_candidate_intent(owner)
    if intent is None:
        return
    if candidate_generation is not None and intent["candidate_generation"] != candidate_generation:
        raise BackupManifestError("restore candidate intent changed during cleanup")
    path.unlink()
    fsync_directory(owner)


def remove_generation_entry(path: Path) -> bool:
    try:
        info = path.lstat()
    except FileNotFoundError:
        return False
    except OSError as exc:
        raise BackupManifestError("orphan restore generation is unavailable") from exc
    try:
        if stat.S_ISLNK(info.st_mode) or stat.S_ISREG(info.st_mode):
            path.unlink()
        elif stat.S_ISDIR(info.st_mode):
            shutil.rmtree(path)
        else:
            raise BackupManifestError("orphan restore generation has an unsafe type")
    except FileNotFoundError:
        return False
    except OSError as exc:
        raise BackupManifestError("orphan restore generation could not be removed") from exc
    return True


def reap_interrupted_restore_candidates(
    owner: Path,
    generations: Path,
    active_generation: str,
) -> None:
    """Reap only intent-bound unpublished candidates and private temporary entries."""
    intent = read_candidate_intent(owner)
    if intent is not None:
        if intent["installation_id"] != read_installation_id(owner):
            raise BackupManifestError("restore candidate intent belongs to another installation")
        candidate_generation = str(intent["candidate_generation"])
        previous_generation = str(intent["previous_generation"])
        marker_path = restore_manual_disabled_path(owner)
        if restore_manual_disabled(marker_path):
            require_regular_file(marker_path, "restore activation gate is unsafe")
            marker = json_object(marker_path.read_bytes())
            if (
                marker.get("candidate_generation") != candidate_generation
                or marker.get("previous_generation") != previous_generation
                or marker.get("installation_id") != intent["installation_id"]
                or marker.get("manifest_sha256") != intent["manifest_sha256"]
                or marker.get("candidate_manifest_sha256") != intent["candidate_manifest_sha256"]
            ):
                raise BackupManifestError("restore gate does not match candidate intent")
        elif active_generation == candidate_generation:
            remove_candidate_intent(owner, candidate_generation)
        elif active_generation == previous_generation:
            candidate = generations / candidate_generation
            if remove_generation_entry(candidate):
                fsync_directory(generations)
            remove_candidate_intent(owner, candidate_generation)
        else:
            raise BackupManifestError("active generation does not match candidate intent")

    changed = False
    for entry in generations.iterdir():
        if not entry.name.startswith(".restore-candidate-"):
            continue
        if remove_generation_entry(entry):
            changed = True
    if changed:
        fsync_directory(generations)


def read_active_generation(owner: Path) -> str:
    pointer = owner / "active-generation"
    require_regular_file(pointer, "active operational generation is unavailable")
    value = pointer.read_text(encoding="ascii").strip()
    try:
        canonical = str(uuid.UUID(value))
    except (ValueError, TypeError, AttributeError) as exc:
        raise BackupManifestError("active operational generation identity is invalid") from exc
    if value != canonical:
        raise BackupManifestError("active operational generation identity is invalid")
    generation = owner / "generations" / canonical
    require_directory(generation, "active operational generation is unavailable")
    return canonical


def write_candidate_manifest(candidate: Path, manifest: BackupManifest) -> str:
    candidate_members = []
    for member in manifest.members:
        path = candidate.joinpath(*PurePosixPath(member.path).parts)
        require_regular_file(path, "restore candidate member is unavailable")
        candidate_members.append(
            {
                "path": member.path,
                "size": path.stat().st_size,
                "sha256": sha256_file(path),
            }
        )
    record = {
        "version": 1,
        "manifest": manifest_dict(manifest),
        "manifest_sha256": manifest_digest(manifest),
        "candidate_members": candidate_members,
    }
    payload = json.dumps(record, sort_keys=True, separators=(",", ":")).encode("utf-8")
    if len(payload) > _MAX_CANDIDATE_MANIFEST_BYTES:
        raise BackupManifestError("restore candidate manifest exceeds the supported size")
    copy_private_bytes(candidate / CANDIDATE_MANIFEST_NAME, payload)
    return hashlib.sha256(payload).hexdigest()


def _read_candidate_manifest(
    candidate: Path,
) -> tuple[BackupManifest, dict[str, tuple[int, str]], bytes]:
    manifest_path = candidate / CANDIDATE_MANIFEST_NAME
    require_regular_file(manifest_path, "restore candidate manifest is unavailable")
    info = manifest_path.stat()
    if info.st_size > _MAX_CANDIDATE_MANIFEST_BYTES:
        raise BackupManifestError("restore candidate manifest exceeds the supported size")
    payload = manifest_path.read_bytes()
    raw = json_object(payload)
    if set(raw) != {"version", "manifest", "manifest_sha256", "candidate_members"}:
        raise BackupManifestError("restore candidate manifest is invalid")
    if type(raw["version"]) is not int or raw["version"] != 1:
        raise BackupManifestError("restore candidate manifest version is unsupported")
    manifest_value = raw["manifest"]
    if not isinstance(manifest_value, dict):
        raise BackupManifestError("restore candidate manifest is invalid")
    try:
        manifest_content = json.dumps(manifest_value, sort_keys=True, separators=(",", ":")).encode(
            "utf-8"
        )
        manifest = parse_manifest(manifest_content)
    except (TypeError, UnicodeEncodeError) as exc:
        raise BackupManifestError("restore candidate manifest is invalid") from exc
    if manifest_dict(manifest) != manifest_value:
        raise BackupManifestError("restore candidate manifest is not canonical")
    manifest_sha256 = raw["manifest_sha256"]
    if not isinstance(manifest_sha256, str) or not DIGEST.fullmatch(manifest_sha256):
        raise BackupManifestError("restore candidate manifest digest is invalid")
    if manifest_sha256 != manifest_digest(manifest):
        raise BackupManifestError("restore candidate manifest digest does not match")

    candidate_members = raw["candidate_members"]
    if not isinstance(candidate_members, list) or len(candidate_members) != len(manifest.members):
        raise BackupManifestError("restore candidate member hashes are invalid")
    candidate_hashes: dict[str, tuple[int, str]] = {}
    for entry, member in zip(candidate_members, manifest.members, strict=True):
        if not isinstance(entry, dict) or set(entry) != {"path", "size", "sha256"}:
            raise BackupManifestError("restore candidate member hash is invalid")
        member_path = entry["path"]
        size = entry["size"]
        digest = entry["sha256"]
        if (
            member_path != member.path
            or type(size) is not int
            or size < 0
            or size > MAX_MEMBER_BYTES
            or not isinstance(digest, str)
            or not DIGEST.fullmatch(digest)
        ):
            raise BackupManifestError("restore candidate member hash is invalid")
        candidate_hashes[member.path] = (size, digest)
    return manifest, candidate_hashes, payload


def validate_published_restore_candidate(
    owner: Path,
    candidate_identifier: str,
    schema_catalog: SchemaCatalogProvider,
    snapshot_schema: AccountSnapshotSchemaProvider,
) -> BackupManifest:
    try:
        canonical_candidate = str(uuid.UUID(candidate_identifier))
    except (ValueError, TypeError, AttributeError) as exc:
        raise BackupManifestError("restore candidate identifier is invalid") from exc
    if candidate_identifier != canonical_candidate:
        raise BackupManifestError("restore candidate identifier is invalid")
    require_directory(owner, "restore owner directory is unavailable")
    marker_path = restore_manual_disabled_path(owner)
    require_regular_file(marker_path, "restore activation gate is unavailable")
    marker = json_object(marker_path.read_bytes())
    marker_fields = {
        "version",
        "installation_id",
        "previous_generation",
        "candidate_generation",
        "backup_created_at",
        "manifest_sha256",
        "candidate_manifest_sha256",
    }
    if (
        set(marker) != marker_fields
        or type(marker.get("version")) is not int
        or marker["version"] != 2
    ):
        raise BackupManifestError("restore activation gate is invalid")
    for key in ("installation_id", "previous_generation", "candidate_generation"):
        value = marker[key]
        try:
            canonical = str(uuid.UUID(value))
        except (ValueError, TypeError, AttributeError) as exc:
            raise BackupManifestError("restore activation identity is invalid") from exc
        if value != canonical:
            raise BackupManifestError("restore activation identity is invalid")
    if marker["candidate_generation"] != canonical_candidate:
        raise BackupManifestError("restore activation candidate does not match")
    if marker["previous_generation"] == canonical_candidate:
        raise BackupManifestError("restore activation generations are invalid")
    for key in ("manifest_sha256", "candidate_manifest_sha256"):
        if not isinstance(marker[key], str) or not DIGEST.fullmatch(marker[key]):
            raise BackupManifestError("restore activation digest is invalid")
    if not isinstance(marker["backup_created_at"], str):
        raise BackupManifestError("restore activation timestamp is invalid")
    if read_installation_id(owner) != marker["installation_id"]:
        raise BackupManifestError("restore activation belongs to a different installation")
    active_generation = read_active_generation(owner)
    if active_generation not in {marker["previous_generation"], canonical_candidate}:
        raise BackupManifestError("active generation does not match restore activation")

    candidate = owner / "generations" / canonical_candidate
    require_directory(candidate, "restore candidate generation is unavailable")
    manifest, _, payload = _read_candidate_manifest(candidate)
    if hashlib.sha256(payload).hexdigest() != marker["candidate_manifest_sha256"]:
        raise BackupManifestError(
            "restore candidate manifest digest does not match activation gate"
        )
    if manifest_digest(manifest) != marker["manifest_sha256"]:
        raise BackupManifestError("restore archive manifest digest does not match activation gate")
    if manifest.installation_id != marker["installation_id"]:
        raise BackupManifestError("restore candidate installation identity does not match")
    if manifest.created_at.isoformat() != marker["backup_created_at"]:
        raise BackupManifestError("restore candidate timestamp does not match activation gate")
    validate_candidate_generation(candidate, manifest, schema_catalog, snapshot_schema)
    return manifest


def verify_staged_tree(
    staged: Path,
    manifest: BackupManifest,
    schema_catalog: SchemaCatalogProvider,
    snapshot_schema: AccountSnapshotSchemaProvider,
) -> None:
    tree_paths(staged, manifest)
    account_environments: dict[str, str] = {}
    configured_environments: dict[str, str] = {}
    for member in manifest.members:
        path = staged.joinpath(*PurePosixPath(member.path).parts)
        if path.stat().st_size != member.size or sha256_file(path) != member.sha256:
            raise BackupManifestError("restore member changed after validation")
        if is_sqlite_member(member.path):
            actual_schema = validate_sqlite(
                path,
                member.path,
                manifest.installation_id,
                schema_catalog,
                snapshot_schema,
            )
            if actual_schema != member.schema_version:
                raise BackupManifestError("restore member schema changed after validation")
            if account_match := ACCOUNT_DATABASE.fullmatch(member.path):
                account_environments[account_match.group(1)] = account_environment(path)
        elif member.path == "trading-configuration.json":
            identities = read_configuration_identities(path.read_bytes())
            configured_environments = {
                identity.split(":", 1)[1]: identity.split(":", 1)[0] for identity in identities
            }
        elif member.path == "trading-activation.json":
            validate_activation_json(path.read_bytes())
        elif member.path.startswith("attachments/"):
            if sha256_file(path) != PurePosixPath(member.path).name:
                raise BackupManifestError("restore attachment hash does not match its path")
    _validate_restore_environments(manifest, account_environments, configured_environments)


def validate_candidate_generation(
    candidate: Path,
    manifest: BackupManifest,
    schema_catalog: SchemaCatalogProvider,
    snapshot_schema: AccountSnapshotSchemaProvider,
) -> None:
    stored_manifest, candidate_hashes, _ = _read_candidate_manifest(candidate)
    if stored_manifest != manifest:
        raise BackupManifestError("restore candidate archive manifest changed")
    tree_paths(candidate, manifest, allow_candidate_manifest=True)
    account_environments: dict[str, str] = {}
    configured_environments: dict[str, str] = {}
    for member in manifest.members:
        path = candidate.joinpath(*PurePosixPath(member.path).parts)
        recorded_size, recorded_digest = candidate_hashes[member.path]
        if path.stat().st_size != recorded_size or sha256_file(path) != recorded_digest:
            raise BackupManifestError("restore candidate member changed after preparation")
        if account_match := ACCOUNT_DATABASE.fullmatch(member.path):
            actual_schema = validate_sqlite(
                path,
                member.path,
                manifest.installation_id,
                schema_catalog,
                snapshot_schema,
            )
            if actual_schema != member.schema_version:
                raise BackupManifestError("restore account schema changed during preparation")
            require_manual_disabled_account(path)
            account_environments[account_match.group(1)] = account_environment(path)
        else:
            if recorded_size != member.size or recorded_digest != member.sha256:
                raise BackupManifestError("restore member changed during candidate preparation")
            if is_sqlite_member(member.path):
                actual_schema = validate_sqlite(
                    path,
                    member.path,
                    manifest.installation_id,
                    schema_catalog,
                    snapshot_schema,
                )
                if actual_schema != member.schema_version:
                    raise BackupManifestError("restore database schema changed during preparation")
            elif member.path == "trading-configuration.json":
                identities = read_configuration_identities(path.read_bytes())
                configured_environments = {
                    identity.split(":", 1)[1]: identity.split(":", 1)[0] for identity in identities
                }
            elif member.path == "trading-activation.json":
                validate_activation_json(path.read_bytes())
            elif member.path.startswith("attachments/"):
                if sha256_file(path) != PurePosixPath(member.path).name:
                    raise BackupManifestError("restore attachment hash does not match its path")
    _validate_restore_environments(manifest, account_environments, configured_environments)


def _validate_restore_environments(
    manifest: BackupManifest,
    account_environments: dict[str, str],
    configured_environments: dict[str, str],
) -> None:
    if any(
        account_id in configured_environments and configured_environments[account_id] != environment
        for account_id, environment in account_environments.items()
    ):
        raise BackupManifestError("restored account environment conflicts with configuration")
    identities = {
        *(
            f"{environment}:{account_id}"
            for account_id, environment in account_environments.items()
        ),
        *(
            f"{environment}:{account_id}"
            for account_id, environment in configured_environments.items()
        ),
    }
    if tuple(sorted(identities)) != manifest.environment_ids:
        raise BackupManifestError("restore account identities do not match the manifest")
