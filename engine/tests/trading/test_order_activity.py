"""A live order update or a new call reconciles the account at once; while the order stream
is live and nothing waits on a clock, the periodic check slows to a safety net."""

import asyncio
import datetime as dt
from types import SimpleNamespace

from copytrading_engine.trading.application.accounts import (
    STREAM_SAFETY_SECONDS,
    AccountSupervisor,
)

from .runtime.fakes import Owner


class _StreamingOwner(Owner):
    """An owner whose broker reports order changes as they happen."""

    def __init__(self, path):
        super().__init__(path, {}, {})
        self.report = None
        self.live = None

    async def watch_orders(self, on_update, on_live, stop: asyncio.Event) -> None:
        self.report = on_update
        self.live = on_live
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


async def test_a_live_stream_slows_the_check_only_while_nothing_waits_on_a_clock(tmp_path):
    owner = _StreamingOwner(tmp_path)
    stop = asyncio.Event()
    supervisor = AccountSupervisor("primary", owner, 2.0, stop, lambda: None)
    supervisor.start()
    try:
        await asyncio.sleep(0.05)
        assert supervisor.check_seconds == 2.0, "no stream yet: the short interval"

        owner.live(True)
        assert supervisor.check_seconds == STREAM_SAFETY_SECONDS

        # An open order or a call still to act on needs its timer: back to the short interval.
        owner.outstanding_work = True
        owner.report()
        await asyncio.sleep(0.1)
        assert supervisor.check_seconds == 2.0

        owner.outstanding_work = False
        owner.report()
        await asyncio.sleep(0.1)
        assert supervisor.check_seconds == STREAM_SAFETY_SECONDS
    finally:
        stop.set()
        await asyncio.sleep(0)
        await owner.close()


async def test_a_dropped_stream_reconciles_at_once_and_checks_often_again(tmp_path):
    owner = _StreamingOwner(tmp_path)
    stop = asyncio.Event()
    supervisor = AccountSupervisor("primary", owner, 2.0, stop, lambda: None)
    supervisor.start()
    try:
        await asyncio.sleep(0.05)
        owner.live(True)
        before = owner.cycles

        owner.live(False)

        assert await _cycles_after(owner, wait=0.1) == before + 1
        assert supervisor.check_seconds == 2.0
    finally:
        stop.set()
        await asyncio.sleep(0)
        await owner.close()


async def test_a_new_call_is_acted_on_at_once_not_at_the_next_check(tmp_path):
    owner = _StreamingOwner(tmp_path)
    stop = asyncio.Event()
    supervisor = AccountSupervisor(owner.name, owner, 30.0, stop, lambda: None)
    supervisor.start()
    delivery = SimpleNamespace(
        terms=SimpleNamespace(connection=SimpleNamespace(account_id=owner.name)),
        signal=SimpleNamespace(source="discord", channel_id="1", id="1"),
    )
    try:
        await asyncio.sleep(0.05)
        before = owner.cycles

        await supervisor.receive(delivery, dt.datetime.now(dt.UTC))

        assert await _cycles_after(owner, wait=0.1) == before + 1
    finally:
        stop.set()
        await asyncio.sleep(0)
        await owner.close()
