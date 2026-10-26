"""A sell held because none of the account's buys is at the price it names says why: the guru's
buy at that price was refused, already sold, or never reached the account (ADR-0010)."""

import datetime as dt

from copytrading_engine.execution.application.engine import CopyEngine
from copytrading_engine.execution.domain.progress import Skipped
from copytrading_engine.execution.domain.signals import CopyConfig
from copytrading_engine.execution.presentation.operator_views import NamedBuy, destination_views

from .builders import NOW, deliver, event
from .fakes import FakeBroker, MemoryRepository

LATER = NOW + dt.timedelta(minutes=1)
LATEST = NOW + dt.timedelta(minutes=2)


def _engine() -> CopyEngine:
    engine = CopyEngine(MemoryRepository(), FakeBroker(), CopyConfig(sources=["discord:demo"]))
    engine.bind(NOW)
    return engine


def _named(engine: CopyEngine, sell: str) -> tuple[NamedBuy, ...]:
    source = f"discord:demo:{sell}"
    assert engine.ledger.message(source).parts == (Skipped(reason="named_buy_not_held"),)
    return destination_views(engine.ledger.snapshot(), {source})[source].named_buys


def test_a_sell_of_a_buy_refused_by_the_daily_entry_limit_says_so():
    engine = _engine()
    deliver(engine, event("held", price="20"))
    # The day's one entry is used: the guru's buy at $25 is refused.
    engine.config = CopyConfig.model_validate(
        engine.config.model_dump() | {"max_entries_per_day": 1}
    )
    deliver(engine, event("refused", price="25", timestamp=LATER), LATER)

    deliver(engine, event("sell", "close", "27", "25", timestamp=LATEST), LATEST)

    assert _named(engine, "sell") == (NamedBuy(part=0, posted_at=LATER, outcome="daily_entry_cap"),)


def test_a_sell_of_a_buy_already_sold_says_so():
    engine = _engine()
    deliver(engine, event("held", price="20"))
    deliver(engine, event("sold", price="25", timestamp=LATER), LATER)
    deliver(engine, event("first-sell", "close", "27", "25", timestamp=LATEST), LATEST)
    again = LATEST + dt.timedelta(minutes=1)

    deliver(engine, event("sell", "close", "28", "25", timestamp=again), again)

    assert _named(engine, "sell") == (NamedBuy(part=0, posted_at=LATER, outcome="sold"),)


def test_a_sell_of_a_buy_that_never_reached_the_account_says_so():
    engine = _engine()
    deliver(engine, event("held", price="20"))

    deliver(engine, event("sell", "close", "27", "30", timestamp=LATER), LATER)

    assert _named(engine, "sell") == (NamedBuy(part=0, posted_at=None, outcome=None),)
