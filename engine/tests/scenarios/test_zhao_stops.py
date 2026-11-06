"""Zhao's stops end to end: off by default, a real stop order when the account follows them,
sized to the buy it protects and never to the owner's own shares."""

import datetime as dt
from decimal import Decimal

from .rig import Account, Rig, outcomes
from .zhao import buy, close, stop, trim

BUY_AND_STOP = "买入 SOXL 43.4 止损 38.4"
STOP_ONLY = "SOXL 做个跌破 38.4 的保护"
HALF_SOLD = "SOXL 43.4买的 一半 卖出 45"
ALL_SOLD = "SOXL 43.4买的 清仓 46"
FOLLOWING = {"follow_stops": True}


def stop_outcomes(activity, account: str) -> tuple[str, ...]:
    return next(d for d in activity.destinations if d.account_id == account).stop_outcomes


def resting(broker, *, not_id: str | None = None) -> list[dict]:
    return [
        order
        for order in broker.submitted("sell")
        if order["symbol"] == "SOXL" and order["status"] == "new" and order["id"] != not_id
    ]


async def until_resting(rig, what: str, *, not_id: str | None = None) -> list[dict]:
    async def read():
        return resting(rig.brokers["paper"], not_id=not_id)

    return await rig.until(read, what)


async def place_buy_and_stop(rig, clock) -> dict:
    """Zhao buys and posts the stop on that buy; the stop is placed once the fill has settled."""
    rig.reader.expect(BUY_AND_STOP, buy("SOXL", "43.4"), stop("SOXL", "38.4", alongside=0))
    await rig.post(BUY_AND_STOP, expect_destinations=False)
    clock.shift(dt.timedelta(seconds=31))
    [order] = await until_resting(rig, "the stop to rest")
    return order


async def test_with_the_setting_off_a_stop_is_skipped_and_nothing_rests_at_the_broker(tmp_path):
    async with Rig(tmp_path, {"paper": Account(cash="1000")}, {"SOXL": "43.4"}) as rig:
        rig.reader.expect(BUY_AND_STOP, buy("SOXL", "43.4"), stop("SOXL", "38.4", alongside=0))
        activity = await rig.post(BUY_AND_STOP)
        assert outcomes(activity, "paper") == ("order_linked",)
        assert stop_outcomes(activity, "paper") == ("follow_stops_off",)
        assert rig.brokers["paper"].submitted("sell") == []


async def test_a_stop_beside_a_buy_rests_at_the_broker_for_the_shares_that_filled(tmp_path, clock):
    accounts = {"paper": Account(cash="1000", limits=FOLLOWING)}
    async with Rig(tmp_path, accounts, {"SOXL": "43.4"}) as rig:
        broker = rig.brokers["paper"]
        order = await place_buy_and_stop(rig, clock)
        assert (order["type"], order["stop_price"], order["qty"]) == (
            "stop",
            "38.4",
            str(broker.holdings["SOXL"]),
        )


async def test_a_stop_never_covers_the_owners_own_shares(tmp_path):
    accounts = {"paper": Account(cash="1000", full_position_usd="3000", limits=FOLLOWING)}
    rig = Rig(tmp_path, accounts, {"SOXL": "43.4"})
    rig.brokers["paper"].hold_outside_the_app("SOXL", "10")
    async with rig:
        rig.reader.expect(STOP_ONLY, stop("SOXL", "38.4"))
        await rig.post(STOP_ONLY)
        assert resting(rig.brokers["paper"]) == []  # CopyTrading holds none of the 10 shares


async def test_a_copied_sell_shrinks_the_stop_and_selling_the_rest_ends_it(tmp_path, clock):
    accounts = {"paper": Account(cash="1000", limits=FOLLOWING)}
    async with Rig(tmp_path, accounts, {"SOXL": "43.4"}) as rig:
        broker = rig.brokers["paper"]
        first = await place_buy_and_stop(rig, clock)
        bought = broker.holdings["SOXL"]

        rig.reader.expect(
            HALF_SOLD,
            trim("SOXL", "45", bought_at="43.4", fraction="0.5", fraction_said="一半"),
        )
        broker.move("SOXL", "45")
        await rig.post(HALF_SOLD)
        clock.shift(dt.timedelta(seconds=31))
        [smaller] = await until_resting(rig, "a smaller stop to rest", not_id=first["id"])
        assert Decimal(smaller["qty"]) == broker.holdings["SOXL"] < bought
        assert first["status"] == "canceled"

        rig.reader.expect(ALL_SOLD, close("SOXL", "46", bought_at="43.4"))
        broker.move("SOXL", "46")
        await rig.post(ALL_SOLD)
        clock.shift(dt.timedelta(seconds=31))
        await rig.until(lambda: _nothing_resting(broker), "the last stop to end")
        assert broker.holdings["SOXL"] == 0
        assert smaller["status"] == "canceled"


async def _nothing_resting(broker) -> bool:
    return not resting(broker)


async def test_a_stop_that_fills_closes_the_buy_and_is_recorded_as_a_sell(tmp_path, clock):
    accounts = {"paper": Account(cash="1000", limits=FOLLOWING)}
    async with Rig(tmp_path, accounts, {"SOXL": "43.4"}) as rig:
        broker = rig.brokers["paper"]
        await place_buy_and_stop(rig, clock)

        broker.move("SOXL", "38")  # the price falls through the stop

        async def recorded():
            page = await rig.runtime.operator.source_activity(None, 100)
            return [
                order
                for item in page.items
                for destination in item.destinations
                for order in destination.orders
                if order.side == "sell" and order.status == "filled"
            ]

        [sale] = await rig.until(recorded, "the stop fill to reach the ledger")
        assert (sale.order_type, sale.stop_price) == ("stop", Decimal("38.4"))
        overview = await rig.overview("paper")
        [position] = overview.positions
        assert (position.owned_qty, position.stops, position.lots) == (0, (), ())
