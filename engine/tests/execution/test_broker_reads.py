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
