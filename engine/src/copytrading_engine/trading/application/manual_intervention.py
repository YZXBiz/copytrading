"""Reviewed corrections, previews, confirmed commands, and account controls."""

import asyncio
import datetime as dt
import logging
from collections.abc import Collection

from copytrading_engine.execution.domain.ledger_state import LedgerSnapshot
from copytrading_engine.execution.domain.lifecycle import (
    AccountControlCommand,
    AccountControlResult,
    AccountOwnerClosed,
)
from copytrading_engine.execution.domain.lot_sales import (
    LotSaleConfirmation,
    LotSalePreview,
    LotSalePreviewRequest,
    LotSaleResult,
)
from copytrading_engine.execution.domain.manual_commands import (
    ManualAccountCommandResult,
    ManualCommandResult,
    ManualCommandsOutcome,
    ManualConfirmationRequest,
    ManualCorrectionAccountResult,
    ManualCorrectionOutcome,
    ManualCorrectionRecord,
    ManualCorrectionRequest,
    ManualOrderPreview,
    ManualPreviewRequest,
    ManualRefusal,
)
from copytrading_engine.execution.domain.ownership import (
    OwnershipResolution,
    OwnershipResolutionRequest,
)
from copytrading_engine.trading.application.account_access import (
    AccountAccess,
    OwnerUnavailable,
    bounded_owner_read,
)
from copytrading_engine.trading.application.accounts import AccountOwner, AccountSupervisor

log = logging.getLogger(__name__)


