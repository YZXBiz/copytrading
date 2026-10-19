"""A cycle that fails for a reason other than Alpaca answering badly is tried again a few times
before the account stays failed, and the owner hears once when it does."""

import asyncio

import pytest

from copytrading_engine.execution.application.ports import BrokerError
from copytrading_engine.trading.application import accounts
from copytrading_engine.trading.application.accounts import AccountSupervisor

from .runtime.fakes import Owner


class _FaultyOwner(Owner):
    """An owner whose cycle raises each of `faults` in turn, then works."""

    def __init__(self, path, faults: list[Exception]):
        super().__init__(path, {}, {})
        self.faults = faults

    async def cycle(self, now, *, halted):
        if self.faults:
            self.cycles += 1
            raise self.faults.pop(0)
        return await super().cycle(now, halted=halted)


class _AlwaysFaulty(Owner):
    async def cycle(self, now, *, halted):
        self.cycles += 1
        raise RuntimeError("the cycle cannot finish")


@pytest.fixture(autouse=True)
def quick_retries(monkeypatch):
    monkeypatch.setattr(accounts, "CYCLE_RETRY_SECONDS", (0.01, 0.01, 0.01))


def _supervisor(
    owner, failed: list[tuple[str, BaseException]]
) -> tuple[AccountSupervisor, asyncio.Event]:
    stop = asyncio.Event()
    return AccountSupervisor(
        owner.name,
        owner,
        0.02,
        stop,
        lambda: None,
        on_failed=lambda account_id, error: failed.append((account_id, error)),
    ), stop


async def test_a_cycle_that_fails_unexpectedly_is_retried_and_the_account_recovers(tmp_path):
    owner = _FaultyOwner(tmp_path, [RuntimeError("disk"), ValueError("odd answer")])
    failed: list[tuple[str, BaseException]] = []
    supervisor, stop = _supervisor(owner, failed)
    supervisor.start()
    try:
        await asyncio.sleep(0.3)
        assert supervisor.state == "running"
        assert supervisor.error_code is None
        assert owner.cycles > 3, "the cycles went on after the two that failed"
        assert failed == []
        assert not owner.stopped
    finally:
        stop.set()
        await supervisor.close()


async def test_a_run_of_failures_that_ends_in_success_starts_the_count_over(tmp_path):
    first = [RuntimeError("one"), RuntimeError("two"), RuntimeError("three")]
    owner = _FaultyOwner(tmp_path, first)
    failed: list[tuple[str, BaseException]] = []
    supervisor, stop = _supervisor(owner, failed)
    supervisor.start()
    try:
        await asyncio.sleep(0.2)
        assert owner.cycles > 3
        owner.faults.extend([RuntimeError("four"), RuntimeError("five"), RuntimeError("six")])
        await asyncio.sleep(0.2)
        assert supervisor.state == "running"
        assert failed == []
    finally:
        stop.set()
        await supervisor.close()


async def test_a_cycle_that_keeps_failing_stops_the_account_after_its_retries(tmp_path):
    owner = _AlwaysFaulty(tmp_path, {}, {})
    failed: list[tuple[str, BaseException]] = []
    supervisor, stop = _supervisor(owner, failed)
    supervisor.start()
    await asyncio.sleep(0.3)
    stop.set()
    await supervisor.close()

    assert supervisor.state == "failed"
    assert supervisor.error_code == "account_unavailable"
    assert owner.cycles == 1 + len(accounts.CYCLE_RETRY_SECONDS)
    assert owner.stopped
    assert [(account_id, str(error)) for account_id, error in failed] == [
        (owner.name, "the cycle cannot finish")
    ], "the owner is told once, with the last error, not once per try"


async def test_rejected_keys_still_stop_the_account_at_once_and_say_so(tmp_path):
    owner = _FaultyOwner(tmp_path, [BrokerError(403)])
    failed: list[tuple[str, BaseException]] = []
    supervisor, stop = _supervisor(owner, failed)
    supervisor.start()
    await asyncio.sleep(0.1)
    stop.set()
    await supervisor.close()

    assert supervisor.state == "failed"
    assert owner.cycles == 1
    assert [(account_id, type(error)) for account_id, error in failed] == [
        (owner.name, BrokerError)
    ]


async def test_an_account_that_never_opened_says_nothing(tmp_path):
    failed: list[tuple[str, BaseException]] = []
    stop = asyncio.Event()
    supervisor = AccountSupervisor(
        "paper-1",
        None,
        0.02,
        stop,
        lambda: None,
        open_failure="account_in_use",
        on_failed=lambda account_id, error: failed.append((account_id, error)),
    )
    supervisor.start()

    assert supervisor.state == "failed"
    assert failed == [], "the owner was there when it was opened"
