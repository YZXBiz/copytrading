"""Backup and restore for one installation: create, preview, stage, and activate candidates."""

from __future__ import annotations

import asyncio
import json
import os
import shutil
import tempfile
import threading
import uuid
from pathlib import Path, PurePosixPath

from copytrading_engine.backup.archive import inspect_backup_archive
from copytrading_engine.backup.configuration import (
    archive_credential_references,
    candidate_credential_references,
    read_installation_id,
)
from copytrading_engine.backup.files import (
    copy_private_file,
    fsync_directory,
    fsync_tree,
    require_directory,
)
from copytrading_engine.backup.manifest import (
    ACCOUNT_DATABASE,
    RESTORE_STAGE,
    BackupManifest,
    BackupManifestError,
    PendingRestoreCandidate,
    RestorePreview,
    json_object,
    manifest_digest,
)
from copytrading_engine.backup.ports import (
    AccountSnapshotSchemaProvider,
    BackupFence,
    RestoredAccountPreparer,
    SchemaCatalogProvider,
)
from copytrading_engine.backup.restore.candidates import (
    candidate_intent_payload,
    clear_restore_staging,
    persist_candidate_intent,
    read_active_generation,
    read_candidate_intent,
    reap_interrupted_restore_candidates,
    remove_candidate_intent,
    remove_generation_entry,
    stage_restore,
    validate_candidate_generation,
    validate_published_restore_candidate,
    verify_staged_tree,
    write_candidate_manifest,
)
from copytrading_engine.backup.restore.gate import (
    clear_restore_manual_disabled,
    persist_restore_manual_disabled,
    restore_manual_disabled,
    restore_manual_disabled_path,
)
from copytrading_engine.backup.snapshot import create_backup


