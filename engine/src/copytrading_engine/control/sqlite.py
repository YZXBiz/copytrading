"""The control audit trail in `application.db`, bounded to the newest entries."""

import datetime as dt
import sqlite3
from pathlib import Path
from typing import Final

from copytrading_engine.control.audit import Actor, AuditEntry
from copytrading_engine.control.policy import Tier
from copytrading_engine.shared.sqlite import SchemaComponent, SQLiteUnit, ensure_schema

AUDIT_RETENTION: Final = 10_000
_ACTORS: Final[dict[object, Actor]] = {"agent": "agent", "owner": "owner"}
_TIERS: Final[dict[object, Tier | None]] = {
    None: None,
    "read": "read",
    "safer": "safer",
    "approval": "approval",
}

CONTROL_AUDIT_SCHEMA = SchemaComponent(
    "control_audit",
    1,
    """
CREATE TABLE IF NOT EXISTS control_audit (
    seq INTEGER PRIMARY KEY AUTOINCREMENT,
    at TEXT NOT NULL,
    actor TEXT NOT NULL CHECK (actor IN ('agent','owner')),
    caller_pid INTEGER,
    caller_path TEXT,
    operation TEXT NOT NULL,
    tier TEXT CHECK (tier IS NULL OR tier IN ('read','safer','approval')),
    outcome TEXT NOT NULL,
    proposal_id TEXT
);
""",
)


class SQLiteControlAudit:
    def __init__(self, unit: SQLiteUnit, retention: int = AUDIT_RETENTION) -> None:
        if retention < 1:
            raise ValueError("The audit trail must keep at least one entry")
        self._unit = unit
        self._retention = retention

    @classmethod
    async def open(cls, path: Path, retention: int = AUDIT_RETENTION) -> SQLiteControlAudit:
        unit = await SQLiteUnit.open(path)
        try:
            await unit.run(lambda db: ensure_schema(db, CONTROL_AUDIT_SCHEMA), write=True)
            return cls(unit, retention)
        except BaseException:
            await unit.close()
            raise

    async def record(self, entry: AuditEntry) -> None:
        def write(db: sqlite3.Connection) -> None:
            db.execute(
                "INSERT INTO control_audit"
                "(at,actor,caller_pid,caller_path,operation,tier,outcome,proposal_id)"
                " VALUES (?,?,?,?,?,?,?,?)",
                (
                    entry.at.isoformat(),
                    entry.actor,
                    entry.caller_pid,
                    entry.caller_path,
                    entry.operation,
                    entry.tier,
                    entry.outcome,
                    entry.proposal_id,
                ),
            )
            db.execute(
                "DELETE FROM control_audit WHERE seq <= (SELECT MAX(seq) FROM control_audit) - ?",
                (self._retention,),
            )

        await self._unit.run(write, write=True)

    async def recent(self, limit: int) -> tuple[AuditEntry, ...]:
        def read(db: sqlite3.Connection) -> tuple[AuditEntry, ...]:
            rows = db.execute(
                "SELECT at,actor,caller_pid,caller_path,operation,tier,outcome,proposal_id"
                " FROM control_audit ORDER BY seq DESC LIMIT ?",
                (limit,),
            ).fetchall()
            return tuple(_entry(row) for row in rows)

        return await self._unit.run(read)

    async def close(self) -> None:
        await self._unit.close()


def _entry(row: tuple[object, ...]) -> AuditEntry:
    at, actor, pid, path, operation, tier, outcome, proposal_id = row
    if not (
        isinstance(at, str)
        and actor in _ACTORS
        and (pid is None or isinstance(pid, int))
        and (path is None or isinstance(path, str))
        and isinstance(operation, str)
        and tier in _TIERS
        and isinstance(outcome, str)
        and (proposal_id is None or isinstance(proposal_id, str))
    ):
        raise ValueError("Stored control audit entry is invalid")
    return AuditEntry(
        at=dt.datetime.fromisoformat(at),
        actor=_ACTORS[actor],
        caller_pid=pid,
        caller_path=path,
        operation=operation,
        tier=_TIERS[tier],
        outcome=outcome,
        proposal_id=proposal_id,
    )
