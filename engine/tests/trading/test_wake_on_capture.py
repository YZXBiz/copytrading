"""A newly captured post wakes the processing loop at once instead of on its next tick."""

import asyncio
import datetime as dt

from copytrading_engine.shared.raw_message import RawMessage
from copytrading_engine.sources.sqlite import SQLiteSourceStore
from copytrading_engine.trading.entrypoints.runtime import TradingRuntime


def _raw(message_id: int) -> RawMessage:
    return RawMessage(
        schema_version=1,
        event_type="raw_message",
        source="discord",
        channel_id="7",
        id=str(message_id),
        timestamp=dt.datetime.now(dt.UTC),
        text="Bought AAPL",
    )


async def test_a_new_live_capture_wakes_the_loop_but_a_replay_does_not(tmp_path):
    wakes: list[None] = []
    source = await SQLiteSourceStore.open(
        tmp_path / "app.db", on_captured=lambda: wakes.append(None)
    )
    first = _raw(1)
    try:
        await source.add(first)
        await source.add(first)
        await source.add(_raw(2))
    finally:
        await source.close()

    assert len(wakes) == 2


async def test_the_loop_wait_ends_when_work_arrives_or_on_stop(tmp_path):
    runtime = TradingRuntime(tmp_path)
    loop = asyncio.get_running_loop()

    loop.call_later(0.05, runtime._wake)
    started = loop.time()
    await runtime._idle(5)
    assert loop.time() - started < 1

    runtime._work_arrived.clear()
    loop.call_later(0.05, runtime._stop.set)
    started = loop.time()
    await runtime._idle(5)
    assert loop.time() - started < 1


async def test_with_nothing_to_do_the_loop_still_ticks(tmp_path):
    runtime = TradingRuntime(tmp_path)
    loop = asyncio.get_running_loop()

    started = loop.time()
    await runtime._idle(0.1)

    assert 0.05 < loop.time() - started < 1
