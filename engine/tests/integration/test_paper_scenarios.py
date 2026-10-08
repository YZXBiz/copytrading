"""Opt-in live scenarios: every rule a copied call meets, against DeepSeek and Alpaca paper.

Each scenario replays a guru's posts through the real pipeline and checks what reached the paper
account. They run in any session the broker offers (overnight is on), take a minute or two each,
and leave the account as they found it. Run with the keys set:

    uv run --directory engine pytest tests/integration/test_paper_scenarios.py -p no:randomly
"""

import asyncio
import datetime as dt
import time
from decimal import ROUND_DOWN, ROUND_UP, Decimal

import pytest
import pytest_asyncio

from copytrading_engine.execution.adapters.alpaca.broker import quote_feed

from .paper import (
    CENT,
    LIVE,
    LIVE_REASON,
    Post,
    Rig,
    broker,
    destination_of,
    filled,
    flatten,
    guru_price,
    guru_sell_price,
    open_orders,
    placed,
    quote,
    settled,
    total_exposure,
)

pytestmark = [
    pytest.mark.skipif(not LIVE, reason=LIVE_REASON),
    # One loop for the module, as in the app: an account that opens after Start gave up on it is
    # closed by that loop instead of keeping the broker account's lock for the next scenario.
    pytest.mark.asyncio(loop_scope="module"),
]

SYMBOL = "F"
OTHER = "SOFI"


@pytest_asyncio.fixture(autouse=True, loop_scope="module")
async def _clean_account():
    """No open orders and no shares of the scenario stocks before each scenario, after a pause
    that keeps the run inside Alpaca's per-minute request limit."""
    await asyncio.sleep(15)
    await flatten((SYMBOL, OTHER))


# Traded on Alpaca but not on its overnight venue.
DAY_ONLY = "TCEHY"


def _overnight() -> bool:
    return quote_feed(dt.datetime.now(dt.UTC)) == "overnight"


def _notional(order) -> Decimal:
    return order.quantity * order.limit_price


def _one(result):
    """The single order a post placed, or a failure that says what became of the post."""
    activity, orders = result
    assert len(orders) == 1, f"expected one order: {activity}"
    return orders[0]


def _outcomes(activity) -> tuple[str, ...]:
    return destination_of(activity).instruction_outcomes


async def _no_open_orders(symbol: str) -> None:
    # Give the engine a few cycles to prove nothing slips out later.
    await asyncio.sleep(5)
    assert await open_orders(symbol) == [], f"an order for {symbol} reached Alpaca"


# Buying


async def test_a_full_position_buy_fills_at_most_one_percent_above_the_guru(tmp_path):
    price = await guru_price(SYMBOL)
    async with Rig(tmp_path, (Post(f"Bought {SYMBOL} at {price}"),)) as rig:
        order = _one(await rig.post(0, until=filled))
        assert (order.symbol, order.side, order.status) == (SYMBOL, "buy", "filled"), order
        assert order.limit_price == (price * Decimal("1.01")).quantize(CENT, ROUND_DOWN)
        assert order.budget_usd == Decimal("40")
        assert _notional(order) <= Decimal("40")
        assert order.average_fill_price <= order.limit_price
        assert await rig.owned(SYMBOL) == order.filled_quantity


async def test_partial_buys_join_one_lot_and_partial_sells_trim_it(tmp_path):
    price, sale = await guru_price(SYMBOL), await guru_sell_price(SYMBOL)
    posts = (
        Post(f"Starter: bought 1/4 position {SYMBOL} at {price}"),
        # At another price: the same call within ten minutes is the guru re-posting it.
        Post(f"Adding another 1/4 position {SYMBOL} at {price + Decimal('0.02')}"),
        Post(f"Sold half of my {SYMBOL} at {sale}"),
        Post(f"Out of the rest of {SYMBOL} at {sale}"),
    )
    async with Rig(tmp_path, posts) as rig:
        first = _one(await rig.post(0, until=filled))
        assert first.budget_usd == Decimal("10"), first
        second = _one(await rig.post(1, until=filled))
        assert second.budget_usd == Decimal("10"), second
        account = await rig.account()
        [position] = [p for p in account.positions if p.symbol == SYMBOL]
        assert len(position.lots) == 1, f"an add must join the open lot: {position.lots}"
        held = position.owned_qty
        assert held == first.filled_quantity + second.filled_quantity

        half = _one(await rig.post(2, until=filled))
        assert half.side == "sell"
        assert half.limit_price == (sale * Decimal("0.99")).quantize(CENT, ROUND_UP)
        # Half, rounded down to the millionth of a share Alpaca takes: never more than half.
        assert half.quantity == (held / 2).quantize(Decimal("0.000001"), ROUND_DOWN), (half, held)
        assert await rig.owned(SYMBOL) == held - half.filled_quantity

        rest = _one(await rig.post(3, until=filled))
        assert rest.side == "sell"
        assert rest.quantity == held - half.filled_quantity
        assert await rig.owned(SYMBOL) == 0


