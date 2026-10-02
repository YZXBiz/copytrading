"""Close must retain ownership until the connection's worker has finished."""

import asyncio
import threading

import pytest

from copytrading_engine.shared.sqlite import SQLiteUnit


async def test_repeated_cancel_and_concurrent_close_drain_one_worker():
    entered = threading.Event()
    release = threading.Event()
    finished = threading.Event()
    calls = []

    class Connection:
        def close(self):
            calls.append(threading.get_ident())
            entered.set()
            if not release.wait(5):
                raise TimeoutError("test did not release SQLite close")
            finished.set()

    unit = SQLiteUnit(Connection())
    first = asyncio.create_task(unit.close())
    second = None
    try:
        assert await asyncio.to_thread(entered.wait, 5)
        first.cancel()
        await asyncio.sleep(0)
        assert not first.done()
        first.cancel()
        second = asyncio.create_task(unit.close())
        await asyncio.sleep(0)
        assert not first.done()
        assert not second.done()
        assert not finished.is_set()
        with pytest.raises(RuntimeError, match="unusable"):
            await unit.run(lambda _: None)
        release.set()
        with pytest.raises(asyncio.CancelledError):
            await first
        await second
        assert finished.is_set()
        assert len(calls) == 1
        await unit.close()
        assert len(calls) == 1
    finally:
        release.set()
        if not first.done():
            await asyncio.gather(first, return_exceptions=True)
        if second is not None and not second.done():
            await asyncio.gather(second, return_exceptions=True)
