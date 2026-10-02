"""Backup and restore: create, preview, stage, check, and activate a candidate."""

import asyncio
import time
from dataclasses import dataclass
from pathlib import Path
from uuid import uuid4

from copytrading_engine.backup.manifest import backup_manifest_payload, restore_preview_payload
from copytrading_engine.backup.service import BackupRestoreService
from copytrading_engine.execution.application.restore_preflight import (
    RestoreBrokerCredential,
    RestoreCandidatePreflight,
)
from copytrading_engine.host.pipe.requests import (
    AbortRestoreCandidateRequest,
    CompleteRestoreCandidateRequest,
    CreateBackupRequest,
    PipeRequest,
    PrepareRestoreCandidateRequest,
    PreviewRestoreRequest,
    RequestHandler,
    RestoreCandidateStatusRequest,
    RestorePreflightRequest,
)
from copytrading_engine.host.pipe.responses import reply
from copytrading_engine.host.pipe.services import TradingServices
from copytrading_engine.host.pipe.session import PipeSession


@dataclass(frozen=True)
class _RestorePreflightGrant:
    candidate_id: str
    token: str
    expires_at: float


class BackupRestoreHandlers:
    """Back up, then stage, check, and activate a restore candidate; activation ends the session."""

    def __init__(
        self,
        *,
        backup_restore: BackupRestoreService | None,
        restore_preflight: RestoreCandidatePreflight | None,
        trading: TradingServices | None,
        restore_gated: bool,
        session: PipeSession,
    ) -> None:
        self._backup_restore = backup_restore
        self._restore_preflight = restore_preflight
        self._trading = trading
        self._restore_gated = restore_gated
        self._session = session
        self._restore_preflight_grant: _RestorePreflightGrant | None = None

    def handlers(self) -> dict[type[PipeRequest], RequestHandler]:
        return {
            CreateBackupRequest: self._on_create_backup,
            PreviewRestoreRequest: self._on_preview_restore,
            PrepareRestoreCandidateRequest: self._on_prepare_restore_candidate,
            RestoreCandidateStatusRequest: self._on_restore_candidate_status,
            AbortRestoreCandidateRequest: self._on_abort_restore_candidate,
            RestorePreflightRequest: self._on_restore_preflight,
            CompleteRestoreCandidateRequest: self._on_complete_restore_candidate,
        }

    async def _on_create_backup(self, request: CreateBackupRequest) -> bytes:
        if self._backup_restore is None:
            return reply(request.version, request.request_id, error="unavailable")
        destination = Path(request.destination)
        if not destination.is_absolute():
            return reply(request.version, request.request_id, error="invalid_request")
        manifest = await self._backup_restore.create_backup(destination)
        return reply(
            request.version,
            request.request_id,
            ok={"type": "backup", "manifest": backup_manifest_payload(manifest)},
        )

    async def _on_preview_restore(self, request: PreviewRestoreRequest) -> bytes:
        if self._backup_restore is None:
            return reply(request.version, request.request_id, error="unavailable")
        archive_path = Path(request.archive_path)
        if not archive_path.is_absolute():
            return reply(request.version, request.request_id, error="invalid_request")
        staged, preview = await asyncio.to_thread(
            self._backup_restore.stage_restore,
            archive_path,
            self._backup_restore.staging_root,
        )
        return reply(
            request.version,
            request.request_id,
            ok={
                "type": "restore_preview",
                "preview": restore_preview_payload(preview, staged.name),
            },
        )

    async def _on_prepare_restore_candidate(self, request: PrepareRestoreCandidateRequest) -> bytes:
        if self._backup_restore is None:
            return reply(request.version, request.request_id, error="unavailable")
        candidate_id = await asyncio.to_thread(
            self._backup_restore.prepare_restore_candidate,
            request.staging_id,
        )
        return reply(
            request.version,
            request.request_id,
            ok={"type": "restore_candidate", "candidate_id": candidate_id},
        )

    async def _on_restore_candidate_status(self, request: RestoreCandidateStatusRequest) -> bytes:
        if self._backup_restore is None:
            return reply(request.version, request.request_id, error="unavailable")
        pending = await asyncio.to_thread(self._backup_restore.pending_restore_candidate)
        candidate = (
            None
            if pending is None
            else {
                "candidate_id": pending.candidate_id,
                "previous_generation": pending.previous_generation,
                "active_generation": pending.active_generation,
                "installation_id": pending.installation_id,
                "environment_ids": list(pending.environment_ids),
                "account_ids": list(pending.account_ids),
                "credential_references": list(pending.credential_references),
                "candidate_valid": pending.candidate_valid,
            }
        )
        return reply(
            request.version,
            request.request_id,
            ok={"type": "restore_candidate_status", "candidate": candidate},
        )

    async def _on_abort_restore_candidate(self, request: AbortRestoreCandidateRequest) -> bytes:
        if self._backup_restore is None:
            return reply(request.version, request.request_id, error="unavailable")
        await asyncio.to_thread(
            self._backup_restore.abort_restore_candidate,
            request.candidate_id,
        )
        return reply(
            request.version,
            request.request_id,
            ok={"type": "restore_aborted", "candidate_id": request.candidate_id},
        )

    async def _on_restore_preflight(self, request: RestorePreflightRequest) -> bytes:
        self._restore_preflight_grant = None
        if not self._restore_gated or self._trading is None or self._restore_preflight is None:
            return reply(request.version, request.request_id, error="unavailable")
        credentials = tuple(
            RestoreBrokerCredential(
                account_id=account.account_id,
                environment=account.environment,
                key=account.key,
                secret=account.secret,
            )
            for account in request.accounts
        )
        self._trading.lifecycle.register_restore_secrets(
            tuple(
                value
                for account in request.accounts
                for value in (
                    account.key.get_secret_value(),
                    account.secret.get_secret_value(),
                )
            )
        )
        result = await asyncio.to_thread(
            self._restore_preflight.preflight_restore_candidate,
            request.candidate_id,
            credentials,
        )
        completion_token = None
        if result.eligible:
            completion_token = uuid4().hex
            self._restore_preflight_grant = _RestorePreflightGrant(
                candidate_id=result.candidate_id,
                token=completion_token,
                expires_at=time.monotonic() + 120,
            )
        return reply(
            request.version,
            request.request_id,
            ok={
                "type": "restore_preflight",
                "candidate_id": result.candidate_id,
                "eligible": result.eligible,
                "checked_account_count": result.checked_account_count,
                "blockers": [blocker.value for blocker in result.blockers],
                "completion_token": completion_token,
            },
        )

    async def _on_complete_restore_candidate(
        self, request: CompleteRestoreCandidateRequest
    ) -> bytes:
        grant = self._restore_preflight_grant
        self._restore_preflight_grant = None
        if (
            not self._restore_gated
            or self._backup_restore is None
            or grant is None
            or grant.candidate_id != request.candidate_id
            or grant.token != request.completion_token
            or grant.expires_at < time.monotonic()
        ):
            return reply(request.version, request.request_id, error="invalid_request")
        await asyncio.to_thread(
            self._backup_restore.complete_restore_candidate,
            request.candidate_id,
        )
        self._session.stop()
        return reply(
            request.version,
            request.request_id,
            ok={"type": "restore_activated", "candidate_id": request.candidate_id},
        )
