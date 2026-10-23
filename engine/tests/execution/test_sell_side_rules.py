"""A sell is not a buy: each side keeps its own price direction, limits, and replace rule."""

import datetime as dt
from decimal import Decimal

from hypothesis import given
from hypothesis import strategies as st

from copytrading_engine.execution.domain.order_lifecycle import OrderStatus
from copytrading_engine.execution.domain.orders import SHARE_STEP, OwnedLot
from copytrading_engine.execution.domain.pricing import EntryPricingPolicy
from copytrading_engine.execution.domain.signals import CopyConfig
from copytrading_engine.shared.signals import StockSignal

from .builders import NOW, deliver, event, receive

prices = st.decimals(min_value=Decimal("0.01"), max_value=Decimal("5000"), places=2)
allowances = st.decimals(min_value=Decimal(0), max_value=Decimal("99"), places=2)


@given(prices, allowances)
def test_a_buy_limit_never_pays_more_than_the_allowance_over_the_guru(price, allowance):
    limit = EntryPricingPolicy(max_above_signal_pct=allowance).limit_price(price)
    assert price <= limit or allowance == 0
    assert limit <= price * (1 + allowance / 100)


@given(prices, allowances)
def test_a_sell_floor_is_never_above_the_price_it_sells_into(price, allowance):
    """A sell limit is a floor: at or under the price, never over it, so a market at that price
    always fills it."""
    floor = EntryPricingPolicy(max_below_signal_pct=allowance).exit_limit_price(price)
    assert floor <= price
    assert floor >= price * (1 - allowance / 100)


def _sell_engine(system):
    engine, broker, _ = system
    deliver(engine, event())
    assert broker.holdings["ABC"] == 4
    broker.auto_fill = False
    return engine, broker


def test_a_later_sell_leaves_an_earlier_open_sell_working(system):
    """ "Sell half", then "sell half of the rest" while the first is still open: both sales
    happen. The second waits for the first instead of cancelling it, which would lose a sale."""
    engine, broker = _sell_engine(system)
    deliver(engine, event("2", "reduce", "27", "25"))
    [first] = engine.pending()
    assert first.side == "sell"
    assert first.qty == 2

    later = NOW + dt.timedelta(seconds=30)
    deliver(engine, event("3", "reduce", "28", "25", timestamp=later), later)
    assert broker.orders[first.client_id]["status"] == "new", "the earlier sell was cancelled"

    broker.fill(first.client_id, "2")
    engine.reconcile(later)
    broker.auto_fill = True
    engine.process(later)
    assert broker.holdings["ABC"] == 1


def test_a_sell_of_one_buy_leaves_an_open_buy_at_another_price_working(system):
    """ "Sell the 25 buy" while a new buy at 30 is still open: the new buy is a separate call, so
    the sell does not cancel it."""
    engine, broker = _sell_engine(system)
    later = NOW + dt.timedelta(minutes=11)
    deliver(engine, event("2", price="30", timestamp=later), later)
    [buy] = engine.pending()
    assert buy.side == "buy"

    deliver(engine, event("3", "close", "27", "25", timestamp=later), later)
    assert broker.orders[buy.client_id]["status"] == "new", "the unrelated buy was cancelled"


def test_a_sell_of_the_whole_position_still_cancels_an_open_buy(system):
    """The guru selling out before the copy's buy fills: the open buy is cancelled."""
    engine, broker = _sell_engine(system)
    later = NOW + dt.timedelta(minutes=11)
    deliver(engine, event("2", price="25", timestamp=later), later)
    [buy] = engine.pending()

    deliver(engine, event("3", "close", "27", None, timestamp=later), later)
    assert broker.orders[buy.client_id]["status"] == "canceled"


def test_buy_limits_never_stop_a_sell(system):
    """Per-stock, total, daily-entry and daily-loss limits are for buys: a sell still goes out
    with every one of them used up."""
    engine, broker, _ = system
    deliver(engine, event())
    engine.config = CopyConfig(
        sources=["discord:demo"],
        max_symbol_usd=Decimal("1"),
        max_total_usd=Decimal("1"),
        max_entries_per_day=1,
        daily_loss_cap_usd=Decimal("1"),
    )
    broker.account_data |= {"equity": "4000", "last_equity": "5000"}
    deliver(engine, event("2", "close", "27", "25"))
    assert broker.holdings["ABC"] == 0


def test_an_operator_halt_stops_buys_but_not_sells(system):
    engine, _, _ = system
    deliver(engine, event())
    later = NOW + dt.timedelta(minutes=11)
    receive(engine, StockSignal.model_validate(event("2", price="25", timestamp=later)), later)
    receive(
        engine, StockSignal.model_validate(event("3", "close", "27", "25", timestamp=later)), later
    )
    engine.process(later, halted=True)
    assert [order.side for order in engine.ledger.orders()] == ["buy", "sell"]
    assert engine.ledger.orders()[-1].status is OrderStatus.FILLED


shares = st.decimals(min_value=Decimal("0.000001"), max_value=Decimal("500"), places=6)


@given(st.lists(shares, min_size=1, max_size=4), st.sampled_from(["0.5", "0.25", "0.333333"]))
def test_selling_part_then_the_rest_of_fractional_buys_leaves_no_dust(buys, fraction):
    """Any split of fractional buys: a partial sell takes no more than they hold and no buy goes
    negative, and selling what is left after it empties the lot exactly."""
    keys = [f"buy-{index}" for index in range(len(buys))]
    total = sum(buys, Decimal(0))
    lot = OwnedLot(
        symbol="ABC",
        entry_price=Decimal("25"),
        source_key="discord:demo",
        original_qty=total,
        remaining_qty=total,
        average_price=Decimal("25"),
        joined_entries=tuple(keys[1:]),
        entry_remaining=dict(zip(keys, buys, strict=True)),
        entry_prices=dict.fromkeys(keys, Decimal("25")),
    )
    part = (total * Decimal(fraction)).quantize(SHARE_STEP, rounding="ROUND_DOWN")
    after = lot.reduced(part)
    assert all(left >= 0 for left in after.entry_remaining.values())
    assert after.remaining_qty == total - part
    emptied = after.reduced(after.remaining_qty)
    assert emptied.remaining_qty == 0
    assert all(left == 0 for left in emptied.entry_remaining.values())


def test_half_then_the_rest_of_an_odd_fractional_buy_sells_every_share(system):
    engine, broker, _ = system
    deliver(engine, event(price="27.13"))
    bought = broker.holdings["ABC"]
    assert bought != bought.to_integral_value()
    deliver(engine, event("2", "reduce", "28", "27.13"))
    assert broker.holdings["ABC"] == bought - (bought / 2).quantize(
        Decimal("0.000001"), "ROUND_DOWN"
    )
    deliver(engine, event("3", "close", "29", "27.13"))
    assert broker.holdings["ABC"] == 0
    assert engine.ledger.owned("ABC") == 0