async def test_the_maximum_per_order_trims_a_large_call(tmp_path):
    price = await guru_price(SYMBOL)
    async with Rig(
        tmp_path, (Post(f"Bought {SYMBOL} at {price}"),), policy={"max_order_usd": "15"}
    ) as rig:
        order = _one(await rig.post(0, until=placed))
        assert (order.requested_usd, order.budget_usd) == (Decimal("40"), Decimal("15")), order
        assert _notional(order) <= Decimal("15")


async def test_the_guru_buying_far_below_the_market_rests_then_times_out(tmp_path):
    bid, _ = await quote(SYMBOL)
    low = (bid * Decimal("0.8")).quantize(CENT)
    async with Rig(
        tmp_path,
        (Post(f"Bought {SYMBOL} at {low}"),),
        policy={"order_timeout_seconds": 15},
    ) as rig:
        order = _one(await rig.post(0, until=placed))
        assert order.limit_price < bid, "the order must rest below the market"
        order = _one(await rig.wait(0, until=settled, seconds=60))
        assert order.status in {"canceled", "expired"}, order
        assert order.filled_quantity == 0
    assert await open_orders(SYMBOL) == []


# Limits that stop a buy


async def test_the_maximum_per_stock_stops_a_second_full_buy(tmp_path):
    price = await guru_price(SYMBOL)
    posts = (
        Post(f"Bought {SYMBOL} at {price}"),
        Post(f"Bought more {SYMBOL} here at {price + Decimal('0.05')}"),
    )
    async with Rig(tmp_path, posts) as rig:
        bought = _one(await rig.post(0, until=filled))
        activity, orders = await rig.post(1)
        assert _outcomes(activity) == ("symbol_exposure_cap",), activity
        assert [order.client_id for order in orders] == [], orders
        [hit] = destination_of(activity).limits_hit
        assert (hit.scope, hit.limit) == ("symbol", Decimal("40")), hit
        assert await rig.owned(SYMBOL) == bought.filled_quantity


async def test_the_account_total_stops_a_buy(tmp_path):
    ceiling = (await total_exposure() + 5).quantize(CENT)
    price = await guru_price(SYMBOL)
    async with Rig(
        tmp_path, (Post(f"Bought {SYMBOL} at {price}"),), policy={"max_total_usd": str(ceiling)}
    ) as rig:
        activity, orders = await rig.post(0)
        assert _outcomes(activity) == ("total_exposure_cap",), activity
        assert orders == []
        await _no_open_orders(SYMBOL)


async def test_the_daily_entry_count_stops_the_second_buy(tmp_path):
    first, second = await guru_price(SYMBOL), await guru_price(OTHER)
    posts = (Post(f"Bought {SYMBOL} at {first}"), Post(f"Bought {OTHER} at {second}"))
    async with Rig(tmp_path, posts, policy={"max_entries_per_day": 1}) as rig:
        await rig.post(0, until=filled)
        activity, orders = await rig.post(1)
        assert _outcomes(activity) == ("daily_entry_cap",), activity
        assert orders == []
        await _no_open_orders(OTHER)


async def test_a_buy_larger_than_the_cash_is_refused(tmp_path):
    price = await guru_price(SYMBOL)
    huge = "50000000"
    async with Rig(
        tmp_path,
        (Post(f"Bought {SYMBOL} at {price}"),),
        policy={"max_order_usd": huge, "max_symbol_usd": huge, "max_total_usd": "500000000"},
    ) as rig:
        activity, orders = await rig.post(0)
        assert _outcomes(activity) == ("insufficient_cash",), activity
        assert orders == []
        await _no_open_orders(SYMBOL)


async def _outside_order(symbol: str) -> str:
    """A resting buy placed on Alpaca directly, far under the market; returns its broker id."""
    bid, _ = await quote(symbol)
    placed_outside = await broker(
        "POST",
        "/orders",
        json={
            "symbol": symbol,
            "qty": "1",
            "side": "buy",
            "type": "limit",
            "limit_price": str((bid * Decimal("0.5")).quantize(CENT)),
            "time_in_force": "day",
            "extended_hours": True,
        },
    )
    assert placed_outside.status_code == 200, placed_outside.text
    return placed_outside.json()["id"]


