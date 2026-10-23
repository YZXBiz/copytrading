"""A sell is never too old (ADR-0010): a sell read late still goes out, at its floor under the
guru's sell price, while a late buy is skipped."""

import datetime as dt
from decimal import Decimal

from copytrading_engine.execution.application.engine import CopyEngine
from copytrading_engine.execution.domain.market import Quote
from copytrading_engine.execution.domain.progress import OrderLinked, Skipped
from copytrading_engine.execution.domain.signals import CopyConfig

from .builders import NOW, deliver, event, evidence
from .fakes import FakeBroker, MemoryRepository

LATE = NOW + dt.timedelta(hours=2)


class Market(FakeBroker):
    """A broker whose bid for every stock is `bid`, quoted now."""

    def __init__(self, bid: str, at: dt.datetime = LATE) -> None:
        super().__init__()
        self.bid = Decimal(bid)
        self.at = at

    def quote(self, symbol: str) -> Quote:
        return Quote(feed="iex", bid=self.bid, ask=self.bid + Decimal("0.01"), timestamp=self.at)


def _engine(broker: FakeBroker) -> CopyEngine:
    engine = CopyEngine(MemoryRepository(), broker, CopyConfig(sources=["discord:demo"]))
    engine.bind(NOW)
    return engine


def test_a_sell_read_two_hours_late_is_copied_at_its_floor_under_the_gurus_price():
    broker = Market("22.00")
    engine = _engine(broker)
    deliver(engine, event())

    # The guru sold at $27 two hours ago; the stock has since fallen to $22. The copy still goes
    # out, and still never sells under 1% below the guru's $27.
    deliver(engine, event("exit", "close", "27", "25"), LATE)

    assert isinstance(engine.ledger.message("discord:demo:exit").parts[0], OrderLinked)
    sale = engine.ledger.orders()[-1]
    assert (sale.side, sale.source_price, sale.limit_price) == (
        "sell",
        Decimal(27),
        Decimal("26.73"),
    )


def test_a_sell_with_no_price_takes_its_floor_from_the_bid():
    broker = Market("26.10", at=NOW)
    engine = _engine(broker)
    deliver(engine, event())
    exit_signal = event("exit", "close", "27", "25", timestamp=NOW + dt.timedelta(seconds=1))
    exit_signal["instructions"][0]["price"] = None
    exit_signal["evidence"][0] = evidence(exit_signal["instructions"][0])

    deliver(engine, exit_signal)

    sale = engine.ledger.orders()[-1]
    # 1% under the $26.10 bid, rounded up to a cent.
    assert (sale.source_price, sale.limit_price) == (Decimal("26.10"), Decimal("25.84"))


def test_a_late_post_skips_its_buys_as_too_old_and_copies_its_sells():
    broker = Market("26.00")
    engine = _engine(broker)
    deliver(engine, event())
    message = event("mixed", "close", "27", "25")
    message["instructions"].append({**event()["instructions"][0], "symbol": "DEF", "price": "20"})
    message["evidence"].append(evidence(message["instructions"][1]))

    deliver(engine, message, LATE)

    sell, buy = engine.ledger.message("discord:demo:mixed").parts
    assert isinstance(sell, OrderLinked)
    assert buy == Skipped(reason="stale")
    assert engine.ledger.message("discord:demo:mixed").status != "stale"


def test_a_late_post_of_only_buys_is_stale():
    engine = _engine(Market("25.00"))

    deliver(engine, event("late-buy"), NOW + dt.timedelta(minutes=11))

    message = engine.ledger.message("discord:demo:late-buy")
    assert message.status == "stale"
    assert not engine.ledger.orders()


# --- A sell only takes from buys posted before it ------------------------------------------------

MONDAY = NOW
WEDNESDAY = NOW + dt.timedelta(days=2)


