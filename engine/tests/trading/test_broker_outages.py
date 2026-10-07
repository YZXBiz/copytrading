"""A passing Alpaca outage keeps the account running and copying resumes on its own; a failure
that needs the owner, such as rejected keys, still stops the account."""

import asyncio

import pytest

from copytrading_engine.execution.application.ports import BrokerError, BrokerResponseError
from copytrading_engine.trading.application import accounts
from copytrading_engine.trading.application.accounts import AccountSupervisor

from .runtime.fakes import Owner


class _FlakyOwner(Owner):
    """An owner whose broker answers with `failures` before it answers normally."""

    def __init__(self, path, failures: list[BrokerError]):
        super().__init__(path, {}, {})
        self.failures = failures

    async def cycle(self, now, *, halted):
        if self.failures:
            self.cycles += 1
            raise self.failures.pop(0)
        return await super().cycle(now, halted=halted)


@pytest.mark.parametrize(
    ("status", "transient"),
    [
        (None, True),
        (408, True),
        (429, True),
        (500, True),
        (503, True),
        (401, False),
        (403, False),
        (404, False),
        (422, False),
    ],
)
def test_only_failures_that_pass_on_their_own_are_transient(status, transient):
    assert BrokerError(status).transient is transient


def test_a_garbled_broker_answer_is_not_transient():
    assert BrokerResponseError().transient is False


async def _run(owner, *, seconds: float) -> AccountSupervisor:
    stop = asyncio.Event()
    supervisor = AccountSupervisor(owner.name, owner, 0.05, stop, lambda: None)
    supervisor.start()
    await asyncio.sleep(seconds)
    stop.set()
    await supervisor.close()
    return supervisor


async def test_an_outage_keeps_the_account_running_and_it_recovers(tmp_path, monkeypatch):
    monkeypatch.setattr(accounts, "UNREACHABLE_FIRST_RETRY_SECONDS", 0.01)
    owner = _FlakyOwner(tmp_path, [BrokerError(), BrokerError(429), BrokerError(503)])
    stop = asyncio.Event()
    supervisor = AccountSupervisor(owner.name, owner, 0.05, stop, lambda: None)
    supervisor.start()
    try:
        await asyncio.sleep(0.02)
        assert supervisor.state == "running"
        assert supervisor.status.error_code == "broker_unreachable"
        await asyncio.sleep(0.3)
        assert supervisor.state == "running"
        assert supervisor.status.error_code is None
        assert owner.cycles > 3
    finally:
        stop.set()
        await supervisor.close()


async def test_rejected_keys_stop_the_account(tmp_path, monkeypatch):
    monkeypatch.setattr(accounts, "UNREACHABLE_FIRST_RETRY_SECONDS", 0.01)
    owner = _FlakyOwner(tmp_path, [BrokerError(401)])
    supervisor = await _run(owner, seconds=0.1)
    assert supervisor.state == "failed"
    assert supervisor.error_code == "account_unavailable"
    assert owner.cycles == 1