class BackupRestoreService:
    """Coordinate a consistent snapshot and isolate an explicitly selected restore."""

    def __init__(
        self,
        data_dir: Path,
        fence: BackupFence,
        *,
        schema_catalog: SchemaCatalogProvider,
        snapshot_schema: AccountSnapshotSchemaProvider,
        owner_support_directory: Path,
        account_preparer: RestoredAccountPreparer | None = None,
    ) -> None:
        self._data_dir = data_dir
        self._fence = fence
        self._schema_catalog = schema_catalog
        self._snapshot_schema = snapshot_schema
        self._owner_support_directory = owner_support_directory
        self._account_preparer = account_preparer
        self._staging_lock = threading.RLock()
        self._staged_manifests: dict[str, BackupManifest] = {}
        self._prepared_candidates: dict[str, str] = {}

    @property
    def staging_root(self) -> Path:
        root = self._owner_support_directory / ".restore-staging"
        try:
            root.mkdir(mode=0o700)
        except FileExistsError:
            pass
        require_directory(root, "restore staging directory is unavailable")
        os.chmod(root, 0o700)
        return root

    async def create_backup(self, destination: Path) -> BackupManifest:
        async with self._fence():
            worker = asyncio.create_task(
                asyncio.to_thread(
                    create_backup,
                    self._data_dir,
                    self._owner_support_directory,
                    destination,
                    self._schema_catalog,
                    self._snapshot_schema,
                )
            )
            cancelled = False
            while True:
                try:
                    result = await asyncio.shield(worker)
                    break
                except asyncio.CancelledError:
                    cancelled = True
                    if worker.done():
                        break
            if cancelled:
                worker.result()
                raise asyncio.CancelledError
            return result

    def preview_restore(self, archive_path: Path) -> RestorePreview:
        manifest = inspect_backup_archive(
            archive_path,
            self._schema_catalog,
            self._snapshot_schema,
        )
        current_identity = read_installation_id(self._owner_support_directory)
        account_ids = tuple(
            sorted(
                member.path.split("/")[1]
                for member in manifest.members
                if ACCOUNT_DATABASE.fullmatch(member.path)
            )
        )
        credential_references = archive_credential_references(archive_path, manifest)
        return RestorePreview(
            manifest=manifest,
            matches_installation=manifest.installation_id == current_identity,
            account_ids=account_ids,
            credential_references=credential_references,
        )

    def stage_restore(self, archive_path: Path, staging_root: Path) -> tuple[Path, RestorePreview]:
        with self._staging_lock:
            service_root = self.staging_root
            try:
                supplied_root = staging_root.resolve(strict=True)
                expected_root = service_root.resolve(strict=True)
            except OSError as exc:
                raise BackupManifestError("restore staging directory is unavailable") from exc
            require_directory(staging_root, "restore staging directory is unsafe")
            if supplied_root != expected_root:
                raise BackupManifestError("restore staging must use the service-owned directory")
            clear_restore_staging(service_root)
            self._staged_manifests.clear()
            self._prepared_candidates.clear()
            preview = self.preview_restore(archive_path)
            staged = stage_restore(
                archive_path,
                service_root,
                preview.manifest,
                self._schema_catalog,
                self._snapshot_schema,
            )
            self._staged_manifests[staged.name] = preview.manifest
            return staged, preview

    def prepare_restore_candidate(self, staging_identifier: str) -> str:
        """Copy one validated preview into an inactive generation and gate startup."""
        with self._staging_lock:
            if not isinstance(staging_identifier, str) or not RESTORE_STAGE.fullmatch(
                staging_identifier
            ):
                raise BackupManifestError("restore staging identifier is invalid")
            prior_candidate = self._prepared_candidates.get(staging_identifier)
            if prior_candidate is not None:
                validate_published_restore_candidate(
                    self._owner_support_directory,
                    prior_candidate,
                    self._schema_catalog,
                    self._snapshot_schema,
                )
                return prior_candidate
            manifest = self._staged_manifests.get(staging_identifier)
            if manifest is None:
                raise BackupManifestError("restore staging identifier is unknown")

            stage_root = self.staging_root
            staged = stage_root / staging_identifier
            require_directory(staged, "restore staging directory is unavailable")
            owner = self._owner_support_directory
            require_directory(owner, "restore owner directory is unavailable")
            if read_installation_id(owner) != manifest.installation_id:
                raise BackupManifestError("backup belongs to a different installation")
            generations = owner / "generations"
            require_directory(generations, "operational generations directory is unavailable")
            active_generation = read_active_generation(owner)
            reap_interrupted_restore_candidates(owner, generations, active_generation)
            if restore_manual_disabled(restore_manual_disabled_path(owner)):
                raise BackupManifestError("another restore activation is already in progress")

            verify_staged_tree(
                staged,
                manifest,
                self._schema_catalog,
                self._snapshot_schema,
            )
            candidate_id = str(uuid.uuid4())
            candidate = generations / candidate_id
            if candidate.exists() or candidate.is_symlink():
                raise BackupManifestError("restore candidate identifier already exists")
            temporary = Path(tempfile.mkdtemp(prefix=".restore-candidate-", dir=generations))
            os.chmod(temporary, 0o700)
            published = False
            try:
                for member in manifest.members:
                    source = staged.joinpath(*PurePosixPath(member.path).parts)
                    target = temporary.joinpath(*PurePosixPath(member.path).parts)
                    target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
                    digest, size = copy_private_file(source, target, member.size)
                    if digest != member.sha256 or size != member.size:
                        raise BackupManifestError("restore member changed after validation")

                account_members = tuple(
                    member for member in manifest.members if ACCOUNT_DATABASE.fullmatch(member.path)
                )
                if account_members and self._account_preparer is None:
                    raise BackupManifestError(
                        "restored account manual-state preparation is unavailable"
                    )
                for member in account_members:
                    account_path = temporary.joinpath(*PurePosixPath(member.path).parts)
                    assert self._account_preparer is not None
                    try:
                        self._account_preparer(account_path)
                    except Exception as exc:
                        raise BackupManifestError(
                            "restored account could not be made manual-disabled"
                        ) from exc

                candidate_manifest_sha256 = write_candidate_manifest(temporary, manifest)
                validate_candidate_generation(
                    temporary,
                    manifest,
                    self._schema_catalog,
                    self._snapshot_schema,
                )
                intent_payload = candidate_intent_payload(
                    manifest,
                    active_generation,
                    candidate_id,
                    candidate_manifest_sha256,
                )
                persist_candidate_intent(owner, intent_payload)
                fsync_tree(temporary)
                os.rename(temporary, candidate)
                published = True
                fsync_directory(generations)

                marker_payload = json.dumps(
                    {
                        "version": 2,
                        "installation_id": manifest.installation_id,
                        "previous_generation": active_generation,
                        "candidate_generation": candidate_id,
                        "backup_created_at": manifest.created_at.isoformat(),
                        "manifest_sha256": manifest_digest(manifest),
                        "candidate_manifest_sha256": candidate_manifest_sha256,
                    },
                    sort_keys=True,
                    separators=(",", ":"),
                ).encode("utf-8")
                persist_restore_manual_disabled(restore_manual_disabled_path(owner), marker_payload)
                self._prepared_candidates[staging_identifier] = candidate_id
                return candidate_id
            except BaseException:
                if published:
                    if not restore_manual_disabled(restore_manual_disabled_path(owner)):
                        remove_generation_entry(candidate)
                        fsync_directory(generations)
                        remove_candidate_intent(owner, candidate_id)
                else:
                    shutil.rmtree(temporary, ignore_errors=True)
                    remove_candidate_intent(owner, candidate_id)
                raise

    def validate_restore_candidate(self, candidate_identifier: str) -> BackupManifest:
        """Reload and validate a prepared candidate using only durable evidence."""
        with self._staging_lock:
            return validate_published_restore_candidate(
                self._owner_support_directory,
                candidate_identifier,
                self._schema_catalog,
                self._snapshot_schema,
            )

    def pending_restore_candidate(self) -> PendingRestoreCandidate | None:
        """Read the durable restore intent and gate after an uncertain IPC result or restart."""
        with self._staging_lock:
            owner = self._owner_support_directory
            marker_path = restore_manual_disabled_path(owner)
            if not restore_manual_disabled(marker_path):
                return None
            marker = json_object(marker_path.read_bytes())
            candidate_id = marker.get("candidate_generation")
            intent = read_candidate_intent(owner)
            if intent is None or not isinstance(candidate_id, str):
                raise BackupManifestError("restore candidate status is unavailable")
            if (
                set(marker)
                != {
                    "version",
                    "installation_id",
                    "previous_generation",
                    "candidate_generation",
                    "backup_created_at",
                    "manifest_sha256",
                    "candidate_manifest_sha256",
                }
                or marker.get("version") != 2
            ):
                raise BackupManifestError("restore gate is invalid")
            active_generation = read_active_generation(owner)
            previous_generation = intent["previous_generation"]
            expected = {
                "installation_id": intent["installation_id"],
                "previous_generation": previous_generation,
                "candidate_generation": candidate_id,
                "manifest_sha256": intent["manifest_sha256"],
                "candidate_manifest_sha256": intent["candidate_manifest_sha256"],
            }
            if any(marker.get(key) != value for key, value in expected.items()):
                raise BackupManifestError("restore gate does not match candidate intent")
            if active_generation not in {previous_generation, candidate_id}:
                raise BackupManifestError("active generation does not match restore candidate")

            environment_ids: tuple[str, ...] = ()
            account_ids: tuple[str, ...] = ()
            credential_references: tuple[str, ...] = ()
            candidate_valid = False
            try:
                manifest = validate_published_restore_candidate(
                    owner,
                    candidate_id,
                    self._schema_catalog,
                    self._snapshot_schema,
                )
            except BackupManifestError:
                pass
            else:
                candidate_valid = True
                environment_ids = manifest.environment_ids
                account_ids = tuple(
                    sorted(
                        member.path.split("/")[1]
                        for member in manifest.members
                        if ACCOUNT_DATABASE.fullmatch(member.path)
                    )
                )
                credential_references = candidate_credential_references(
                    owner / "generations" / candidate_id, manifest
                )
            return PendingRestoreCandidate(
                candidate_id=candidate_id,
                previous_generation=str(previous_generation),
                active_generation=active_generation,
                installation_id=str(intent["installation_id"]),
                environment_ids=environment_ids,
                account_ids=account_ids,
                credential_references=credential_references,
                candidate_valid=candidate_valid,
            )

    def abort_restore_candidate(self, candidate_identifier: str) -> None:
        """Abort only after the previous generation is selected and candidate absence is durable."""
        with self._staging_lock:
            status = self.pending_restore_candidate()
            if status is None or status.candidate_id != candidate_identifier:
                raise BackupManifestError("restore candidate is unavailable for rollback")
            if status.active_generation != status.previous_generation:
                raise BackupManifestError("restore candidate must be switched back before rollback")
            owner = self._owner_support_directory
            candidate = owner / "generations" / candidate_identifier
            if candidate.exists() or candidate.is_symlink():
                if not remove_generation_entry(candidate):
                    raise BackupManifestError("restore candidate could not be removed")
                fsync_directory(owner / "generations")
            clear_restore_manual_disabled(restore_manual_disabled_path(owner))
            remove_candidate_intent(owner, candidate_identifier)
            self._prepared_candidates = {
                staging_id: candidate_id
                for staging_id, candidate_id in self._prepared_candidates.items()
                if candidate_id != candidate_identifier
            }

    def resolve_active_restore_candidate(
        self, candidate_identifier: str
    ) -> tuple[BackupManifest, Path]:
        """Validate and resolve a candidate only after its generation is selected."""
        with self._staging_lock:
            manifest = validate_published_restore_candidate(
                self._owner_support_directory,
                candidate_identifier,
                self._schema_catalog,
                self._snapshot_schema,
            )
            if read_active_generation(self._owner_support_directory) != candidate_identifier:
                raise BackupManifestError("restore candidate generation is not active")
            candidate = self._owner_support_directory / "generations" / candidate_identifier
            require_directory(candidate, "restore candidate generation is unavailable")
            return manifest, candidate

    def complete_restore_candidate(self, candidate_identifier: str) -> None:
        """Clear the durable startup gate after a successful read-only preflight."""
        with self._staging_lock:
            owner = self._owner_support_directory
            manifest = validate_published_restore_candidate(
                owner,
                candidate_identifier,
                self._schema_catalog,
                self._snapshot_schema,
            )
            if read_active_generation(owner) != candidate_identifier:
                raise BackupManifestError("restore candidate generation is not active")
            intent = read_candidate_intent(owner)
            if (
                intent is None
                or intent["installation_id"] != manifest.installation_id
                or intent["candidate_generation"] != candidate_identifier
                or intent["manifest_sha256"] != manifest_digest(manifest)
            ):
                raise BackupManifestError("restore candidate intent does not match activation")
            clear_restore_manual_disabled(restore_manual_disabled_path(owner))
