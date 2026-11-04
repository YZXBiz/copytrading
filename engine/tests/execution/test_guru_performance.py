"""A guru's performance is read from the ledger and its journal: each sell is matched to the buys
it took from by replaying the fills through the ledger's own lot reduction, and a lot the replay
cannot reproduce is counted as unmatched, never guessed."""

import datetime as dt
from decimal import Decimal

from copytrading_engine.execution.application.engine import CopyEngine
from copytrading_engine.execution.domain.signals import CopyConfig
from copytrading_engine.execution.domain.sizing import DestinationSignal
from copytrading_engine.execution.presentation.guru_performance import (
    REPLAY_KINDS,
    GuruPerformance,
    guru_performance,
)
from copytrading_engine.shared.route_keys import guru_for_channel
from copytrading_engine.shared.signals import StockSignal

from .builders import NOW, destination_signal, event, manual_sale
from .fakes import FakeBroker, MemoryRepository

GURU = guru_for_channel("discord", "demo")
LATER = NOW + dt.timedelta(minutes=1)
LATEST = NOW + dt.timedelta(minutes=2)
NEXT_DAY = NOW + dt.timedelta(days=1)


def _post(*args, **kwargs):
    return event(*args, **kwargs)


def deliver(engine, message, now=NOW):
    """A post from the channel's guru, as an account with a profile receives it."""
    guru = {"guru_id": GURU, "profile_revision": "a" * 64}
    terms = destination_signal(StockSignal.model_validate(message)).terms
    engine.receive(
        DestinationSignal(
            signal=StockSignal.model_validate(message | guru),
            terms=terms.model_copy(update=guru),
        ),
        now,
    )
    engine.process(now)


def _engine() -> tuple[CopyEngine, MemoryRepository]:
    repository = MemoryRepository()
    engine = CopyEngine(repository, FakeBroker(), CopyConfig(sources=["discord:demo"]))
    engine.bind(NOW)
    return engine, repository


def _read(engine, repository, *, guru=GURU, drop=lambda e: False) -> GuruPerformance:
    events = tuple(e for e in repository.events if e.payload.kind in REPLAY_KINDS and not drop(e))
    return guru_performance(
        engine.ledger.snapshot(), events, guru_id=guru, account_id="paper-demo", unrealized_usd=None
    )


def _sells(engine):
    return [o for o in engine.ledger.orders() if o.side == "sell"]


def _buys(engine):
    return [o for o in engine.ledger.orders() if o.side == "buy"]


def test_a_partial_sell_makes_only_what_it_sold():
    engine, repository = _engine()
    deliver(engine, _post("buy", price="25"))
    deliver(engine, _post("half", "reduce", "27", timestamp=LATER), LATER)

    (buy,), (sell,) = _buys(engine), _sells(engine)
    assert 0 < sell.filled_qty < buy.filled_qty
    expected = ((sell.filled_avg_price - buy.filled_avg_price) * sell.filled_qty).quantize(
        Decimal("0.01")
    )
    performance = _read(engine, repository)

    assert performance.closed_trades == 1
    assert performance.unmatched_sells == 0
    assert performance.realized_usd == expected
    assert performance.best == performance.worst
    assert performance.best.symbol == "ABC"
    assert performance.best.source_id == "discord:demo:buy"
    assert performance.best.excerpt == "synthetic fixture buy"
    assert performance.series[-1].cumulative_usd == expected


def test_a_sell_over_two_buys_takes_each_at_its_own_price():
    engine, repository = _engine()
    deliver(engine, _post("low", price="20"))
    deliver(engine, _post("high", price="25", timestamp=LATER), LATER)
    deliver(engine, _post("half", "reduce", "27", timestamp=LATEST), LATEST)

    low, high = _buys(engine)
    assert low.filled_avg_price != high.filled_avg_price
    (lot,) = engine.ledger.lots()
    (sell,) = _sells(engine)
    taken = {
        order.client_id: order.filled_qty - lot.entry_remaining[order.client_id]
        for order in (low, high)
    }
    assert all(qty > 0 for qty in taken.values())
    cost = (
        taken[low.client_id] * low.filled_avg_price + taken[high.client_id] * high.filled_avg_price
    )
    expected = (sell.filled_qty * sell.filled_avg_price - cost).quantize(Decimal("0.01"))

    performance = _read(engine, repository)

    assert performance.unmatched_sells == 0
    assert performance.closed_trades == 1
    assert performance.realized_usd == expected
    # The sale is the post that opened the lot.
    assert performance.best.source_id == "discord:demo:low"


