"""An account whose worker is busy placing orders still reads as what it last said, never as
stopped, and the app's reads never pile up behind that worker."""

import asyncio
from types import SimpleNamespace

from copytrading_engine.execution.domain.ledger_state import LedgerSnapshot
from copytrading_engine.execution.presentation.operator_views import AccountOverview
from copytrading_engine.trading.adapters.operator_queries import SQLiteOperatorEvidence
from copytrading_engine.trading.application import account_access
from copytrading_engine.trading.application.account_access import (
    AccountAccess,
    OwnerReads,
    OwnerUnavailable,
)
from copytrading_engine.trading.application.operator_service import OperatorQueryService

from ..execution.builders import save_snapshot


def copying(account_id: str = "primary") -> AccountOverview:
    return AccountOverview(
        account_id=account_id,
        environment="paper",
        active_configuration=True,
        broker_identity="paper-demo",
        entry_permission="enabled",
        recovery_preference="automatic",
        readiness="enabled",
        account_risk_status="ready",
        account_risk_reason=None,
        account_activity_status="ready",
        account_activity_reason=None,
        total_exposure_usd=None,
        app_cost_basis_usd=None,
        positions=(),
        unresolved_incidents=(),
        ownership_incidents=(),
        pending_orders=0,
        balance=None,
    )


class Worker:
    """Answers its first read at once, then is busy until released."""

    def __init__(self, answer: object) -> None:
        self.answer = answer
        self.reads = 0
        self.free = asyncio.Event()

    async def read(self) -> object:
        self.reads += 1
        if self.reads > 1:
            await self.free.wait()
        return self.answer


async def test_a_busy_account_reads_as_copying_not_stopped(tmp_path, monkeypatch):
    monkeypatch.setattr(account_access, "_OWNER_READ_TIMEOUT_SECONDS", 0.01)
    save_snapshot(tmp_path / "accounts" / "primary", LedgerSnapshot(account_id="primary"))
    worker = Worker(copying())
    owner = SimpleNamespace(operator_overview=worker.read)
    service = OperatorQueryService(
        AccountAccess(
            tmp_path,
            lambda: {"primary": SimpleNamespace(owner=owner, state="running", error_code=None)},
            configuration=lambda: None,
            runtime_state=lambda: "running",
            evidence=SQLiteOperatorEvidence(),
        )
    )

    assert (await service.account_overviews()).items == (copying(),)
    busy = await service.account_overviews()
    while_busy = await service.account_overviews()

    assert busy.items == while_busy.items == (copying(),)
    assert busy.unavailable_accounts == ()
    assert worker.reads == 2, "a read queued behind the busy worker"
    worker.free.set()


async def test_a_late_answer_becomes_the_one_shown_while_busy(monkeypatch):
    monkeypatch.setattr(account_access, "_OWNER_READ_TIMEOUT_SECONDS", 0.01)
    reads = OwnerReads()
    owner = object()
    worker = Worker("first")

    assert await reads.read("primary", owner, "feed", worker.read) == "first"
    worker.answer = "second"
    assert await reads.read("primary", owner, "feed", worker.read) == "first"
    worker.free.set()
    await asyncio.sleep(0)

    worker.free.clear()
    assert await reads.read("primary", owner, "feed", worker.read) == "second"


async def test_a_restarted_worker_is_never_shown_its_predecessors_answers(monkeypatch):
    monkeypatch.setattr(account_access, "_OWNER_READ_TIMEOUT_SECONDS", 0.01)
    reads = OwnerReads()
    before = Worker("before the restart")
    assert await reads.read("primary", object(), "overview", before.read) == "before the restart"

    stalled = asyncio.Event()

    async def busy() -> str:
        await stalled.wait()
        return "late"

    assert await reads.read("primary", object(), "overview", busy) == OwnerUnavailable("timeout")
    stalled.set()


async def test_an_answer_stands_in_only_for_the_same_read(monkeypatch):
    monkeypatch.setattr(account_access, "_OWNER_READ_TIMEOUT_SECONDS", 0.01)
    reads = OwnerReads()
    owner = object()
    worker = Worker("day curve")
    assert await reads.read("primary", owner, ("history", "day"), worker.read) == "day curve"

    assert await reads.read("primary", owner, ("history", "week"), worker.read) == (
        OwnerUnavailable("timeout")
    )
    worker.free.set()
