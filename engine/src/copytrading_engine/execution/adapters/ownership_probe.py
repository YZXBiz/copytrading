"""Read-only account-state guard for removing a stopped app configuration."""

import json
import sqlite3
from contextlib import closing
from dataclasses import dataclass
from pathlib import Path

from copytrading_engine.execution.adapters.sqlite_ledger import (
    EXECUTION_SCHEMA,
    decode_ledger_snapshot,
)
from copytrading_engine.execution.domain.ledger_state import is_earlier_version
from copytrading_engine.execution.domain.order_lifecycle import is_terminal
from copytrading_engine.shared.sqlite import verify_schema


@dataclass(frozen=True)
class UnsettledOwnership:
    """Work a stopped account still has in flight, named so the owner can settle it. Shares it
    holds are not work: a removed account keeps them at the broker, and CopyTrading stops
    tracking them."""

    # Stocks with an order CopyTrading placed that has not finished, A to Z.
    order_symbols: tuple[str, ...] = ()
    # A post still being copied.
    needs_review: bool = False


def unsettled_ownership(account_dir: Path) -> UnsettledOwnership | None:
    """The work an account still has in flight, or None when it has none; never create or
    modify its DB.

    Missing state is empty. Existing state with an unknown schema, invalid identity, or
    unreadable snapshot raises so the caller can keep the account configuration.
    Call only after the account owner has stopped writing this directory.
    """
    path = account_dir / "execution.sqlite3"
    if path.is_symlink():
        raise RuntimeError("Execution database symlink cannot be inspected safely")
    if not path.exists():
        return None
    if not path.is_file():
        raise RuntimeError("Execution database path is not a file")
    try:
        with closing(sqlite3.connect(path.as_uri() + "?mode=ro", uri=True, timeout=5)) as db:
            db.execute("BEGIN")
            verify_schema(db, EXECUTION_SCHEMA)
            row = db.execute("SELECT data FROM snapshot WHERE singleton=1").fetchone()
            if row is None:
                return None
            older = _older_snapshot(row[0])
            if older is not None:
                return _older_ownership(older)
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
            return _held(
                order_symbols={
                    order.symbol for order in ledger.orders.values() if not order.terminal
                },
                needs_review=any(
                    message.status == "queued" for message in ledger.messages.values()
                ),
            )
    except (sqlite3.Error, ValueError) as error:
        raise RuntimeError("Execution ownership state is unreadable") from error


def _held(*, order_symbols: set[str], needs_review: bool) -> UnsettledOwnership | None:
    if not order_symbols and not needs_review:
        return None
    return UnsettledOwnership(order_symbols=tuple(sorted(order_symbols)), needs_review=needs_review)


def _older_snapshot(data: str) -> dict | None:
    """The snapshot of an earlier ledger version, which is never migrated, or None when it is
    the current one."""
    snapshot = json.loads(data)
    if not isinstance(snapshot, dict):
        raise ValueError("Execution snapshot is not an object")
    return snapshot if is_earlier_version(snapshot.get("schema_version")) else None


def _older_ownership(snapshot: dict) -> UnsettledOwnership | None:
    """The work a ledger an earlier CopyTrading wrote still has in flight: an open order or a post
    being copied. Read by name only, since its format is not this version's; anything unreadable
    counts as needing review."""
    try:
        return _held(
            order_symbols={
                str(order["symbol"])
                for order in snapshot.get("orders", {}).values()
                if not is_terminal(order["status"])
            },
            needs_review=any(
                m["status"] == "queued" for m in snapshot.get("messages", {}).values()
            ),
        )
    except KeyError, TypeError, ValueError, AttributeError:
        return UnsettledOwnership(needs_review=True)
