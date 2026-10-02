"""A cancelled open still closes its SQLite connection."""

import asyncio
import threading

import pytest

from copytrading_engine.shared.sqlite import SQLiteUnit


async def test_cancelled_open_drains_connection_and_closes_it(monkeypatch, tmp_path):
    import copytrading_engine.shared.sqlite as module

    started = threading.Event()
    proceed = threading.Event()
    closed = threading.Event()

    class Connection:
        def execute(self, sql):
            return None

        def close(self):
            closed.set()

    def connect(*args, **kwargs):
        started.set()
        proceed.wait(timeout=5)
        return Connection()

    monkeypatch.setattr(module.sqlite3, "connect", connect)
    task = asyncio.create_task(SQLiteUnit.open(tmp_path / "app.db"))
    assert await asyncio.to_thread(started.wait, 5)
    task.cancel()
    proceed.set()
    with pytest.raises(asyncio.CancelledError):
        await task
    assert closed.is_set()
