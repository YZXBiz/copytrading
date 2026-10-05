"""Zhao buys: the order fills, cash goes down, and the shares are a lot that names his post."""

from decimal import Decimal

from .rig import Account, Rig, orders, outcomes
from .zhao import GURU_ID, buy


async def test_a_buy_fills_and_becomes_a_lot_tied_to_the_post(tmp_path):
    async with Rig(tmp_path, {"paper": Account(cash="10000")}, {"NVDA": "125"}) as rig:
        rig.reader.expect("买入 NVDA 125", buy("NVDA", "125"))
        activity = await rig.post("买入 NVDA 125")

        assert outcomes(activity, "paper") == ("order_linked",)
        [order] = orders(activity, "paper")
        assert (order.side, order.status, order.filled_quantity) == ("buy", "filled", Decimal(4))
        assert rig.brokers["paper"].cash == Decimal("9500.00")
        [lot] = await rig.lots("paper", "NVDA")
        assert (lot.remaining_qty, lot.average_price, lot.guru_id) == (4, 125, GURU_ID)
        assert lot.source_id == activity.source_ids[0]
