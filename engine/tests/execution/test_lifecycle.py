"""Execution owner startup and partial construction stay on the owner worker."""

import asyncio
import threading

import pytest
from pydantic import SecretStr

from copytrading_engine.execution.adapters import owner as owner_module
from copytrading_engine.execution.adapters import resources as resources_module
from copytrading_engine.execution.adapters.alpaca.broker import AlpacaCredentials
from copytrading_engine.execution.adapters.alpaca.models import decode_account
from copytrading_engine.execution.adapters.owner import ExecutionOwner
from copytrading_engine.execution.domain.signals import CopyConfig

KEYS = AlpacaCredentials(SecretStr("test-key"), SecretStr("test-secret"))


@pytest.mark.parametrize("cancellations", [1, 2])
async def test_cancelled_owner_startup_closes_late_resource_on_worker(
    tmp_path, monkeypatch, cancellations
):
    entered = asyncio.Event()
    release = threading.Event()
    loop = asyncio.get_running_loop()
    timeline = []

    class Resource:
        def close(self):
            timeline.append(("closed", threading.get_ident()))

    def build(*args):
        del args
        timeline.append(("factory", threading.get_ident()))
        loop.call_soon_threadsafe(entered.set)
        if not release.wait(5):
            raise TimeoutError("test did not release owner construction")
        timeline.append(("factory_finished", threading.get_ident()))
        return Resource()

    monkeypatch.setattr(owner_module, "build_resources", build)
    task = asyncio.create_task(
        ExecutionOwner.open(
            tmp_path,
            KEYS,
            CopyConfig(sources=["discord:demo"]),
            environment="paper",
            account_lock_root=tmp_path / "locks",
        )
    )
    try:
        await asyncio.wait_for(entered.wait(), timeout=5)
        for _ in range(cancellations):
            task.cancel()
            await asyncio.sleep(0)
            assert not task.done()
            assert not any(name == "closed" for name, _ in timeline)
        release.set()
        with pytest.raises(asyncio.CancelledError):
            await asyncio.wait_for(task, timeout=5)
        assert [name for name, _ in timeline] == ["factory", "factory_finished", "closed"]
        assert len({thread for _, thread in timeline}) == 1
    finally:
        release.set()
        if not task.done():
            task.cancel()
            await asyncio.gather(task, return_exceptions=True)


async def test_partial_core_construction_closes_acquired_broker_on_owner_worker(
    tmp_path, monkeypatch
):
    thread_ids = []

    class Broker:
        def account(self):

            return decode_account(
                {
                    "id": "paper-demo",
                    "status": "ACTIVE",
                    "cash": "5000",
                    "equity": "5000",
                    "last_equity": "5000",
                    "buying_power": "5000",
                    "currency": "USD",
                    "trading_blocked": False,
                    "account_blocked": False,
                    "trade_suspended_by_user": False,
                }
            )

        def close(self):
            thread_ids.append(threading.get_ident())

    broker = Broker()

    def fail_store(path):
        del path
        thread_ids.append(threading.get_ident())
        raise OSError("controlled store startup failure")

    monkeypatch.setattr(resources_module, "Store", fail_store)
    with pytest.raises(OSError, match="controlled store startup failure"):
        await ExecutionOwner.open(
            tmp_path,
            KEYS,
            CopyConfig(sources=["discord:demo"]),
            environment="paper",
            broker_factory=lambda *_: broker,
            account_lock_root=tmp_path / "locks",
        )
    assert len(thread_ids) == 2
    assert thread_ids[0] == thread_ids[1]