async def _cancel(order_id: str) -> None:
    """Cancel an outside order and wait until Alpaca no longer lists it as open."""
    await broker("DELETE", f"/orders/{order_id}")
    for _ in range(20):
        if (await broker("GET", f"/orders/{order_id}")).json()["status"] == "canceled":
            return
        await asyncio.sleep(1)
    raise AssertionError("the outside order was not canceled")


async def test_an_order_placed_outside_copytrading_holds_the_first_connection(tmp_path):
    outside = await _outside_order(OTHER)
    try:
        async with Rig(tmp_path, (Post("Morning all"),), resume=False) as rig:
            for _ in range(30):
                if rig.runtime.status().error_code:
                    break
                await asyncio.sleep(1)
            # Copying waits and says why, so the owner knows to settle that order first.
            assert rig.runtime.status().error_code == "outside_open_orders", rig.runtime.status()
            assert (await rig.account()).readiness == "outside_open_orders"
    finally:
        await _cancel(outside)


async def test_an_order_placed_outside_while_copying_holds_new_buys(tmp_path):
    price = await guru_price(SYMBOL)
    async with Rig(tmp_path, (Post(f"Bought {SYMBOL} at {price}"),)) as rig:
        outside = await _outside_order(OTHER)
        try:
            # The buy waits, unsent, while an order the app did not place is open; the account
            # says why.
            activity, orders = await rig.post(0, until=lambda *_: False, seconds=20, must=False)
            assert orders == [], orders
            assert _outcomes(activity) in {("pending",), ("unresolved_account_order",)}, activity
            account = await rig.account()
            assert account.account_activity_reason == "unresolved_account_order", account
        finally:
            await _cancel(outside)
    await _no_open_orders(SYMBOL)


async def test_an_account_with_entries_off_copies_no_buy(tmp_path):
    price = await guru_price(SYMBOL)
    async with Rig(tmp_path, (Post(f"Bought {SYMBOL} at {price}"),), resume=False) as rig:
        activity, orders = await rig.post(0)
        assert _outcomes(activity) == ("account_disabled",), activity
        assert orders == []
        await _no_open_orders(SYMBOL)


async def test_an_account_that_approves_orders_holds_the_buy(tmp_path):
    price = await guru_price(SYMBOL)
    async with Rig(
        tmp_path, (Post(f"Bought {SYMBOL} at {price}"),), policy={"approve_orders": True}
    ) as rig:
        activity, orders = await rig.post(0)
        assert _outcomes(activity) == ("approval_required",), activity
        assert orders == []
        await _no_open_orders(SYMBOL)


# Sells


async def test_a_sell_with_nothing_bought_sends_nothing(tmp_path):
    price = await guru_price(SYMBOL)
    async with Rig(tmp_path, (Post(f"Sold all my {SYMBOL} at {price}"),)) as rig:
        activity, orders = await rig.post(0)
        assert activity.decision in {"trade", "ignore", "review"}
        assert orders == [], f"a sell without a lot reached Alpaca: {orders}"
        if activity.decision == "trade":
            assert set(_outcomes(activity)) <= {"lot_unavailable", "missing_or_ambiguous_lot"}
        await _no_open_orders(SYMBOL)


async def test_exits_not_copied_keep_the_shares(tmp_path):
    price = await guru_price(SYMBOL)
    posts = (Post(f"Bought {SYMBOL} at {price}"), Post(f"Sold all {SYMBOL} at {price}"))
    async with Rig(tmp_path, posts, policy={"copy_exits": False}) as rig:
        bought = _one(await rig.post(0, until=filled))
        activity, orders = await rig.post(1)
        assert _outcomes(activity) == ("exits_disabled",), activity
        assert orders == []
        assert await rig.owned(SYMBOL) == bought.filled_quantity


# Posts the engine must not trade


async def test_chatter_is_read_as_talk(tmp_path):
    posts = (Post(f"Watching {SYMBOL} into earnings, no position yet. Good morning all!"),)
    async with Rig(tmp_path, posts) as rig:
        activity, orders = await rig.post(0)
        assert activity.decision == "ignore", activity
        assert orders == []


