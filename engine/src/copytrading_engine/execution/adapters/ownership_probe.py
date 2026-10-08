"""Read-only account-state guard for removing a stopped app configuration."""

import json
import sqlite3
from contextlib import closing
from decimal import Decimal
from pathlib import Path

from copytrading_engine.execution.adapters.sqlite_ledger import (
    EXECUTION_SCHEMA,
    decode_ledger_snapshot,
)
from copytrading_engine.execution.domain.ledger_state import LedgerSnapshot
from copytrading_engine.execution.domain.order_lifecycle import is_terminal
from copytrading_engine.shared.sqlite import verify_schema


def has_unresolved_ownership(account_dir: Path) -> bool:
    """Return whether an account still owns work or shares; never create or modify its DB.

    Missing state is empty. Existing state with an unknown schema, invalid identity, or
    unreadable snapshot raises so the caller can keep the account configuration.
    Call only after the account owner has stopped writing this directory.
    """
    path = account_dir / "execution.sqlite3"
    if path.is_symlink():
        raise RuntimeError("Execution database symlink cannot be inspected safely")
    if not path.exists():
        return False
    if not path.is_file():
        raise RuntimeError("Execution database path is not a file")
    try:
        with closing(sqlite3.connect(path.as_uri() + "?mode=ro", uri=True, timeout=5)) as db:
            db.execute("BEGIN")
            verify_schema(db, EXECUTION_SCHEMA)
            row = db.execute("SELECT data FROM snapshot WHERE singleton=1").fetchone()
            if row is None:
                return False
            older = _older_snapshot(row[0])
            if older is not None:
                return _older_holds_work(older)
            ledger = decode_ledger_snapshot(row[0])
            identity = db.execute(
                "SELECT environment,account_id FROM identity WHERE singleton=1"
            ).fetchone()
            if (
                identity is None
                or identity[0] not in {"paper", "live"}
                or ledger.account_id is None
                or ledger.account_id != identity[1]
                or ledger.environment != identity[0]
            ):
                raise RuntimeError("Execution snapshot account identity is invalid")
            return (
                any(message.status == "queued" for message in ledger.messages.values())
                or any(not order.terminal for order in ledger.orders.values())
                or any(lot.remaining_qty > 0 for lot in ledger.lots.values())
                or ledger.entry_halted
                or any(not incident.resolved for incident in ledger.ownership_incidents.values())
            )
    except (sqlite3.Error, ValueError) as error:
        raise RuntimeError("Execution ownership state is unreadable") from error


def _older_snapshot(data: str) -> dict | None:
    """The snapshot of an earlier ledger version, which is never migrated, or None when it is
    the current one."""
    snapshot = json.loads(data)
    if not isinstance(snapshot, dict):
        raise ValueError("Execution snapshot is not an object")
    version = snapshot.get("schema_version")
    current = LedgerSnapshot.model_fields["schema_version"].default
    if isinstance(version, int) and 0 < version < current:
        return snapshot
    return None


def _older_holds_work(snapshot: dict) -> bool:
    """Whether a ledger an earlier CopyTrading wrote still holds anything of the app's: a post
    being copied, an open order, shares, a halt, or an unresolved ownership incident. Read by name
    only, since its format is not this version's; anything unreadable counts as held."""
    try:
        return (
            any(m["status"] == "queued" for m in snapshot.get("messages", {}).values())
            or any(not is_terminal(o["status"]) for o in snapshot.get("orders", {}).values())
            or any(
                Decimal(str(lot["remaining_qty"])) > 0 for lot in snapshot.get("lots", {}).values()
            )
            or bool(snapshot.get("entry_halted"))
            or any(not i.get("resolved") for i in snapshot.get("ownership_incidents", {}).values())
        )
    except KeyError, TypeError, ArithmeticError, ValueError, AttributeError:
        return True
