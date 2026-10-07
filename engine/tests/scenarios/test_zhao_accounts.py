"""Several accounts and the owner's own hand: each account decides alone, and a lot the owner
sells from Accounts is gone from what Zhao's later sell can touch."""

from decimal import Decimal

from .rig import Account, Rig, orders, outcomes
from .zhao import buy, close, trim


async def test_an_account_without_cash_never_holds_back_the_others(tmp_path):
    accounts = {"rich": Account(cash="5000"), "poor": Account(cash="100")}
    async with Rig(tmp_path, accounts, {"NVDA": "125"}) as rig:
        rig.reader.expect("买入 NVDA 125", buy("NVDA", "125"))
        activity = await rig.post("买入 NVDA 125")
        assert outcomes(activity, "rich") == ("order_linked",)
        assert outcomes(activity, "poor") == ("insufficient_cash",)
        assert rig.brokers["rich"].holdings["NVDA"] == 4
        assert rig.brokers["poor"].submitted() == []


async def test_each_account_sizes_zhaos_share_from_its_own_full_position(tmp_path):
    accounts = {
        "small": Account(cash="5000", full_position_usd="750"),
        "large": Account(cash="5000", full_position_usd="3000"),
    }
    async with Rig(tmp_path, accounts, {"NVDA": "125"}) as rig:
        text = "买入 NVDA 125 6分之一"
        rig.reader.expect(
            text, buy("NVDA", "125", fraction=str(Decimal(1) / 6), fraction_said="6分之一")
        )
        activity = await rig.post(text)
        assert orders(activity, "small")[0].quantity == 1
        assert orders(activity, "large")[0].quantity == 4


async def test_a_call_with_no_size_buys_the_full_position(tmp_path):
    async with Rig(tmp_path, {"paper": Account(cash="5000")}, {"NVDA": "125"}) as rig:
        rig.reader.expect("买入 NVDA 125", buy("NVDA", "125"))
        activity = await rig.post("买入 NVDA 125")
        assert orders(activity, "paper")[0].quantity == 4


async def test_selling_part_of_a_lot_from_accounts_leaves_the_rest_for_zhao(tmp_path):
    async with Rig(tmp_path, {"paper": Account(cash="1000")}, {"NVDA": "125"}) as rig:
        broker = rig.brokers["paper"]
        rig.reader.expect("买入 NVDA 125", buy("NVDA", "125"))
        rig.reader.expect("NVDA 125买的 140 清仓", close("NVDA", "140", bought_at="125"))
        bought = await rig.post("买入 NVDA 125")
        [lot] = await rig.lots("paper", "NVDA")
        assert lot.source_id == bought.source_ids[0]

        broker.move("NVDA", "130")
        preview, result = await rig.sell_lot("paper", lot.lot_id, "1")
        assert preview.plan is not None
        assert preview.plan.type == "limit"
        assert result.status == "filled"
        [lot] = await rig.lots("paper", "NVDA")
        assert lot.remaining_qty == 3
        assert broker.cash == Decimal("630.00")

        broker.move("NVDA", "140")
        sold = await rig.post("NVDA 125买的 140 清仓")
        [sale] = orders(sold, "paper")
        assert sale.quantity == 3
        assert broker.holdings["NVDA"] == 0
        assert await rig.lots("paper", "NVDA") == ()


async def test_after_the_owner_sells_the_whole_lot_zhaos_sell_finds_nothing(tmp_path):
    async with Rig(tmp_path, {"paper": Account(cash="1000")}, {"NVDA": "125"}) as rig:
        broker = rig.brokers["paper"]
        rig.reader.expect("买入 NVDA 125", buy("NVDA", "125"))
        rig.reader.expect(
            "NVDA 125的仓位 卖出一半 140",
            trim("NVDA", "140", bought_at="125", fraction="0.5", fraction_said="一半"),
        )
        await rig.post("买入 NVDA 125")
        [lot] = await rig.lots("paper", "NVDA")
        _, result = await rig.sell_lot("paper", lot.lot_id, "4")
        assert result.status == "filled"
        sells = len(broker.submitted("sell"))

        broker.move("NVDA", "140")
        late = await rig.post("NVDA 125的仓位 卖出一半 140")
        assert orders(late, "paper") == ()
        assert len(broker.submitted("sell")) == sells
        assert broker.holdings["NVDA"] == 0


async def test_asking_to_sell_more_than_a_lot_holds_sells_only_the_lot(tmp_path):
    async with Rig(tmp_path, {"paper": Account(cash="1000")}, {"NVDA": "125"}) as rig:
        rig.reader.expect("买入 NVDA 125", buy("NVDA", "125"))
        await rig.post("买入 NVDA 125")
        [lot] = await rig.lots("paper", "NVDA")
        preview, result = await rig.sell_lot("paper", lot.lot_id, "10")
        assert preview.plan is not None
        assert preview.plan.qty == 4
        assert result.status == "filled"
        assert rig.brokers["paper"].holdings["NVDA"] == 0
        assert rig.brokers["paper"].refused == []
