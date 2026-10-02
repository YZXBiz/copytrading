"""Zhao sells: only what the copier bought for his post is sold, never more, never someone
else's shares."""

from decimal import Decimal

from .rig import Account, Rig, orders, outcomes
from .zhao import buy, close


async def test_selling_a_stock_never_bought_sends_nothing(tmp_path):
    async with Rig(tmp_path, {"paper": Account(cash="1000")}, {"TSLA": "250"}) as rig:
        rig.reader.expect("TSLA 200买的 250 清仓", close("TSLA", "250", bought_at="200"))
        activity = await rig.post("TSLA 200买的 250 清仓")
        assert outcomes(activity, "paper") == ("missing_or_ambiguous_lot",)
        assert rig.brokers["paper"].submitted() == []


async def test_shares_held_outside_the_app_are_never_sold(tmp_path):
    rig = Rig(tmp_path, {"paper": Account(cash="1000")}, {"AAPL": "125"})
    broker = rig.brokers["paper"]
    broker.hold_outside_the_app("AAPL", "10")  # bought by hand before CopyTrading started
    async with rig:
        rig.reader.expect("买入 AAPL 125", buy("AAPL", "125"))
        rig.reader.expect("AAPL 125买的 130 清仓", close("AAPL", "130", bought_at="125"))

        bought = await rig.post("买入 AAPL 125")
        assert outcomes(bought, "paper") == ("order_linked",)
        assert broker.holdings["AAPL"] == 14
        broker.move("AAPL", "130")
        sold = await rig.post("AAPL 125买的 130 清仓")

        [sale] = orders(sold, "paper")
        assert sale.quantity == 4
        assert broker.holdings["AAPL"] == 10
        overview = await rig.overview("paper")
        [position] = overview.positions
        assert (position.owned_qty, position.external_qty) == (0, 10)


async def test_shares_that_appear_unexplained_stop_buys_of_that_stock(tmp_path):
    """Shares the app did not buy show up mid-session (bought by hand at the broker): the engine
    will not guess whose they are, so it stops copying buys of that stock until the owner says."""
    async with Rig(tmp_path, {"paper": Account(cash="1000")}, {"AAPL": "125"}) as rig:
        rig.brokers["paper"].hold_outside_the_app("AAPL", "10")
        rig.reader.expect("买入 AAPL 125", buy("AAPL", "125"))
        bought = await rig.post("买入 AAPL 125")
        assert outcomes(bought, "paper") == ("ownership_incident",)
        assert rig.brokers["paper"].submitted() == []
        overview = await rig.overview("paper")
        assert overview.ownership_incidents


async def test_two_buys_are_two_lots_and_a_sell_names_which_one(tmp_path):
    async with Rig(tmp_path, {"paper": Account(cash="2000")}, {"NVDA": "125"}) as rig:
        broker = rig.brokers["paper"]
        rig.reader.expect("买入 NVDA 125", buy("NVDA", "125"))
        rig.reader.expect("加仓 NVDA 100", buy("NVDA", "100", said="加仓"))
        rig.reader.expect("NVDA 100买的 110 清仓", close("NVDA", "110", bought_at="100"))

        await rig.post("买入 NVDA 125")
        broker.move("NVDA", "100")
        await rig.post("加仓 NVDA 100")
        lots = await rig.lots("paper", "NVDA")
        assert sorted((lot.average_price, lot.remaining_qty) for lot in lots) == [
            (100, 5),
            (125, 4),
        ]

        broker.move("NVDA", "110")
        sold = await rig.post("NVDA 100买的 110 清仓")
        [sale] = orders(sold, "paper")
        assert sale.quantity == 5
        [left] = await rig.lots("paper", "NVDA")
        assert (left.average_price, left.remaining_qty) == (125, 4)


async def test_exits_are_skipped_when_the_account_does_not_copy_them(tmp_path):
    accounts = {"paper": Account(cash="1000", limits={"copy_exits": False})}
    async with Rig(tmp_path, accounts, {"NVDA": "125"}) as rig:
        rig.reader.expect("买入 NVDA 125", buy("NVDA", "125"))
        rig.reader.expect("NVDA 125买的 140 清仓", close("NVDA", "140", bought_at="125"))
        await rig.post("买入 NVDA 125")
        rig.brokers["paper"].move("NVDA", "140")

        activity = await rig.post("NVDA 125买的 140 清仓")
        assert outcomes(activity, "paper") == ("exits_disabled",)
        assert rig.brokers["paper"].holdings["NVDA"] == 4
        assert rig.brokers["paper"].cash == Decimal("500.00")