class ManualInterventionService:
    """Operator actions that reach a live account owner; each keeps its own identity."""

    def __init__(self, access: AccountAccess) -> None:
        self._access = access
        self._correction_lock = asyncio.Lock()

    async def save_manual_correction(
        self, request: ManualCorrectionRequest
    ) -> ManualCorrectionOutcome:
        """Assign one revision and replicate its exact evidence independently."""
        request = ManualCorrectionRequest.model_validate(request.model_dump())
        async with self._correction_lock:
            source_database = self._access.application_database
            evidence = await asyncio.wait_for(
                asyncio.to_thread(
                    self._access.evidence.manual_source_evidence, source_database, request.source_id
                ),
                timeout=3,
            )
            if evidence.source_id != request.source_id:
                raise ManualRefusal("post_unavailable")
            # Every ledger on disk numbers the post's corrections; only the selected accounts must
            # read. An account from an earlier setup whose ledger no longer reads is skipped.
            snapshots = await self._manual_snapshots(required=request.selected_account_ids)
            by_id = [
                correction
                for snapshot in snapshots.values()
                for correction in snapshot.manual_corrections.values()
                if correction.correction_id == request.correction_id
            ]
            revisions: dict[int, str] = {}
            for snapshot in snapshots.values():
                for correction in snapshot.manual_corrections.values():
                    if correction.source_id != request.source_id:
                        continue
                    existing_id = revisions.setdefault(
                        correction.revision, correction.correction_id
                    )
                    if existing_id != correction.correction_id:
                        raise ManualRefusal("correction_conflict")

            if by_id:
                correction = by_id[0]
                if any(item != correction for item in by_id):
                    raise ManualRefusal("correction_conflict")
                if (
                    not correction.matches_request(request)
                    or correction.source_revision != evidence.source_revision
                    or correction.source_at != evidence.source_at
                    or correction.source_text != evidence.text
                    or correction.accepted_interpretation != evidence.accepted_interpretation
                ):
                    raise ManualRefusal("identity_conflict")
            else:
                correction = ManualCorrectionRecord(
                    correction_id=request.correction_id,
                    source_id=request.source_id,
                    selected_account_ids=request.selected_account_ids,
                    revision=max(revisions, default=0) + 1,
                    actor=request.actor,
                    reason=request.reason,
                    instructions=request.instructions,
                    source_revision=evidence.source_revision,
                    source_at=evidence.source_at,
                    source_text=evidence.text,
                    accepted_interpretation=evidence.accepted_interpretation,
                    recorded_at=dt.datetime.now(dt.UTC),
                )

            async def record_one(account_id: str) -> ManualCorrectionAccountResult:
                supervisor = self._access.supervisors().get(account_id)
                if supervisor is None or supervisor.owner is None or supervisor.state == "failed":
                    return ManualCorrectionAccountResult(
                        account_id=account_id, status="unavailable", reason="account_not_running"
                    )
                try:
                    saved = await supervisor.owner.record_manual_correction(correction)
                    if saved != correction:
                        raise RuntimeError("Account correction copy differs")
                    return ManualCorrectionAccountResult(account_id=account_id, status="recorded")
                except AccountOwnerClosed:
                    # Copying is pausing or stopped: the call was never offered to this account.
                    return ManualCorrectionAccountResult(
                        account_id=account_id, status="unavailable", reason="account_not_running"
                    )
                except Exception as exc:  # noqa: BLE001 - one account's failure is reported per account
                    # A refusal names itself; anything else is one account that could not save.
                    reason = exc.reason if isinstance(exc, ManualRefusal) else "record_failed"
                    log.warning(
                        "manual_correction_record_failed account=%s error=%s reason=%s",
                        account_id,
                        type(exc).__name__,
                        reason,
                    )
                    return ManualCorrectionAccountResult(
                        account_id=account_id, status="failed", reason=reason
                    )

            accounts = await asyncio.gather(
                *(record_one(account_id) for account_id in request.selected_account_ids)
            )
            # An account that did not record says why; the owner reads those, not one error.
            if any(account.status == "recorded" for account in accounts):
                # The guru's history reads the owner's call in place of the reader's (ADR-0010).
                await asyncio.to_thread(
                    self._access.evidence.record_owner_correction,
                    source_database,
                    correction.source_id,
                    correction.instructions,
                    correction.recorded_at,
                )
            return ManualCorrectionOutcome(correction=correction, accounts=tuple(accounts))

    async def preview_manual_order(self, request: ManualPreviewRequest) -> ManualOrderPreview:
        request = ManualPreviewRequest.model_validate(request.model_dump())
        _, owner = self._manual_owner(request.account_id)
        live = await bounded_owner_read(owner.observation())
        if isinstance(live, OwnerUnavailable):
            raise ManualRefusal("account_unavailable")
        record = live.ledger.manual_corrections.get(request.correction_id)
        if record is None:
            raise ManualRefusal("correction_incomplete")
        await self._require_agreeing_copies(record, request.account_id)
        try:
            return await owner.preview_manual_order(request, dt.datetime.now(dt.UTC))
        except AccountOwnerClosed as exc:
            raise ManualRefusal("account_not_running") from exc

    async def preview_lot_sale(self, request: LotSalePreviewRequest) -> LotSalePreview:
        request = LotSalePreviewRequest.model_validate(request.model_dump())
        _, owner = self._manual_owner(request.account_id)
        return await owner.preview_lot_sale(request, dt.datetime.now(dt.UTC))

    async def confirm_lot_sale(self, request: LotSaleConfirmation) -> LotSaleResult:
        request = LotSaleConfirmation.model_validate(request.model_dump())
        supervisor, owner = self._manual_owner(request.account_id)
        result = await owner.confirm_lot_sale(request, dt.datetime.now(dt.UTC))
        await supervisor.refresh()
        return result

    async def confirm_manual_orders(
        self, requests: tuple[ManualConfirmationRequest, ...]
    ) -> ManualCommandsOutcome:
        if not requests or len(requests) > 20:
            raise ValueError("Manual confirmation batch is invalid")
        requests = tuple(
            ManualConfirmationRequest.model_validate(item.model_dump()) for item in requests
        )
        if len({item.command_id for item in requests}) != len(requests):
            raise ValueError("Manual confirmation batch has duplicate command IDs")

        async def confirm_one(request: ManualConfirmationRequest) -> ManualAccountCommandResult:
            try:
                supervisor, owner = self._manual_owner(request.account_id)
                live = await owner.observation()
                command = live.ledger.manual_commands.get(request.command_id)
                if command is None:
                    preview = live.ledger.manual_previews.get(request.preview_id)
                    correction = (
                        live.ledger.manual_corrections.get(preview.request.correction_id)
                        if preview is not None
                        else None
                    )
                    if correction is None:
                        raise ManualRefusal(
                            "preview_missing" if preview is None else "correction_incomplete"
                        )
                    await self._require_agreeing_copies(correction, request.account_id)
                result = await owner.confirm_manual_order(request, dt.datetime.now(dt.UTC))
                await supervisor.refresh()
                return ManualAccountCommandResult(
                    account_id=request.account_id,
                    command_id=request.command_id,
                    result=result,
                )
            except AccountOwnerClosed:
                # Closed before the call ran, so nothing was sent.
                return ManualAccountCommandResult(
                    account_id=request.account_id,
                    command_id=request.command_id,
                    error="account_not_running",
                )
            except Exception as exc:  # noqa: BLE001 - one account's failure is reported per account
                # A refusal names itself; anything else cannot say whether the order went.
                reason = exc.reason if isinstance(exc, ManualRefusal) else "confirm_failed"
                log.warning(
                    "manual_command_failed account=%s error=%s reason=%s",
                    request.account_id,
                    type(exc).__name__,
                    reason,
                )
                return ManualAccountCommandResult(
                    account_id=request.account_id,
                    command_id=request.command_id,
                    error=reason,
                )

        by_account: dict[str, list[ManualConfirmationRequest]] = {}
        for request in requests:
            by_account.setdefault(request.account_id, []).append(request)

        async def confirm_account(
            account_requests: list[ManualConfirmationRequest],
        ) -> tuple[ManualAccountCommandResult, ...]:
            # Recheck each preview only after the previous command has been
            # durably reconciled. A changed account snapshot rejects later
            # previews instead of letting a batch silently reuse stale sizing.
            outcomes = []
            for item in account_requests:
                outcomes.append(await confirm_one(item))
            return tuple(outcomes)

        batches = await asyncio.gather(
            *(confirm_account(by_account[account_id]) for account_id in sorted(by_account))
        )
        return ManualCommandsOutcome(outcomes=tuple(item for batch in batches for item in batch))

    async def manual_command_result(self, account_id: str, command_id: str) -> ManualCommandResult:
        _, owner = self._manual_owner(account_id)
        return await owner.manual_command_result(command_id)

    async def control_account(self, command: AccountControlCommand) -> AccountControlResult:
        supervisor = self._access.supervisors().get(command.account_id)
        if supervisor is None or supervisor.owner is None or supervisor.state == "failed":
            raise ValueError("Account is not available for control")
        result = await supervisor.owner.control_account(command, dt.datetime.now(dt.UTC))
        await supervisor.refresh()
        return result

    async def resolve_ownership(
        self, local_account_id: str, request: OwnershipResolutionRequest
    ) -> OwnershipResolution:
        supervisor = self._access.supervisors().get(local_account_id)
        if supervisor is None or supervisor.owner is None or supervisor.state == "failed":
            raise ValueError("Account is not available for ownership review")
        result = await supervisor.owner.resolve_ownership(request)
        await supervisor.refresh()
        return result

    def _manual_owner(self, account_id: str) -> tuple[AccountSupervisor, AccountOwner]:
        supervisor = self._access.supervisors().get(account_id)
        if supervisor is None or supervisor.owner is None or supervisor.state == "failed":
            raise ManualRefusal("account_not_running")
        return supervisor, supervisor.owner

    async def _manual_snapshots(
        self,
        account_ids: Collection[str] | None = None,
        *,
        required: Collection[str] | None = None,
    ) -> dict[str, LedgerSnapshot]:
        """The ledgers of `account_ids`, or of every retained account. With `required`, only those
        accounts must read; any other ledger that fails is left out."""
        paths = self._access.retained_paths()
        must_read = set(required or ())
        selected_ids = (
            sorted(set(paths) | must_read) if account_ids is None else sorted(set(account_ids))
        )

        async def read_one(account_id: str) -> tuple[str, LedgerSnapshot] | None:
            database = paths.get(account_id)
            supervisor = self._access.supervisors().get(account_id)
            if (
                supervisor is not None
                and supervisor.owner is not None
                and supervisor.state != "failed"
            ):
                live = await bounded_owner_read(supervisor.owner.observation())
                if not isinstance(live, OwnerUnavailable):
                    return account_id, live.ledger
            if database is None:
                raise ManualRefusal("records_unreadable")
            try:
                _, snapshot, _ = await self._access.retained_account(database, timeout=3)
                return account_id, snapshot
            except Exception as exc:
                log.warning(
                    "manual_ledger_read_failed account=%s type=%s", account_id, type(exc).__name__
                )
                if required is not None and account_id not in must_read:
                    return None
                raise ManualRefusal("records_unreadable") from exc

        read = await asyncio.gather(*(read_one(account_id) for account_id in selected_ids))
        return dict(item for item in read if item is not None)

    async def _require_agreeing_copies(
        self, correction: ManualCorrectionRecord, account_id: str
    ) -> None:
        """The account acting on a correction holds it, and no other chosen account holds a
        different copy under its name. A chosen account that could not record it (paused, or
        the call no longer waits there) holds none, which never stops the accounts that did."""
        snapshots = await self._manual_snapshots(
            correction.selected_account_ids, required=(account_id,)
        )
        if snapshots[account_id].manual_corrections.get(correction.correction_id) != correction:
            raise ManualRefusal("correction_incomplete")
        if any(
            copy != correction
            for snapshot in snapshots.values()
            if (copy := snapshot.manual_corrections.get(correction.correction_id)) is not None
        ):
            raise ManualRefusal("correction_conflict")
