"""A decision's independent broker reads overlap instead of waiting for each other."""

import threading
import time

from copytrading_engine.execution.application.engine import CopyEngine
from copytrading_engine.execution.domain.signals import CopyConfig

from .builders import NOW, deliver, event
from .fakes import FakeBroker, MemoryRepository


class SlowBroker(FakeBroker):
    """Each read is a slow round trip; it records how many were in flight at once."""

    def __init__(self):
        super().__init__()
        self._lock = threading.Lock()
        self._in_flight = 0
        self.most_in_flight = 0

    def _slow(self, read):
        with self._lock:
            self._in_flight += 1
            self.most_in_flight = max(self.most_in_flight, self._in_flight)
        try:
            time.sleep(0.15)
            return read()
        finally:
            with self._lock:
                self._in_flight -= 1

    def asset(self, symbol):
        return self._slow(lambda: super(SlowBroker, self).asset(symbol))

    def account(self):
        return self._slow(super().account)

    def positions(self):
        return self._slow(super().positions)

    def open_orders(self):
        return self._slow(super().open_orders)


def test_entry_reads_go_out_together_and_still_place_the_order():
    broker = SlowBroker()
    engine = CopyEngine(MemoryRepository(), broker, CopyConfig(sources=["discord:demo"]))
    engine.bind(NOW)
    broker.most_in_flight = 0

    deliver(engine, event())

    assert broker.most_in_flight >= 3
    assert broker.orders, "the overlapping reads must still end in the same order"


class CountingBroker(FakeBroker):
    def __init__(self):
        super().__init__()
        self.reads: list[str] = []

    def account(self):
        self.reads.append("account")
        return super().account()

    def positions(self):
        self.reads.append("positions")
        return super().positions()

    def open_orders(self):
        self.reads.append("open_orders")
        return super().open_orders()


async def test_an_idle_cycle_reads_each_broker_fact_once_per_check(tmp_path, monkeypatch):
    """An idle cycle read the positions four times and the account twice, and every Alpaca
    positions read fetched the account again: eleven requests every two seconds, past Alpaca's
    200 a minute. Each reconcile now reads the positions once, and the audit and the holdings
    inspection share that read and the cycle's one account read."""
    import datetime as dt

    from .test_account_lifecycle import _open

    datetime_type = dt.datetime

    class FixedDateTime(datetime_type):
        @classmethod
        def now(cls, tz=None):
            fixed = cls(2026, 1, 5, 15, 0, tzinfo=dt.UTC)
            return fixed if tz is None else fixed.astimezone(tz)

    monkeypatch.setattr(dt, "datetime", FixedDateTime)
    broker = CountingBroker()
    owner = await _open(tmp_path, broker)
    try:
        await owner.cycle(NOW, halted=False)
        broker.reads.clear()
        await owner.cycle(NOW, halted=False)
        assert sorted(broker.reads) == ["account", "open_orders", "positions", "positions"]
    finally:
        await owner.close()