async def test_a_post_read_too_late_is_not_traded(tmp_path):
    price = await guru_price(SYMBOL)
    posts = (Post(f"Bought {SYMBOL} at {price}", age=dt.timedelta(minutes=10)),)
    async with Rig(tmp_path, posts) as rig:
        activity, orders = await rig.post(0)
        assert orders == [], f"a ten-minute-old call was traded: {orders}"
        # Read too late to trust, so it waits for the owner instead of trading.
        assert destination_of(activity).status == "review_required", activity
        await _no_open_orders(SYMBOL)


async def test_a_ticker_that_does_not_exist_is_refused_and_the_engine_keeps_going(tmp_path):
    price = await guru_price(SYMBOL)
    posts = (Post("Bought ZZZZQ at 4.20"), Post(f"Bought {SYMBOL} at {price}"))
    async with Rig(tmp_path, posts) as rig:
        unknown, orders = await rig.post(0)
        assert orders == [], unknown
        order = _one(await rig.post(1, until=placed))
        assert order.symbol == SYMBOL
        assert rig.runtime.status().accounts, "the account stopped after an unknown ticker"


async def test_a_post_delivered_twice_trades_once(tmp_path):
    price = await guru_price(SYMBOL)
    text = f"Bought {SYMBOL} at {price}"
    at = dt.datetime.now(dt.UTC)
    # One Discord message, new on every run: its id names the order sent to Alpaca.
    message_id = str(time.time_ns())
    posts = (Post(text, message_id=message_id, at=at), Post(text, message_id=message_id, at=at))
    async with Rig(tmp_path, posts) as rig:
        await rig.post(0, until=placed)
        await rig.post(1, until=lambda *_: False, seconds=10, must=False)
        broker_orders = [
            order
            for order in (
                await broker("GET", "/orders", params={"status": "all", "limit": 20})
            ).json()
            if order["client_order_id"] in rig.placed
        ]
        assert len(broker_orders) == 1, broker_orders


# Sessions


async def test_overnight_trading_off_holds_a_buy_overnight(tmp_path):
    if not _overnight():
        pytest.skip("runs only during the overnight session, 20:00 to 4:00 New York time")
    price = await guru_price(SYMBOL)
    async with Rig(
        tmp_path, (Post(f"Bought {SYMBOL} at {price}"),), policy={"overnight": False}
    ) as rig:
        activity, orders = await rig.post(0)
        assert _outcomes(activity) == ("outside_session",), activity
        assert orders == []


async def test_a_stock_the_overnight_venue_does_not_list_is_held_overnight(tmp_path):
    if not _overnight():
        pytest.skip("runs only during the overnight session, 20:00 to 4:00 New York time")
    async with Rig(tmp_path, (Post(f"Bought {DAY_ONLY} at 60.00"),)) as rig:
        activity, orders = await rig.post(0)
        assert _outcomes(activity) == ("overnight_not_supported",), activity
        assert orders == []


# Recovery and load


async def test_a_restart_keeps_the_lot_and_the_guru_sell_closes_it(tmp_path):
    price = await guru_price(SYMBOL)
    async with Rig(tmp_path, (Post(f"Bought {SYMBOL} at {price}"),)) as first:
        bought = _one(await first.post(0, until=filled))
        first.placed.clear()  # the second run owns the shares now
    async with Rig(
        tmp_path, (Post(f"Sold all {SYMBOL} at {await guru_sell_price(SYMBOL)}"),)
    ) as second:
        assert await second.owned(SYMBOL) == bought.filled_quantity
        sold = _one(await second.post(0, until=filled))
        assert (sold.side, sold.quantity) == ("sell", bought.filled_quantity)
        assert await second.owned(SYMBOL) == 0


async def test_a_burst_of_posts_settles_every_one(tmp_path):
    first, second = await guru_price(SYMBOL), await guru_price(OTHER)
    posts = (
        Post(f"Bought {SYMBOL} at {first}"),
        Post("Morning all, choppy open today"),
        Post(f"Bought {OTHER} at {second}"),
        Post("Bought QQQQZ at 3.10"),
    )
    async with Rig(tmp_path, posts) as rig:
        for gate in rig.gates:
            gate.set()
        trades = [await rig.wait(index, until=placed) for index in (0, 2)]
        talk, _ = await rig.wait(1, until=lambda activity, _: bool(activity and activity.decision))
        unknown, unknown_orders = await rig.wait(
            3, until=lambda activity, _: bool(activity and activity.decision)
        )
        assert {order.symbol for _, orders in trades for order in orders if order.broker_id} == {
            SYMBOL,
            OTHER,
        }, trades
        assert talk.decision == "ignore", talk
        assert unknown is not None, "the unknown ticker was never read"
        assert unknown_orders == [], unknown
