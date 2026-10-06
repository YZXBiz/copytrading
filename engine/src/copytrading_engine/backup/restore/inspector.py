"""Immutable SQLite inspection adapter for a validated restore generation."""

from __future__ import annotations

import hashlib
import re
import sqlite3
from contextlib import closing
from pathlib import Path

from copytrading_engine.backup.service import BackupRestoreService
from copytrading_engine.execution.adapters.sqlite_ledger import decode_ledger_snapshot
from copytrading_engine.execution.application.restore_preflight import (
    RestoreAccountInspection,
    RestoreCandidateInspection,
)
from copytrading_engine.execution.domain.ledger_state import LedgerSnapshot

_ACCOUNT_DATABASE = re.compile(r"^accounts/([A-Za-z0-9_-]{1,64})/execution\.sqlite3$")
_CANDIDATE_MANIFEST_NAME = ".restore-candidate-manifest.json"


class SQLiteRestoreCandidateInspector:
    """Inspect local state without creating SQLite files or altering candidate hashes."""

    def __init__(self, backup_restore: BackupRestoreService) -> None:
        self._backup_restore = backup_restore

    def inspect_candidate(self, candidate_id: str) -> RestoreCandidateInspection:
        manifest, candidate = self._backup_restore.resolve_active_restore_candidate(candidate_id)
        application_readable = True
        application_work_pending = False
        try:
            application_work_pending = _pending_application_work(candidate / "application.db")
        except Exception:  # noqa: BLE001 - an unreadable member marks the candidate incomplete
            application_readable = False

        account_members = {
            match.group(1): candidate.joinpath(*member.path.split("/"))
            for member in manifest.members
            if (match := _ACCOUNT_DATABASE.fullmatch(member.path)) is not None
        }
        account_inspections: list[RestoreAccountInspection] = []
        incomplete_account_ids: list[str] = []
        for account_id, path in account_members.items():
            try:
                snapshot, pending_delivery = _read_account(path)
            except Exception:  # noqa: BLE001 - an unreadable member marks the candidate incomplete
                incomplete_account_ids.append(account_id)
                continue
            account_inspections.append(
                RestoreAccountInspection(
                    account_id=account_id,
                    snapshot=snapshot,
                    pending_delivery=pending_delivery,
                )
            )

        candidate_manifest_digest = hashlib.sha256(
            (candidate / _CANDIDATE_MANIFEST_NAME).read_bytes()
        ).hexdigest()
        return RestoreCandidateInspection(
            candidate_id=candidate_id,
            created_at=manifest.created_at,
            environment_ids=manifest.environment_ids,
            account_member_ids=tuple(sorted(account_members)),
            accounts=tuple(account_inspections),
            incomplete_account_ids=tuple(sorted(incomplete_account_ids)),
            application_readable=application_readable,
            application_work_pending=application_work_pending,
            candidate_manifest_sha256=candidate_manifest_digest,
        )


def _read_only_connection(path: Path) -> sqlite3.Connection:
    connection = sqlite3.connect(
        f"{path.as_uri()}?mode=ro&immutable=1",
        uri=True,
        timeout=2,
        isolation_level=None,
    )
    try:
        connection.execute("PRAGMA query_only = ON")
    except BaseException:
        connection.close()
        raise
    return connection


def _has_pending(connection: sqlite3.Connection, statement: str) -> bool:
    row = connection.execute(statement).fetchone()
    if row is None or type(row[0]) is not int:
        raise sqlite3.DatabaseError("candidate queue state is unavailable")
    return row[0] != 0


def _pending_application_work(path: Path) -> bool:
    pending_queries = (
        "SELECT EXISTS(SELECT 1 FROM source_captures WHERE mode='live' AND confirmed=0)",
        "SELECT EXISTS(SELECT 1 FROM parser_inbox WHERE result IS NULL)",
        "SELECT EXISTS(SELECT 1 FROM parser_signal_deliveries WHERE delivered_at IS NULL)",
        "SELECT EXISTS(SELECT 1 FROM parser_notifications WHERE delivered_at IS NULL)",
        "SELECT EXISTS(SELECT 1 FROM jobs WHERE status='pending')",
    )
    with closing(_read_only_connection(path)) as connection:
        return any(_has_pending(connection, statement) for statement in pending_queries)


def _read_account(path: Path) -> tuple[LedgerSnapshot, bool]:
    with closing(_read_only_connection(path)) as connection:
        row = connection.execute("SELECT data FROM snapshot WHERE singleton=1").fetchone()
        if row is None or not isinstance(row[0], str):
            raise sqlite3.DatabaseError("account snapshot is unavailable")
        snapshot = decode_ledger_snapshot(row[0])
        # A notification the owner has not been sent yet would be sent again after a restore.
        pending_notifications = _has_pending(
            connection,
            "SELECT EXISTS(SELECT 1 FROM notifications WHERE delivered_at IS NULL)",
        )
    return snapshot, pending_notifications
