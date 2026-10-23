"""What a post does while an order for its stock is still open (ADR-0010).

A copied sell rests at its floor until it sells, so later posts on the stock must not queue behind
it: a buy waits only for an earlier open buy, or for a sell it would trade with; a sell never
waits for or cancels an open sell, and plans against the shares the open sells have not taken;
and a sell cancels only the open buy it would have sold.
"""

import datetime as dt
from decimal import Decimal

from copytrading_engine.execution.domain.order_lifecycle import OrderStatus
from copytrading_engine.execution.domain.progress import OrderLinked, Pending, Skipped

from .builders import NOW, deliver, event


def _resting(system):
    """Four shares bought at $25, and a broker that leaves every later order open."""
    engine, broker, _ = system
    deliver(engine, event())
    assert broker.holdings["ABC"] == 4
    broker.auto_fill = False
    return engine, broker


def _part(engine, post):
    return engine.ledger.message(f"discord:demo:{post}").parts[0]


def _open(engine, side):
    return [order for order in engine.pending() if order.side == side]


def _agree(engine, broker):
    """The ledger and Alpaca hold the same shares, and no sold-out buy went negative."""
    assert engine.audit_positions().matched
    assert engine.ledger.owned("ABC") == broker.holdings.get("ABC", Decimal(0))
    assert all(left >= 0 for lot in engine.ledger.lots() for left in lot.entry_remaining.values())


def test_a_buy_goes_out_under_a_resting_sell_after_the_market_drops(system):
    """The guru sold at $54.20; the copy rests at its $53.66 floor as the market falls. The guru
    buys again at $53: the buy can't trade with the sell, so it goes out instead of waiting
    behind a sell that may never fill."""
    engine, broker, _ = system
    deliver(engine, event(price="54.20"))
    broker.auto_fill = False
    at = NOW + dt.timedelta(minutes=1)
    deliver(engine, event("sell", "close", "54.20", "54.20", timestamp=at), at)
    [sell] = _open(engine, "sell")
    assert sell.limit_price == Decimal("53.66")

    later = NOW + dt.timedelta(minutes=5)
    deliver(engine, event("rebuy", price="53", timestamp=later), later)

    [buy] = _open(engine, "buy")
    assert buy.limit_price == Decimal("53")
    assert isinstance(_part(engine, "rebuy"), OrderLinked)
    assert broker.orders[sell.client_id]["status"] == "new", "the resting sell was disturbed"


def test_a_buy_at_or_above_a_resting_sell_waits_and_ages_out_as_a_buy(system):
    """A buy at $53.66 against a sell resting at $53.66 would trade with it, which Alpaca refuses
    as a possible wash trade: the buy waits, and when the sell never fills, it ends as too old."""
    engine, broker, _ = system
    deliver(engine, event(price="54.20"))
    broker.auto_fill = False
    at = NOW + dt.timedelta(minutes=1)
    deliver(engine, event("sell", "close", "54.20", "54.20", timestamp=at), at)

    later = NOW + dt.timedelta(minutes=2)
    deliver(engine, event("rebuy", price="53.66", timestamp=later), later)
    assert _open(engine, "buy") == []
    assert isinstance(_part(engine, "rebuy"), Pending)

    engine.process(later + dt.timedelta(seconds=601))
    assert _part(engine, "rebuy") == Skipped(reason="stale")
    assert _open(engine, "sell"), "the sell stops resting only when it fills"


def test_a_later_sell_leaves_an_earlier_open_sell_working(system):
    """ "Sell half" rests at its floor, then "sell half of the rest": the second sells a quarter
    of the position at once, the first keeps working, and once both fill one share is left."""
    engine, broker = _resting(system)
    deliver(engine, event("2", "reduce", "27", "25"))
    [first] = engine.pending()
    assert (first.side, first.qty) == ("sell", 2)

    later = NOW + dt.timedelta(seconds=30)
    deliver(engine, event("3", "reduce", "28", "25", timestamp=later), later)

    [_, second] = _open(engine, "sell")
    assert second.qty == 1
    assert broker.orders[first.client_id]["status"] == "new", "the earlier sell was cancelled"

    broker.fill(first.client_id, "2")
    broker.fill(second.client_id, "1")
    engine.reconcile(later)
    assert broker.holdings["ABC"] == 1
    _agree(engine, broker)


def test_selling_everything_again_while_the_first_sale_rests_is_already_selling(system):
    engine, _ = _resting(system)
    deliver(engine, event("2", "close", "27", "25"))
    [first] = _open(engine, "sell")
    assert first.qty == 4

    later = NOW + dt.timedelta(seconds=30)
    deliver(engine, event("3", "close", "28", "25", timestamp=later), later)

    assert _part(engine, "3") == Skipped(reason="already_selling")
    assert _open(engine, "sell") == [first]


def test_half_then_everything_sells_exactly_what_is_held(system):
    """ "Sell half" rests, then "sell the rest": the second sells the other two shares, and once
    both fill Alpaca and the ledger both hold none, with nothing oversold."""
    engine, broker = _resting(system)
    deliver(engine, event("2", "reduce", "27", "25"))
    later = NOW + dt.timedelta(seconds=30)
    deliver(engine, event("3", "close", "28", "25", timestamp=later), later)

    first, second = _open(engine, "sell")
    assert (first.qty, second.qty) == (2, 2)
    broker.fill(second.client_id, "2")
    engine.reconcile(later)
    broker.fill(first.client_id, "2")
    engine.reconcile(later)

    assert broker.holdings["ABC"] == 0
    _agree(engine, broker)


