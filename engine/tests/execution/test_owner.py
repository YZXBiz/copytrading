"""The real owner executor drains canceled work before resource teardown."""

import asyncio
import datetime as dt
import threading
from contextlib import ExitStack
from decimal import Decimal
from types import SimpleNamespace
from typing import cast

import pytest
import pytest_asyncio

from copytrading_engine.execution.adapters.owner import ExecutionOwner
from copytrading_engine.execution.adapters.resources import ExecutionResources
from copytrading_engine.execution.adapters.sqlite_ledger import Store
from copytrading_engine.execution.application.engine import CopyEngine
from copytrading_engine.execution.domain.ledger_state import LedgerSnapshot, MessageRecord
from copytrading_engine.execution.domain.progress import Skipped
from copytrading_engine.shared.queue_snapshot import QueueSnapshot
from copytrading_engine.shared.signals import StockSignal

from .builders import destination_signal, event
from .fakes import FakeBroker


class Probe:
    """Stands in for ExecutionResources: blocks on demand and reports a usable store."""

    def __init__(self) -> None:
        self.store = SimpleNamespace(usable=True)
        self.entered = threading.Event()
        self.release = threading.Event()
        self.close_entered = threading.Event()
        self.close_release = threading.Event()
        self.close_release.set()
        self.thread_ids: list[int] = []
        self.calls: list[str] = []
        self.thread_ids.append(threading.get_ident())
        self.calls.append("factory")

    def blocking_operation(self) -> None:
        self.thread_ids.append(threading.get_ident())
        self.calls.append("entered")
        self.entered.set()
        if not self.release.wait(timeout=5):
            raise TimeoutError("test did not release the probe worker")
        self.calls.append("finished")

    def close(self) -> None:
        self.thread_ids.append(threading.get_ident())
        self.calls.append("close_started")
        self.close_entered.set()
        if not self.close_release.wait(timeout=5):
            raise TimeoutError("test did not release the resource closer")
        self.calls.append("closed")


class ProbeOwner(ExecutionOwner):
    def __init__(self) -> None:
        super().__init__()
        self.close_started = asyncio.Event()

    @property
    def resource(self) -> Probe:
        return cast(Probe, self._resource)

    async def blocking_probe(self) -> None:
        await self._submit(lambda probe: probe.blocking_operation())

    async def _close_resources(self) -> None:
        self.close_started.set()
        await super()._close_resources()


@pytest_asyncio.fixture
async def probe_owner():
    owner = cast(
        ProbeOwner,
        await ProbeOwner._from_resource_factory(Probe, lambda probe: probe.close()),
    )
    try:
        yield owner
    finally:
        owner.resource.release.set()
        owner.resource.close_release.set()
        await owner.close()


@pytest.mark.parametrize("cancellations", [1, 2])
async def test_owner_drains_before_close(probe_owner, cancellations):
    entered = probe_owner.resource.entered
    release = probe_owner.resource.release
    calls = probe_owner.resource.calls
    task = asyncio.create_task(probe_owner.blocking_probe())
    assert await asyncio.to_thread(entered.wait, timeout=5)
    task.cancel()
    await asyncio.sleep(0)
    assert not task.done()
    if cancellations == 2:
        task.cancel()
        await asyncio.sleep(0)
        assert not task.done()
    closing = asyncio.create_task(probe_owner.close())
    assert "closed" not in calls
    release.set()
    with pytest.raises(asyncio.CancelledError):
        await task
    await closing
    assert calls[-1] == "closed"
    assert len(set(probe_owner.resource.thread_ids)) == 1


async def test_close_drains_repeated_cancellation_while_waiting_for_gate(probe_owner):
    resource = probe_owner.resource
    resource.close_release.clear()
    operation = asyncio.create_task(probe_owner.blocking_probe())
    closing = None
    try:
        assert await asyncio.to_thread(resource.entered.wait, timeout=5)
        closing = asyncio.create_task(probe_owner.close())
        await asyncio.wait_for(probe_owner.close_started.wait(), timeout=5)
        closing.cancel()
        await asyncio.sleep(0)
        assert not closing.done()
        closing.cancel()
        await asyncio.sleep(0)
        assert not closing.done()
        assert "closed" not in resource.calls

        resource.release.set()
        assert await asyncio.to_thread(resource.close_entered.wait, timeout=5)
        assert not closing.done()
        closing.cancel()
        await asyncio.sleep(0)
        assert not closing.done()
        resource.close_release.set()

        await operation
        with pytest.raises(asyncio.CancelledError):
            await closing
        assert resource.calls == ["factory", "entered", "finished", "close_started", "closed"]
        assert len(set(resource.thread_ids)) == 1
        assert probe_owner._closed
        assert probe_owner._executor._shutdown
    finally:
        resource.release.set()
        resource.close_release.set()
        if not operation.done():
            await asyncio.wait_for(asyncio.gather(operation, return_exceptions=True), timeout=5)
        if closing is not None and not closing.done():
            await asyncio.wait_for(asyncio.gather(closing, return_exceptions=True), timeout=5)


async def test_owner_observation_detaches_nested_ledger_state(tmp_path):
    signal = StockSignal.model_validate(event())
    message = MessageRecord.model_validate(
        {
            **signal.model_dump(mode="python"),
            "source_key": "discord:demo",
            "parts": (Skipped(reason="synthetic"),),
            "status": "done",
            "destination": destination_signal(signal).terms,
        }
    )
    ledger = LedgerSnapshot(account_id="paper-demo", messages={message.key: message})
    core = ExecutionResources(
        stack=ExitStack(),
        store=cast(Store, SimpleNamespace(report_snapshot=lambda: QueueSnapshot(0, None, 0))),
        broker=FakeBroker(),
        engine=cast(
            CopyEngine,
            SimpleNamespace(
                ledger=SimpleNamespace(
                    snapshot=lambda: ledger,
                    exposure=lambda: Decimal("42.50"),
                )
            ),
        ),
        account=FakeBroker().account(),
        data_dir=tmp_path,
        account_observed_at=dt.datetime(2026, 9, 26, 15, tzinfo=dt.UTC),
    )
    owner = await ExecutionOwner._from_resource_factory(lambda: core, lambda resource: None)
    try:
        observation = await owner._submit(lambda resource: resource.observation())
        assert observation.ledger is not ledger
        assert observation.ledger.messages == ledger.messages
        assert observation.total_cost_exposure_usd == Decimal("42.50")
        observation.ledger.messages.clear()
        assert message.key in ledger.messages
    finally:
        await owner.close()