def test_a_mondays_sell_read_after_a_wednesday_buy_leaves_the_wednesday_shares():
    """The guru sold Monday while CopyTrading was stopped, then bought again Wednesday, which was
    copied; Monday's sell read back afterwards must not sell Wednesday's shares."""
    broker = FakeBroker()
    engine = _engine(broker)
    deliver(engine, event("wed-buy", timestamp=WEDNESDAY), WEDNESDAY)
    bought = broker.holdings["ABC"]

    later = WEDNESDAY + dt.timedelta(minutes=1)
    deliver(engine, event("mon-sell", "close", "27", timestamp=MONDAY), later)

    assert engine.ledger.message("discord:demo:mon-sell").parts == (
        Skipped(reason="bought_after_sell", bought_at=WEDNESDAY),
    )
    assert broker.holdings["ABC"] == bought


def _two_buys_and_a_sell_between(action: str) -> tuple[CopyEngine, FakeBroker, str, str]:
    broker = FakeBroker()
    engine = _engine(broker)
    deliver(engine, event("early", price="25"))
    two_hours = NOW + dt.timedelta(hours=2)
    deliver(engine, event("late", price="20", timestamp=two_hours), two_hours)
    early, late = (order.client_id for order in engine.ledger.orders())
    # Posted between the two buys, read after both.
    deliver(
        engine,
        event("between", action, "26", timestamp=NOW + dt.timedelta(hours=1)),
        NOW + dt.timedelta(hours=3),
    )
    return engine, broker, early, late


def test_a_sell_posted_between_two_buys_sells_only_the_earlier_one():
    engine, broker, early, late = _two_buys_and_a_sell_between("close")

    sale = engine.ledger.orders()[-1]
    assert (sale.side, sale.from_entries) == ("sell", (early,))
    assert sale.qty == engine.ledger.order(early).filled_qty
    assert broker.holdings["ABC"] == engine.ledger.order(late).filled_qty


def test_sell_half_posted_between_two_buys_is_half_of_the_earlier_one():
    engine, _, early, _ = _two_buys_and_a_sell_between("reduce")

    sale = engine.ledger.orders()[-1]
    assert sale.from_entries == (early,)
    assert sale.qty == engine.ledger.order(early).filled_qty / 2


def test_a_sell_posted_after_every_buy_sells_them_all_as_before():
    broker = FakeBroker()
    engine = _engine(broker)
    deliver(engine, event("early", price="25"))
    one_hour, two_hours = NOW + dt.timedelta(hours=1), NOW + dt.timedelta(hours=2)
    deliver(engine, event("late", price="20", timestamp=one_hour), one_hour)

    deliver(engine, event("after", "close", "26", timestamp=two_hours), two_hours)

    assert engine.ledger.orders()[-1].from_entries == ()
    assert broker.holdings["ABC"] == 0


def test_half_of_the_original_read_late_counts_only_buys_posted_before_it():
    """Monday: the guru buys 4 at $25, then posts "sell half of the original". Tuesday: a buy at
    $20 is copied and sold out again. Monday's sell, read back on Wednesday, sells half of
    Monday's 4, never half of Monday's and Tuesday's 9 together, which would sell all of
    Monday's."""
    broker = FakeBroker()
    engine = _engine(broker)
    deliver(engine, event("mon-buy", price="25", timestamp=MONDAY), MONDAY)
    tuesday = MONDAY + dt.timedelta(days=1)
    deliver(engine, event("tue-buy", price="20", timestamp=tuesday), tuesday)
    sold_out = tuesday + dt.timedelta(minutes=1)
    deliver(engine, event("tue-sell", "close", "21", "20", timestamp=sold_out), sold_out)
    assert broker.holdings["ABC"] == 4

    late = event("mon-sell", "reduce", "26", timestamp=MONDAY + dt.timedelta(hours=1))
    late["instructions"][0]["exit_basis"] = "original_position"
    late["evidence"] = [evidence(instruction) for instruction in late["instructions"]]
    deliver(engine, late, WEDNESDAY)

    assert engine.ledger.orders()[-1].qty == 2
    assert broker.holdings["ABC"] == 2
