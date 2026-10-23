"""A sell with no price to sell at keeps waiting (ADR-0010), without spending Alpaca's request
budget: it asks again at most every 30 seconds, and Activity says what it waits for."""

import datetime as dt
from decimal import Decimal

from copytrading_engine.execution.application.engine import CopyEngine
from copytrading_engine.execution.domain.market import Quote
from copytrading_engine.execution.domain.progress import OrderLinked, Pending, Skipped
from copytrading_engine.execution.domain.signals import CopyConfig
from copytrading_engine.execution.presentation.operator_views import destination_views
from copytrading_engine.shared.signals import StockSignal

from .builders import NOW, deliver, event, evidence, receive
from .fakes import FakeBroker, MemoryRepository


class CountingMarket(FakeBroker):
    """A broker that counts every read, with a bid quoted at `quoted_at`."""

    def __init__(self) -> None:
        super().__init__()
        self.quoted_at = NOW - dt.timedelta(hours=7)
        self.reads = 0

    def quote(self, symbol: str) -> Quote:
        self.reads += 1
        return Quote(feed="iex", bid=Decimal("26"), ask=Decimal("26.01"), timestamp=self.quoted_at)

    def asset(self, symbol):
        self.reads += 1
        return super().asset(symbol)

    def account(self):
        self.reads += 1
        return super().account()

    def positions(self):
        self.reads += 1
        return super().positions()

    def open_orders(self):
        self.reads += 1
        return super().open_orders()


def _waiting_sell() -> tuple[CopyEngine, CountingMarket]:
    broker = CountingMarket()
    engine = CopyEngine(MemoryRepository(), broker, CopyConfig(sources=["discord:demo"]))
    engine.bind(NOW)
    deliver(engine, event())
    at_market = event("sell", "close", "27", "25", timestamp=NOW)
    at_market["instructions"][0]["price"] = None
    at_market["evidence"] = [evidence(at_market["instructions"][0])]
    deliver(engine, at_market)
    return engine, broker


def test_a_sell_waiting_for_a_quote_asks_alpaca_at_most_every_30_seconds():
    """The app polls every 2 seconds. A sell with only a seven-hour-old quote used to be planned on
    every poll, five Alpaca requests each: 150 a minute for one sell, against Alpaca's 200."""
    engine, broker = _waiting_sell()
    broker.reads = 0

    for second in range(2, 61, 2):
        engine.process(NOW + dt.timedelta(seconds=second))

    assert broker.reads <= 2 * 5
    assert engine.ledger.message("discord:demo:sell").parts == (Pending(waiting="quote_stale"),)


def test_a_waiting_sell_goes_out_once_a_fresh_quote_arrives():
    engine, broker = _waiting_sell()
    later = NOW + dt.timedelta(seconds=31)
    broker.quoted_at = later
    engine.process(later)

    assert isinstance(engine.ledger.message("discord:demo:sell").parts[0], OrderLinked)
    assert broker.holdings["ABC"] == 0


def test_activity_says_the_sell_waits_for_a_price():
    engine, _ = _waiting_sell()
    engine.process(NOW + dt.timedelta(seconds=2))

    [destination] = destination_views(engine.ledger.state, {"discord:demo:sell"}).values()

    assert destination.instruction_outcomes == ("waiting_for_quote",)


def test_a_sell_read_as_copying_stops_waits_for_the_next_start():
    """A sell reached while CopyTrading is stopping used to be skipped as "stopping" and lost; it
    stays waiting and goes out when copying runs again. A buy is still skipped."""
    broker = FakeBroker()
    engine = CopyEngine(MemoryRepository(), broker, CopyConfig(sources=["discord:demo"]))
    engine.bind(NOW)
    deliver(engine, event())
    receive(engine, StockSignal.model_validate(event("sell", "close", "27", "25")), NOW)
    receive(engine, StockSignal.model_validate(_on("DEF", "buy")), NOW)

    engine.process(NOW, stopping=lambda: True)
    assert engine.ledger.message("discord:demo:sell").parts == (Pending(),)
    assert engine.ledger.message("discord:demo:buy").parts == (Skipped(reason="stopping"),)

    engine.process(NOW + dt.timedelta(seconds=1))
    assert isinstance(engine.ledger.message("discord:demo:sell").parts[0], OrderLinked)


def _on(symbol, *args, **kwargs):
    post = event(*args, **kwargs)
    post["instructions"][0]["symbol"] = symbol
    post["evidence"] = [evidence(instruction) for instruction in post["instructions"]]
    return post
