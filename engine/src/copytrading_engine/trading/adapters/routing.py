"""Bind queued source and parser work to the saved routing configuration."""

import json
import re
import sqlite3
from pathlib import Path

from copytrading_engine.execution.adapters.ownership_probe import has_unresolved_ownership
from copytrading_engine.shared.sqlite import SchemaComponent, SQLiteUnit, ensure_schema
from copytrading_engine.trading.domain.config import TradingConfiguration

ROUTING_SCHEMA = SchemaComponent(
    "trading_routing",
    1,
    """
CREATE TABLE IF NOT EXISTS trading_routing_revision (
    singleton INTEGER PRIMARY KEY CHECK (singleton=1),
    fingerprint TEXT NOT NULL,
    account_ids TEXT NOT NULL
);
""",
)


class RoutingChangePending(Exception):
    """A new configuration cannot claim work captured under a prior route."""


class AccountOwnershipPending(Exception):
    """Removing this local account would abandon unsettled execution ownership."""


class RoutingRevision:
    def __init__(self, unit: SQLiteUnit, account_root: Path) -> None:
        self._unit = unit
        self._account_root = account_root

    @classmethod
    async def open(cls, path: Path) -> RoutingRevision:
        unit = await SQLiteUnit.open(path)
        try:
            await unit.run(
                lambda db: ensure_schema(db, ROUTING_SCHEMA),
                write=True,
            )
            return cls(unit, path.parent / "accounts")
        except BaseException:
            await unit.close()
            raise

    async def validate(self, configuration: TradingConfiguration) -> None:
        """Check revision ownership and pending work without committing a new revision."""
        await self._unit.run(lambda db: self._check(db, configuration, commit=False), write=False)

    async def accept(self, configuration: TradingConfiguration) -> None:
        """Persist a validated revision after atomically rechecking pending work."""
        await self._unit.run(lambda db: self._check(db, configuration, commit=True), write=True)

    def _check(
        self, db: sqlite3.Connection, configuration: TradingConfiguration, *, commit: bool
    ) -> None:
        fingerprint = configuration.routing_revision()
        new_accounts = {account.id for account in configuration.accounts}
        old = db.execute(
            "SELECT fingerprint,account_ids FROM trading_routing_revision WHERE singleton=1"
        ).fetchone()
        if old is not None and old[0] == fingerprint:
            return
        if old is not None:
            saved_accounts = json.loads(old[1])
            if not isinstance(saved_accounts, list) or not all(
                isinstance(value, str) for value in saved_accounts
            ):
                raise RuntimeError("Saved account identities are invalid")
            prior_accounts = set(saved_accounts)
        else:
            prior_accounts = set()
        if self._account_root.exists():
            if self._account_root.is_symlink():
                raise RuntimeError("Account state directory is invalid")
            prior_accounts.update(path.name for path in self._account_root.iterdir())
        for account_id in prior_accounts - new_accounts:
            if not re.fullmatch(r"[A-Za-z0-9_-]{1,64}", account_id):
                raise RuntimeError("Saved account identity is invalid")
            account_dir = self._account_root / account_id
            if account_dir.is_symlink():
                raise RuntimeError("Account state directory is invalid")
            if has_unresolved_ownership(account_dir):
                raise AccountOwnershipPending
        pending = any(
            db.execute(query).fetchone() is not None
            for query in (
                "SELECT 1 FROM source_captures WHERE mode='live' AND confirmed=0 LIMIT 1",
                "SELECT 1 FROM parser_inbox WHERE result IS NULL LIMIT 1",
                "SELECT 1 FROM parser_signal_deliveries WHERE delivered_at IS NULL LIMIT 1",
            )
        )
        if pending:
            raise RoutingChangePending
        if commit:
            db.execute(
                "INSERT INTO trading_routing_revision(singleton,fingerprint,account_ids) "
                "VALUES (1,?,?) ON CONFLICT(singleton) DO UPDATE SET "
                "fingerprint=excluded.fingerprint,account_ids=excluded.account_ids",
                (fingerprint, json.dumps(sorted(new_accounts))),
            )

    async def close(self) -> None:
        await self._unit.close()
