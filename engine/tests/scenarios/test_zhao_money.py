"""Money runs out and comes back: once the cash is spent no buy reaches the broker, and selling
frees it for the next one."""

from decimal import Decimal

from .rig import Account, Rig, orders, outcomes
from .zhao import buy, close, trim


async def test_when_the_cash_is_spent_the_next_buy_never_reaches_the_broker(tmp_path):
    prices = {"NVDA": "125", "AMD": "100", "TSLA": "250"}
    async with Rig(tmp_path, {"paper": Account(cash="1000")}, prices) as rig:
        broker = rig.brokers["paper"]
        rig.reader.expect("买入 NVDA 125", buy("NVDA", "125"))
        rig.reader.expect("买入 AMD 100", buy("AMD", "100"))
        rig.reader.expect("买入 TSLA 250", buy("TSLA", "250"))

        first = await rig.post("买入 NVDA 125")
        second = await rig.post("买入 AMD 100")
        assert outcomes(first, "paper") == outcomes(second, "paper") == ("order_linked",)
        assert broker.cash == Decimal("0.00")

        third = await rig.post("买入 TSLA 250")
        assert outcomes(third, "paper") == ("insufficient_cash",)
        assert orders(third, "paper") == ()
        assert len(broker.submitted("buy")) == 2
        assert broker.refused == []


async def test_a_buy_bigger_than_what_is_left_is_skipped_not_shrunk(tmp_path):
    async with Rig(tmp_path, {"paper": Account(cash="700")}, {"NVDA": "125", "AMD": "100"}) as rig:
        rig.reader.expect("买入 NVDA 125", buy("NVDA", "125"))
        rig.reader.expect("买入 AMD 100", buy("AMD", "100"))

        await rig.post("买入 NVDA 125")
        assert rig.brokers["paper"].cash == Decimal("200.00")

        again = await rig.post("买入 AMD 100")
        assert outcomes(again, "paper") == ("insufficient_cash",)
        assert rig.brokers["paper"].holdings.get("AMD", 0) == 0


async def test_selling_frees_the_cash_and_the_next_buy_fills(tmp_path):
    async with Rig(tmp_path, {"paper": Account(cash="500")}, {"NVDA": "125", "AMD": "100"}) as rig:
        broker = rig.brokers["paper"]
        rig.reader.expect("买入 NVDA 125", buy("NVDA", "125"))
        rig.reader.expect("买入 AMD 100", buy("AMD", "100"))
        rig.reader.expect(
            "NVDA 125买的 140 清仓", close("NVDA", "140", bought_at="125", said="清仓")
        )

        await rig.post("买入 NVDA 125")
        blocked = await rig.post("买入 AMD 100")
        assert outcomes(blocked, "paper") == ("insufficient_cash",)

        broker.move("NVDA", "140")
        sold = await rig.post("NVDA 125买的 140 清仓")
        assert outcomes(sold, "paper") == ("order_linked",)
        [sale] = orders(sold, "paper")
        assert (sale.side, sale.status, sale.filled_quantity) == ("sell", "filled", 4)
        assert broker.cash == Decimal("560.00")
        assert await rig.lots("paper", "NVDA") == ()

        broker.move("AMD", "125")
        rig.reader.expect("现在买入 AMD 125", buy("AMD", "125", said="买入"))
        bought = await rig.post("现在买入 AMD 125")
        assert outcomes(bought, "paper") == ("order_linked",)
        assert broker.cash == Decimal("60.00")
        [lot] = await rig.lots("paper", "AMD")
        assert lot.remaining_qty == 4


async def test_trimming_half_returns_half_the_cash_and_keeps_half_the_lot(tmp_path):
    async with Rig(tmp_path, {"paper": Account(cash="500")}, {"NVDA": "125"}) as rig:
        broker = rig.brokers["paper"]
        rig.reader.expect("买入 NVDA 125", buy("NVDA", "125"))
        rig.reader.expect(
            "NVDA 125的仓位 卖出一半 150",
            trim("NVDA", "150", bought_at="125", fraction="0.5", fraction_said="一半"),
        )
        await rig.post("买入 NVDA 125")
        broker.move("NVDA", "150")

        trimmed = await rig.post("NVDA 125的仓位 卖出一半 150")
        assert outcomes(trimmed, "paper") == ("order_linked",)
        assert broker.holdings["NVDA"] == 2
        assert broker.cash == Decimal("300.00")
        [lot] = await rig.lots("paper", "NVDA")
        assert (lot.original_qty, lot.remaining_qty) == (4, 2)