def test_a_sell_of_every_buy_waits_for_an_open_sell_of_one_of_them(system):
    """ "Sell the $25 buy" rests, then "sell everything": the lot splits a fill across every buy
    a sell names, so sending the second now could take shares of the $25 buy the first still
    needs. It waits for the first, then sells the $30 buy, and nothing is oversold."""
    engine, broker, _ = system
    deliver(engine, event())
    at = NOW + dt.timedelta(minutes=1)
    deliver(engine, event("2", price="30", timestamp=at), at)
    held = broker.holdings["ABC"]
    broker.auto_fill = False

    later = NOW + dt.timedelta(minutes=2)
    deliver(engine, event("3", "close", "31", "25", timestamp=later), later)
    [first] = _open(engine, "sell")
    assert first.qty == 4

    deliver(engine, event("4", "close", "32", None, timestamp=later), later)
    assert isinstance(_part(engine, "4"), Pending)
    assert _open(engine, "sell") == [first]

    broker.fill(first.client_id, "4")
    engine.reconcile(later)
    engine.process(later)
    [second] = _open(engine, "sell")
    assert second.qty == held - 4
    broker.fill(second.client_id, str(second.qty))
    engine.reconcile(later)

    assert broker.holdings["ABC"] == 0
    _agree(engine, broker)


def test_a_sell_cancels_the_open_buy_it_would_have_sold_then_sells_the_rest(system):
    """The guru buys more at $25 and sells the $25 buys before the copy's buy fills: the open
    buy is cancelled, and the sell goes out once Alpaca confirms it."""
    engine, broker = _resting(system)
    # Past the re-post window, so the second $25 buy is a call of its own.
    later = NOW + dt.timedelta(minutes=11)
    deliver(engine, event("2", price="25", timestamp=later), later)
    [buy] = _open(engine, "buy")

    deliver(engine, event("3", "close", "27", "25", timestamp=later), later)
    assert broker.orders[buy.client_id]["status"] == "canceled"
    assert isinstance(_part(engine, "3"), Pending)

    engine.reconcile(later)
    engine.process(later)
    [sell] = _open(engine, "sell")
    assert sell.qty == 4
    assert engine.ledger.order(buy.client_id).status is OrderStatus.CANCELED


def test_a_sell_of_one_buy_leaves_an_open_buy_at_another_price_working(system):
    """ "Sell the $25 buy" while a new buy at $26 is still open: the new buy is a separate call,
    so it stays open, and the sell, whose $29.70 floor is above it, goes out beside it."""
    engine, broker = _resting(system)
    later = NOW + dt.timedelta(minutes=1)
    deliver(engine, event("2", price="26", timestamp=later), later)
    [buy] = _open(engine, "buy")

    deliver(engine, event("3", "close", "30", "25", timestamp=later), later)

    assert broker.orders[buy.client_id]["status"] == "new", "the unrelated buy was cancelled"
    [sell] = _open(engine, "sell")
    assert (sell.qty, sell.limit_price) == (4, Decimal("29.70"))


def test_a_sell_at_or_under_an_open_buy_waits_for_it(system):
    """ "Sell the $25 buy" at $27 while a new buy at $30 is open: the $26.73 floor would trade
    with the $30 buy, so the sell waits, leaving the buy alone, until the buy times out."""
    engine, broker = _resting(system)
    later = NOW + dt.timedelta(minutes=1)
    deliver(engine, event("2", price="30", timestamp=later), later)
    [buy] = _open(engine, "buy")

    deliver(engine, event("3", "close", "27", "25", timestamp=later), later)
    assert broker.orders[buy.client_id]["status"] == "new", "the unrelated buy was cancelled"
    assert _open(engine, "sell") == []
    assert isinstance(_part(engine, "3"), Pending)

    timed_out = later + dt.timedelta(seconds=engine.config.order_timeout_seconds + 1)
    engine.reconcile(timed_out)
    engine.reconcile(timed_out)
    engine.process(timed_out)
    [sell] = _open(engine, "sell")
    assert (sell.qty, sell.limit_price) == (4, Decimal("26.73"))


def test_a_post_waits_for_a_resting_sells_fill_to_be_booked(system):
    """The resting sell fills at Alpaca a moment before the next post, before CopyTrading's sync
    has booked it: the counts differ only by that open order, so the post waits for the sync
    instead of being skipped as a holdings mismatch."""
    engine, broker, _ = system
    deliver(engine, event(price="54.20"))
    broker.auto_fill = False
    at = NOW + dt.timedelta(minutes=1)
    deliver(engine, event("sell", "close", "54.20", "54.20", timestamp=at), at)
    [sell] = _open(engine, "sell")
    broker.fill(sell.client_id, str(sell.qty))

    later = NOW + dt.timedelta(minutes=5)
    deliver(engine, event("rebuy", price="53", timestamp=later), later)
    assert isinstance(_part(engine, "rebuy"), Pending)

    engine.reconcile(later)
    engine.process(later)
    assert isinstance(_part(engine, "rebuy"), OrderLinked)
