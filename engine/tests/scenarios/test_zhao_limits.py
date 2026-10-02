"""The limits the owner sets hold however Zhao posts: per order, per symbol, in total, per day,
and while entries are paused."""

from decimal import Decimal

from .rig import Account, Rig, orders, outcomes
from .zhao import buy, close


async def test_the_order_cap_trims_a_buy_to_its_size(tmp_path):
    accounts = {"paper": Account(cash="10000", limits={"max_order_usd": "250"})}
    async with Rig(tmp_path, accounts, {"NVDA": "125"}) as rig:
        rig.reader.expect("买入 NVDA 125", buy("NVDA", "125"))
        activity = await rig.post("买入 NVDA 125")
        [order] = orders(activity, "paper")
        assert order.quantity == 2
        assert rig.brokers["paper"].cash == Decimal("9750.00")


async def test_the_symbol_cap_stops_a_second_buy_of_the_same_stock_only(tmp_path):
    accounts = {"paper": Account(cash="10000", limits={"max_symbol_usd": "800"})}
    async with Rig(tmp_path, accounts, {"NVDA": "125", "AMD": "100"}) as rig:
        broker = rig.brokers["paper"]
        rig.reader.expect("买入 NVDA 125", buy("NVDA", "125"))
        rig.reader.expect("加仓 NVDA 130", buy("NVDA", "130", said="加仓"))
        rig.reader.expect("买入 AMD 100", buy("AMD", "100"))

        await rig.post("买入 NVDA 125")
        broker.move("NVDA", "130")
        more = await rig.post("加仓 NVDA 130")
        other = await rig.post("买入 AMD 100")

        assert outcomes(more, "paper") == ("symbol_exposure_cap",)
        assert outcomes(other, "paper") == ("order_linked",)


async def test_the_total_cap_stops_buys_across_stocks(tmp_path):
    accounts = {"paper": Account(cash="10000", limits={"max_total_usd": "900"})}
    async with Rig(tmp_path, accounts, {"NVDA": "125", "AMD": "100"}) as rig:
        rig.reader.expect("买入 NVDA 125", buy("NVDA", "125"))
        rig.reader.expect("买入 AMD 100", buy("AMD", "100"))
        await rig.post("买入 NVDA 125")
        second = await rig.post("买入 AMD 100")
        assert outcomes(second, "paper") == ("total_exposure_cap",)


async def test_the_daily_entry_cap_counts_buys_not_sells(tmp_path):
    accounts = {"paper": Account(cash="10000", limits={"max_entries_per_day": 2})}
    prices = {"NVDA": "125", "AMD": "100", "TSLA": "250"}
    async with Rig(tmp_path, accounts, prices) as rig:
        rig.reader.expect("买入 NVDA 125", buy("NVDA", "125"))
        rig.reader.expect("买入 AMD 100", buy("AMD", "100"))
        rig.reader.expect("买入 TSLA 250", buy("TSLA", "250"))
        rig.reader.expect("NVDA 125买的 130 清仓", close("NVDA", "130", bought_at="125"))
        await rig.post("买入 NVDA 125")
        await rig.post("买入 AMD 100")

        third = await rig.post("买入 TSLA 250")
        assert outcomes(third, "paper") == ("daily_entry_cap",)
        rig.brokers["paper"].move("NVDA", "130")
        sold = await rig.post("NVDA 125买的 130 清仓")
        assert outcomes(sold, "paper") == ("order_linked",)


async def test_after_the_daily_loss_cap_buys_stop_but_sells_still_go(tmp_path):
    accounts = {"paper": Account(cash="1000", limits={"daily_loss_cap_usd": "100"})}
    async with Rig(tmp_path, accounts, {"NVDA": "125", "AMD": "100"}) as rig:
        broker = rig.brokers["paper"]
        rig.reader.expect("买入 NVDA 125", buy("NVDA", "125"))
        rig.reader.expect("买入 AMD 100", buy("AMD", "100"))
        rig.reader.expect("NVDA 125买的 95 清仓", close("NVDA", "95", bought_at="125"))
        await rig.post("买入 NVDA 125")

        broker.move("NVDA", "95")  # 4 shares lose $120 against yesterday's close
        blocked = await rig.post("买入 AMD 100")
        assert outcomes(blocked, "paper") == ("daily_loss_cap",)

        sold = await rig.post("NVDA 125买的 95 清仓")
        assert outcomes(sold, "paper") == ("order_linked",)
        assert broker.holdings["NVDA"] == 0


async def test_paused_entries_skip_buys_keep_sells_and_resume(tmp_path):
    async with Rig(tmp_path, {"paper": Account(cash="2000")}, {"NVDA": "125", "AMD": "100"}) as rig:
        broker = rig.brokers["paper"]
        rig.reader.expect("买入 NVDA 125", buy("NVDA", "125"))
        rig.reader.expect("买入 AMD 100", buy("AMD", "100"))
        rig.reader.expect("NVDA 125买的 130 清仓", close("NVDA", "130", bought_at="125"))
        rig.reader.expect("现在买入 AMD 105", buy("AMD", "105"))
        await rig.post("买入 NVDA 125")

        await rig.entries("paper", "pause")
        paused = await rig.post("买入 AMD 100")
        assert outcomes(paused, "paper") == ("account_paused",)
        assert orders(paused, "paper") == ()
        broker.move("NVDA", "130")
        sold = await rig.post("NVDA 125买的 130 清仓")
        assert outcomes(sold, "paper") == ("order_linked",)

        await rig.entries("paper", "resume")
        broker.move("AMD", "105")
        resumed = await rig.post("现在买入 AMD 105")
        assert outcomes(resumed, "paper") == ("order_linked",)


async def test_a_post_that_arrives_late_goes_to_review_and_is_not_traded(tmp_path):
    async with Rig(tmp_path, {"paper": Account(cash="1000")}, {"NVDA": "125"}) as rig:
        rig.reader.expect("买入 NVDA 125", buy("NVDA", "125"))
        late = await rig.post("买入 NVDA 125", age_seconds=600)
        destination = next(d for d in late.destinations if d.account_id == "paper")
        assert destination.status == "review_required"
        assert rig.brokers["paper"].submitted() == []


async def test_a_limit_above_the_market_waits_until_the_price_comes_back(tmp_path):
    async with Rig(tmp_path, {"paper": Account(cash="1000")}, {"NVDA": "131"}) as rig:
        broker = rig.brokers["paper"]
        rig.reader.expect("买入 NVDA 125", buy("NVDA", "125"))
        activity = await rig.post("买入 NVDA 125")
        [order] = orders(activity, "paper")
        assert order.status in {"new", "accepted"}
        assert broker.cash == Decimal("1000")

        assert await rig.lots("paper", "NVDA") == ()

        broker.move("NVDA", "125")
        lots = await rig.until(lambda: rig.lots("paper", "NVDA"), "the late fill to become a lot")
        assert [lot.remaining_qty for lot in lots] == [4]
        assert broker.cash == Decimal("500.00")
