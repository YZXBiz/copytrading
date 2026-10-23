"""A copied sell stopped between being saved and being sent is never lost (ADR-0010): its call
waits again, and the next attempt goes out under a new client order ID tied to the post."""

import datetime as dt

from copytrading_engine.execution.application.engine import CopyEngine
from copytrading_engine.execution.domain.events import SendAborted
from copytrading_engine.execution.domain.order_lifecycle import OrderStatus
from copytrading_engine.execution.domain.orders import copy_client_id
from copytrading_engine.execution.domain.progress import OrderLinked, Pending
from copytrading_engine.execution.domain.signals import CopyConfig
from copytrading_engine.execution.presentation.operator_views import destination_views
from copytrading_engine.shared.signals import StockSignal

from .builders import NOW, deliver, event, receive
from .fakes import FakeBroker, MemoryRepository

SELL = "discord:demo:sell"


def _stops_while_sending():
    """CopyTrading starts stopping after the sell is planned and saved, before it is sent: the
    third check (start, after planning, before sending) is the first to see it."""
    checks = 0

    def stopping() -> bool:
        nonlocal checks
        checks += 1
        return checks >= 3

    return stopping


def _held_and_sold_at_once() -> tuple[CopyEngine, FakeBroker, MemoryRepository]:
    repository, broker = MemoryRepository(), FakeBroker()
    engine = CopyEngine(repository, broker, CopyConfig(sources=["discord:demo"]))
    engine.bind(NOW)
    deliver(engine, event())
    receive(engine, StockSignal.model_validate(event("sell", "close", "27", "25")), NOW)
    engine.process(NOW, stopping=_stops_while_sending())
    return engine, broker, repository


def test_a_sell_stopped_before_it_was_sent_goes_out_on_the_next_start_as_attempt_2():
    engine, broker, repository = _held_and_sold_at_once()
    first = copy_client_id(SELL, 0)
    assert engine.ledger.order(first).status is OrderStatus.ABORTED_BEFORE_SUBMIT
    assert engine.ledger.message(SELL).parts == (Pending(),)
    [aborted] = [e.payload for e in repository.events if isinstance(e.payload, SendAborted)]
    assert (aborted.client_id, aborted.reason) == (first, "stopping")
    assert broker.holdings["ABC"] == 4

    engine.process(NOW + dt.timedelta(seconds=5))

    second = copy_client_id(SELL, 0, 2)
    assert second == f"{first}-2"
    assert engine.ledger.message(SELL).parts == (OrderLinked(client_id=second),)
    assert broker.orders[second]["status"] == "filled"
    assert broker.holdings["ABC"] == 0
    [view] = destination_views(engine.ledger.snapshot(), {SELL}, tuple(repository.events)).values()
    assert [order.client_id for order in view.orders] == [second]


def test_a_restart_after_the_abort_sends_the_sell_exactly_once():
    """CopyTrading crashes right after the abort was saved; the next start reads the ledger
    back, sends attempt 2 once, and never again on later cycles."""
    _, broker, repository = _held_and_sold_at_once()
    sent = broker.calls

    restarted = CopyEngine(repository, broker, CopyConfig(sources=["discord:demo"]))
    restarted.bind(NOW + dt.timedelta(seconds=5))
    restarted.process(NOW + dt.timedelta(seconds=5))
    restarted.process(NOW + dt.timedelta(seconds=10))
    again = CopyEngine(repository, broker, CopyConfig(sources=["discord:demo"]))
    again.bind(NOW + dt.timedelta(seconds=15))
    again.process(NOW + dt.timedelta(seconds=15))

    assert broker.calls == sent + 1
    assert [cid for cid in broker.orders if cid.startswith(copy_client_id(SELL, 0))] == [
        copy_client_id(SELL, 0, 2)
    ]
    assert broker.holdings["ABC"] == 0


def test_a_buy_stopped_before_it_was_sent_is_still_given_up():
    repository, broker = MemoryRepository(), FakeBroker()
    engine = CopyEngine(repository, broker, CopyConfig(sources=["discord:demo"]))
    engine.bind(NOW)
    receive(engine, StockSignal.model_validate(event()), NOW)

    engine.process(NOW, stopping=_stops_while_sending())
    engine.process(NOW + dt.timedelta(seconds=5))

    buy = copy_client_id("discord:demo:1", 0)
    assert engine.ledger.order(buy).status is OrderStatus.ABORTED_BEFORE_SUBMIT
    assert engine.ledger.message("discord:demo:1").parts == (OrderLinked(client_id=buy),)
    assert broker.calls == 0
