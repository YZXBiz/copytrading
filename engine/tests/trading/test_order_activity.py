"""A live order update reconciles the account at once instead of waiting for the next check."""

import asyncio

from copytrading_engine.trading.application.accounts import AccountSupervisor

from .runtime.fakes import Owner


class _StreamingOwner(Owner):
    """An owner whose broker reports order changes as they happen."""

    def __init__(self, path):
        super().__init__(path, {}, {})
        self.report = None

    async def watch_orders(self, on_update, stop: asyncio.Event) -> None:
        self.report = on_update
        await stop.wait()


async def _cycles_after(owner, *, wait: float) -> int:
    await asyncio.sleep(wait)
    return owner.cycles


async def test_an_order_update_reconciles_now_even_with_a_long_periodic_check(tmp_path):
    owner = _StreamingOwner(tmp_path)
    stop = asyncio.Event()
    supervisor = AccountSupervisor("primary", owner, 30.0, stop, lambda: None)
    supervisor.start()
    try:
        assert await _cycles_after(owner, wait=0.1) == 1
        assert owner.report is not None

        owner.report()

        assert await _cycles_after(owner, wait=0.2) == 2
    finally:
        stop.set()
        await asyncio.sleep(0)
        await owner.close()


async def test_an_owner_without_a_stream_keeps_the_periodic_check(tmp_path):
    owner = Owner(tmp_path, {}, {})
    stop = asyncio.Event()
    supervisor = AccountSupervisor("primary", owner, 0.1, stop, lambda: None)
    supervisor.start()
    try:
        assert await _cycles_after(owner, wait=0.35) >= 3
    finally:
        stop.set()
        await asyncio.sleep(0)
        await owner.close()