def test_a_sell_naming_one_buys_price_closes_only_that_buy():
    engine, repository = _engine()
    deliver(engine, _post("low", price="20"))
    deliver(engine, _post("high", price="25", timestamp=LATER), LATER)
    deliver(engine, _post("exit", "close", "27", "20", timestamp=LATEST), LATEST)

    low, _ = _buys(engine)
    (sell,) = _sells(engine)
    expected = ((sell.filled_avg_price - low.filled_avg_price) * sell.filled_qty).quantize(
        Decimal("0.01")
    )
    performance = _read(engine, repository)

    assert performance.unmatched_sells == 0
    assert performance.realized_usd == expected


def test_a_sell_the_replay_cannot_reproduce_is_unmatched_not_guessed():
    engine, repository = _engine()
    deliver(engine, _post("buy", price="25"))
    deliver(engine, _post("half", "reduce", "27", timestamp=LATER), LATER)
    (buy,) = _buys(engine)

    # With the buy's fill missing from the journal, the lot cannot be rebuilt.
    performance = _read(
        engine,
        repository,
        drop=lambda e: e.payload.kind == "order_update" and e.payload.client_id == buy.client_id,
    )

    assert performance.unmatched_sells == 1
    assert performance.closed_trades == 0
    assert performance.realized_usd == 0
    assert performance.best is None
    assert performance.series == ()


def test_another_gurus_sells_are_not_counted():
    engine, repository = _engine()
    deliver(engine, _post("buy", price="25"))
    deliver(engine, _post("half", "reduce", "27", timestamp=LATER), LATER)

    performance = _read(engine, repository, guru="guru-other")

    assert (performance.closed_trades, performance.unmatched_sells) == (0, 0)


def test_the_series_adds_up_day_by_day_and_names_the_best_and_worst_call():
    engine, repository = _engine()
    deliver(engine, _post("buy", price="25"))
    deliver(engine, _post("win", "reduce", "27", timestamp=LATER), LATER)
    deliver(engine, _post("loss", "close", "20", timestamp=NEXT_DAY), NEXT_DAY)

    first, second = _sells(engine)
    (buy,) = _buys(engine)
    win = ((first.filled_avg_price - buy.filled_avg_price) * first.filled_qty).quantize(
        Decimal("0.01")
    )
    loss = ((second.filled_avg_price - buy.filled_avg_price) * second.filled_qty).quantize(
        Decimal("0.01")
    )
    performance = _read(engine, repository)

    assert performance.closed_trades == 2
    assert performance.winning_trades == (win > 0) + (loss > 0)
    assert [(p.day, p.cumulative_usd) for p in performance.series] == [
        (dt.date(2026, 1, 5), win),
        (dt.date(2026, 1, 6), win + loss),
    ]
    assert performance.realized_usd == win + loss
    assert performance.best.profit_usd == max(win, loss)
    assert performance.worst.profit_usd == min(win, loss)


def test_the_owners_own_sale_of_a_copied_lot_counts_as_a_closed_trade():
    engine, repository = _engine()
    deliver(engine, _post("buy", price="25"))
    sale = manual_sale(engine)
    engine.ledger.record_manual_sale(sale)
    (buy,) = _buys(engine)
    expected = ((Decimal("26") - buy.filled_avg_price) * Decimal("4")).quantize(Decimal("0.01"))

    performance = _read(engine, repository)

    assert performance.unmatched_sells == 0
    assert performance.closed_trades == 1
    assert performance.realized_usd == expected
