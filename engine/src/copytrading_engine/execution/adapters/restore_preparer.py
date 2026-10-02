"""Apply the durable manual-disabled transition to an isolated restored ledger."""

from __future__ import annotations

import datetime as dt
import uuid
from pathlib import Path

from copytrading_engine.execution.adapters.sqlite_ledger import Store
from copytrading_engine.execution.application.ledger import TradingLedger
from copytrading_engine.execution.application.ports import NoOpObserver
from copytrading_engine.execution.domain.lifecycle import AccountControlCommand


def prepare_restored_account(path: Path) -> None:
    """Persist an audited disabled/manual control before a candidate can be activated."""
    store = Store(path)
    try:
        row = store.db.execute(
            "SELECT environment, account_id FROM identity WHERE singleton=1"
        ).fetchone()
        if row is None or row[0] not in {"paper", "live"} or not isinstance(row[1], str):
            raise ValueError("restored account identity is incomplete")
        environment, account_id = row
        store.bind_identity(account_id, environment)
        ledger = TradingLedger(store, NoOpObserver())
        result = ledger.account_control(
            AccountControlCommand(
                command_id=str(uuid.uuid4()),
                account_id=account_id,
                action="restore_manual",
            ),
            dt.datetime.now(dt.UTC),
            local_account_id=account_id,
        )
        if (result.entry_permission, result.recovery_preference) != ("disabled", "manual"):
            raise RuntimeError("restored account did not enter manual-disabled state")
        checkpoint = store.db.execute("PRAGMA wal_checkpoint(TRUNCATE)").fetchone()
        if checkpoint is None or checkpoint[0] != 0:
            raise RuntimeError("restored account journal could not be checkpointed")
    finally:
        store.close()
