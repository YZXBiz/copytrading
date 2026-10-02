"""One audit record per control decision, and the port that keeps them."""

import datetime as dt
from dataclasses import dataclass
from typing import Literal, Protocol

from copytrading_engine.control.policy import Tier

type Actor = Literal["agent", "owner"]


@dataclass(frozen=True, slots=True)
class AuditEntry:
    """Identifiers only: no request text, source text, or secrets."""

    at: dt.datetime
    actor: Actor
    caller_pid: int | None
    caller_path: str | None
    operation: str
    tier: Tier | None
    outcome: str
    proposal_id: str | None = None


class ControlAudit(Protocol):
    async def record(self, entry: AuditEntry) -> None: ...

    async def recent(self, limit: int) -> tuple[AuditEntry, ...]: ...
