"""A cycle the supervisor retries after an unexpected failure can never place an order twice.

An order's client ID comes from its post (`copy-` plus a hash of the post and the call's index),
its intent is committed before anything is sent, and a later cycle only looks an order up at the
broker by that ID. So whichever step of the order path the failure interrupts, running the cycle
again sends nothing the first run already sent."""

import pytest

from copytrading_engine.execution.application.engine import CopyEngine
from copytrading_engine.execution.domain.order_lifecycle import OrderStatus
from copytrading_engine.execution.domain.signals import CopyConfig
from copytrading_engine.shared.signals import StockSignal

from .builders import NOW, event, receive
from .fakes import FakeBroker, MemoryRepository


def _cycle(engine: CopyEngine) -> None:
    """What one account cycle does: book what the broker reports, then work the queue."""
    engine.reconcile(NOW)
    engine.process(NOW)
    engine.reconcile(NOW)


@pytest.mark.parametrize(
    ("fails_on", "sent"),
    [
        # Nothing was committed, so the retry prepares the order afresh and sends it once.
        ("order_prepared", 1),
        # The intent is committed but nothing went out: the retry never sends a prepared intent
        # again; it waits for the broker's word on that ID, which is "unknown".
        ("submit_started", 0),
        # The order reached Alpaca and the answer was lost: the retry finds it by its ID.
        ("order_update", 1),
        ("broker_acknowledged", 1),
    ],
)
def test_a_cycle_that_fails_part_way_is_not_sent_twice_when_retried(fails_on, sent):
    repository = MemoryRepository()
    broker = FakeBroker()
    engine = CopyEngine(repository, broker, CopyConfig(sources=["discord:demo"]))
    engine.bind(NOW)
    receive(engine, StockSignal.model_validate(event()), NOW)

    repository.fail_event = fails_on
    with pytest.raises(RuntimeError, match="simulated persistence failure"):
        _cycle(engine)
    repository.fail_event = None

    for _ in range(3):  # the retry, and then the periodic cycles after it
        _cycle(engine)

    assert broker.calls == sent
    assert len(broker.orders) == sent
    [order] = engine.ledger.orders()
    assert order.client_id.startswith("copy-")
    assert list(broker.orders) in ([], [order.client_id])
    if sent:
        assert order.status == OrderStatus.FILLED
    else:
        assert order.status == OrderStatus.UNCERTAIN


def test_the_same_post_cannot_make_a_second_order_intent():
    broker = FakeBroker()
    engine = CopyEngine(MemoryRepository(), broker, CopyConfig(sources=["discord:demo"]))
    engine.bind(NOW)
    receive(engine, StockSignal.model_validate(event()), NOW)
    _cycle(engine)

    # The post is handed over again, as a restarted delivery would.
    receive(engine, StockSignal.model_validate(event()), NOW)
    _cycle(engine)

    assert broker.calls == 1
    assert len(engine.ledger.orders()) == 1
