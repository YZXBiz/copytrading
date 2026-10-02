"""The copy engine over an in-memory repository and scripted broker, plain and instrumented."""

import pytest

from copytrading_engine.execution.application.engine import CopyEngine
from copytrading_engine.execution.application.ports import NoOpObserver
from copytrading_engine.execution.domain.signals import CopyConfig

from .builders import NOW
from .fakes import FakeBroker, MemoryRepository


@pytest.fixture(params=[False, True], ids=["plain", "instrumented"])
def system(tmp_path, request):
    store = MemoryRepository()
    broker = FakeBroker()
    engine = CopyEngine(
        store,
        broker,
        CopyConfig(sources=["discord:demo"]),
        observer=NoOpObserver() if request.param else None,
    )
    engine.bind(NOW)
    return engine, broker, store
