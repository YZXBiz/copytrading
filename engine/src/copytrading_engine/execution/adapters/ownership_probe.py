"""Read-only account-state guard for removing a stopped app configuration."""

import json
import sqlite3
from contextlib import closing
from dataclasses import dataclass
from decimal import Decimal
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
    """What a stopped account still holds of CopyTrading's, named so the owner can settle it."""

    # Stocks it still holds shares of from copied buys, A to Z.
    symbols: tuple[str, ...] = ()
    # Stocks with an order CopyTrading placed that has not finished, A to Z.
    order_symbols: tuple[str, ...] = ()
    # A post still being copied, entries halted, or holdings waiting for the owner's review.
    needs_review: bool = False


def unsettled_ownership(account_dir: Path) -> UnsettledOwnership | None:
    """What an account still owns of the app's work or shares, or None when it owns nothing;
    never create or modify its DB.

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
                symbols={lot.symbol for lot in ledger.lots.values() if lot.remaining_qty > 0},
                order_symbols={
                    order.symbol for order in ledger.orders.values() if not order.terminal
                },
                needs_review=(
                    any(message.status == "queued" for message in ledger.messages.values())
                    or ledger.entry_halted
                    or any(
                        not incident.resolved for incident in ledger.ownership_incidents.values()
                    )
                ),
            )
    except (sqlite3.Error, ValueError) as error:
        raise RuntimeError("Execution ownership state is unreadable") from error


def _held(
    *, symbols: set[str], order_symbols: set[str], needs_review: bool
) -> UnsettledOwnership | None:
    if not symbols and not order_symbols and not needs_review:
        return None
    return UnsettledOwnership(
        symbols=tuple(sorted(symbols)),
        order_symbols=tuple(sorted(order_symbols)),
        needs_review=needs_review,
    )


def _older_snapshot(data: str) -> dict | None:
    """The snapshot of an earlier ledger version, which is never migrated, or None when it is
    the current one."""
    snapshot = json.loads(data)
    if not isinstance(snapshot, dict):
        raise ValueError("Execution snapshot is not an object")
    return snapshot if is_earlier_version(snapshot.get("schema_version")) else None


def _older_ownership(snapshot: dict) -> UnsettledOwnership | None:
    """What a ledger an earlier CopyTrading wrote still holds of the app's: shares, an open order,
    a post being copied, a halt, or an unresolved ownership incident. Read by name only, since its
    format is not this version's; anything unreadable counts as needing review."""
    try:
        return _held(
            symbols={
                str(lot["symbol"])
                for lot in snapshot.get("lots", {}).values()
                if Decimal(str(lot["remaining_qty"])) > 0
            },
            order_symbols={
                str(order["symbol"])
                for order in snapshot.get("orders", {}).values()
                if not is_terminal(order["status"])
            },
            needs_review=(
                any(m["status"] == "queued" for m in snapshot.get("messages", {}).values())
                or bool(snapshot.get("entry_halted"))
                or any(
                    not i.get("resolved") for i in snapshot.get("ownership_incidents", {}).values()
                )
            ),
        )
    except KeyError, TypeError, ArithmeticError, ValueError, AttributeError:
        return UnsettledOwnership(needs_review=True)
