"""Eligibility policy for restoring an archived execution snapshot."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from enum import StrEnum
from typing import Literal, Protocol

from pydantic import SecretStr

from copytrading_engine.execution.application.ports import RestoreEvidenceBroker
from copytrading_engine.execution.application.restore_reconciliation import (
    RestoreReconciliationError,
    reconcile_restore_snapshot,
)
from copytrading_engine.execution.domain.ledger_state import LedgerSnapshot


class RestorePreflightBlocker(StrEnum):
    CANDIDATE_INVALID = "candidate_invalid"
    CANDIDATE_CHANGED = "candidate_changed"
    APPLICATION_WORK_PENDING = "application_work_pending"
    ACCOUNT_OUTBOX_PENDING = "account_outbox_pending"
    ACCOUNT_SNAPSHOT_INCOMPLETE = "account_snapshot_incomplete"
    ACCOUNT_IDENTITY_MISMATCH = "account_identity_mismatch"
    BROKER_STATE_MISMATCH = "broker_state_mismatch"
    BROKER_EVIDENCE_UNAVAILABLE = "broker_evidence_unavailable"


@dataclass(frozen=True, slots=True)
class RestoreBrokerCredential:
    account_id: str
    environment: Literal["paper", "live"]
    key: SecretStr
    secret: SecretStr


@dataclass(frozen=True, slots=True)
class RestoreAccountInspection:
    account_id: str
    snapshot: LedgerSnapshot
    pending_delivery: bool


@dataclass(frozen=True, slots=True)
class RestoreCandidateInspection:
    """Immutable facts read by an outer adapter from a validated candidate."""

    candidate_id: str
    created_at: datetime
    environment_ids: tuple[str, ...]
    account_member_ids: tuple[str, ...]
    accounts: tuple[RestoreAccountInspection, ...]
    incomplete_account_ids: tuple[str, ...]
    application_readable: bool
    application_work_pending: bool
    candidate_manifest_sha256: str


class RestoreCandidateInspector(Protocol):
    def inspect_candidate(self, candidate_id: str) -> RestoreCandidateInspection: ...


class RestoreEvidenceBrokerFactory(Protocol):
    def __call__(self, credential: RestoreBrokerCredential) -> RestoreEvidenceBroker: ...


@dataclass(frozen=True, slots=True)
class RestorePreflightResult:
    candidate_id: str
    checked_account_count: int
    blockers: tuple[RestorePreflightBlocker, ...]

    @property
    def eligible(self) -> bool:
        return not self.blockers


class RestoreCandidatePreflight:
    """Coordinate local snapshot inspection and read-only broker reconciliation."""

    def __init__(
        self,
        inspector: RestoreCandidateInspector,
        broker_factory: RestoreEvidenceBrokerFactory,
    ) -> None:
        self._inspector = inspector
        self._broker_factory = broker_factory

    def preflight_restore_candidate(
        self,
        candidate_id: str,
        credentials: tuple[RestoreBrokerCredential, ...],
    ) -> RestorePreflightResult:
        blockers: set[RestorePreflightBlocker] = set()
        checked_accounts = 0
        try:
            inspection = self._inspector.inspect_candidate(candidate_id)
        except Exception:  # noqa: BLE001 - any failure blocks the restore candidate
            return self._result(
                candidate_id,
                checked_accounts,
                {RestorePreflightBlocker.CANDIDATE_INVALID},
            )

        try:
            if inspection.candidate_id != candidate_id:
                blockers.add(RestorePreflightBlocker.CANDIDATE_INVALID)
            if not inspection.application_readable:
                blockers.add(RestorePreflightBlocker.CANDIDATE_INVALID)
            elif inspection.application_work_pending:
                blockers.add(RestorePreflightBlocker.APPLICATION_WORK_PENDING)

            manifest_accounts = _manifest_accounts(inspection.environment_ids)
            if set(inspection.account_member_ids) != set(manifest_accounts):
                blockers.add(RestorePreflightBlocker.ACCOUNT_SNAPSHOT_INCOMPLETE)
            if inspection.incomplete_account_ids:
                blockers.add(RestorePreflightBlocker.ACCOUNT_SNAPSHOT_INCOMPLETE)

            supplied: dict[str, RestoreBrokerCredential] = {}
            for credential in credentials:
                if credential.account_id in supplied:
                    blockers.add(RestorePreflightBlocker.ACCOUNT_IDENTITY_MISMATCH)
                supplied[credential.account_id] = credential
            if set(supplied) != set(manifest_accounts):
                blockers.add(RestorePreflightBlocker.ACCOUNT_IDENTITY_MISMATCH)
            if any(
                supplied[account_id].environment != environment
                for account_id, environment in manifest_accounts.items()
                if account_id in supplied
            ):
                blockers.add(RestorePreflightBlocker.ACCOUNT_IDENTITY_MISMATCH)

            for account in inspection.accounts:
                credential = supplied.get(account.account_id)
                if account.pending_delivery:
                    blockers.add(RestorePreflightBlocker.ACCOUNT_OUTBOX_PENDING)
                if (
                    credential is None
                    or account.snapshot.environment != manifest_accounts.get(account.account_id)
                    or account.snapshot.environment != credential.environment
                    or account.snapshot.control.entry_permission != "disabled"
                    or account.snapshot.control.recovery_preference != "manual"
                ):
                    blockers.add(RestorePreflightBlocker.ACCOUNT_IDENTITY_MISMATCH)

            if not blockers:
                for account in inspection.accounts:
                    credential = supplied[account.account_id]
                    broker = None
                    try:
                        broker = self._broker_factory(credential)
                        evidence = broker.restore_evidence(account.snapshot, inspection.created_at)
                        reconcile_restore_snapshot(account.snapshot, evidence)
                    except RestoreReconciliationError:
                        blockers.add(RestorePreflightBlocker.BROKER_STATE_MISMATCH)
                    except Exception:  # noqa: BLE001 - any failure blocks the restore candidate
                        blockers.add(RestorePreflightBlocker.BROKER_EVIDENCE_UNAVAILABLE)
                    finally:
                        if broker is not None:
                            try:
                                broker.close()
                            except Exception:  # noqa: BLE001 - any failure blocks the restore candidate
                                blockers.add(RestorePreflightBlocker.BROKER_EVIDENCE_UNAVAILABLE)
                    if blockers:
                        break
                    checked_accounts += 1
        except Exception:  # noqa: BLE001 - any failure blocks the restore candidate
            blockers.add(RestorePreflightBlocker.CANDIDATE_INVALID)

        try:
            inspection_after = self._inspector.inspect_candidate(candidate_id)
            if (
                inspection_after.candidate_id != candidate_id
                or inspection_after.candidate_manifest_sha256
                != inspection.candidate_manifest_sha256
            ):
                blockers.add(RestorePreflightBlocker.CANDIDATE_CHANGED)
        except Exception:  # noqa: BLE001 - any failure blocks the restore candidate
            blockers.add(RestorePreflightBlocker.CANDIDATE_CHANGED)
        return self._result(candidate_id, checked_accounts, blockers)

    @staticmethod
    def _result(
        candidate_id: str,
        checked_accounts: int,
        blockers: set[RestorePreflightBlocker],
    ) -> RestorePreflightResult:
        return RestorePreflightResult(
            candidate_id=candidate_id,
            checked_account_count=checked_accounts,
            blockers=tuple(sorted(blockers, key=lambda blocker: blocker.value)),
        )


def _manifest_accounts(environment_ids: tuple[str, ...]) -> dict[str, str]:
    accounts: dict[str, str] = {}
    for identity in environment_ids:
        environment, separator, account_id = identity.partition(":")
        if not separator or environment not in {"paper", "live"} or not account_id:
            raise ValueError("restore account identity is invalid")
        if account_id in accounts:
            raise ValueError("restore account identity is duplicated")
        accounts[account_id] = environment
    return accounts
