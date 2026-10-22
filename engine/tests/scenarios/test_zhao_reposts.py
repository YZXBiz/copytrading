"""Reposts and chatter: a repeated alert never buys twice, and talk is never a trade."""

import datetime as dt
from decimal import Decimal

from .rig import Account, Rig, outcomes
from .zhao import buy, trim

# A model can write 1/6 as the ratio "1/6", kept as Decimal(1) / 6, or as the JSON number
# 0.16666666666666666; a re-read of the same post can come back either way.
SIXTH, SIXTH_AS_FLOAT = str(Decimal(1) / 6), "0.16666666666666666"
THIRD, THIRD_AS_FLOAT = str(Decimal(1) / 3), "0.3333333333333333"


async def test_chatter_is_read_but_never_traded(tmp_path):
    async with Rig(tmp_path, {"paper": Account(cash="1000")}, {"NVDA": "125"}) as rig:
        rig.reader.expect("今天大盘不错 大家注意风险")
        activity = await rig.post("今天大盘不错 大家注意风险", expect_destinations=False)
        assert activity.decision == "ignore"
        assert rig.brokers["paper"].submitted() == []


async def test_the_same_alert_reposted_within_ten_minutes_buys_once(tmp_path):
    async with Rig(tmp_path, {"paper": Account(cash="2000")}, {"NVDA": "125"}) as rig:
        rig.reader.expect("买入 NVDA 125", buy("NVDA", "125"))
        first = await rig.post("买入 NVDA 125")
        again = await rig.post("买入 NVDA 125")
        assert outcomes(first, "paper") == ("order_linked",)
        assert outcomes(again, "paper") == ("duplicate",)
        assert len(rig.brokers["paper"].submitted("buy")) == 1


async def test_a_repeat_of_a_skipped_alert_inside_ten_minutes_is_still_a_repost(tmp_path):
    """Known behavior: the repost guard does not ask whether the first alert traded."""
    async with Rig(tmp_path, {"paper": Account(cash="100")}, {"NVDA": "125"}) as rig:
        rig.reader.expect("买入 NVDA 125", buy("NVDA", "125"))
        first = await rig.post("买入 NVDA 125")
        assert outcomes(first, "paper") == ("insufficient_cash",)
        rig.brokers["paper"].cash += 1000
        again = await rig.post("买入 NVDA 125")
        assert outcomes(again, "paper") == ("duplicate",)


async def test_the_same_alert_nine_minutes_later_is_still_a_repost(tmp_path, clock):
    async with Rig(tmp_path, {"paper": Account(cash="2000")}, {"NVDA": "125"}) as rig:
        rig.reader.expect("买入 NVDA 125", buy("NVDA", "125"))
        await rig.post("买入 NVDA 125")
        clock.shift(dt.timedelta(minutes=9))
        later = await rig.post("买入 NVDA 125")
        assert outcomes(later, "paper") == ("duplicate",)
        assert len(rig.brokers["paper"].submitted("buy")) == 1


async def test_the_same_alert_after_ten_minutes_is_a_new_buy(tmp_path, clock):
    accounts = {"paper": Account(cash="2000", full_position_usd="1000")}
    async with Rig(tmp_path, accounts, {"NVDA": "125"}) as rig:
        text = "买入 NVDA 125 一半"
        rig.reader.expect(text, buy("NVDA", "125", fraction="0.5", fraction_said="一半"))
        await rig.post(text)
        clock.shift(dt.timedelta(minutes=11))
        later = await rig.post(text)
        assert outcomes(later, "paper") == ("order_linked",)
        assert len(rig.brokers["paper"].submitted("buy")) == 2


async def test_a_reposted_buy_is_one_call_however_the_model_writes_its_fraction(tmp_path):
    """Oct 22 2026 audit: the repost checks compared fractions digit for digit, so a re-read
    that wrote 1/6 the other way bought a second sixth."""
    accounts = {"paper": Account(cash="5000", full_position_usd="1000")}
    async with Rig(tmp_path, accounts, {"NVDA": "125"}) as rig:
        post = "买入 NVDA 125 6分之一"
        rig.reader.expect(post, buy("NVDA", "125", fraction=SIXTH, fraction_said="6分之一"))
        await rig.post(post)
        rig.reader.expect(
            post, buy("NVDA", "125", fraction=SIXTH_AS_FLOAT, fraction_said="6分之一")
        )
        again = await rig.post(post)

        assert outcomes(again, "paper") == ("duplicate",)
        assert len(rig.brokers["paper"].submitted("buy")) == 1


async def test_a_reposted_sell_is_one_call_however_the_model_writes_its_fraction(tmp_path):
    """A sell repeated the same day sells once, or a recap of "sell a third" sells two thirds."""
    accounts = {"paper": Account(cash="5000", full_position_usd="1000")}
    async with Rig(tmp_path, accounts, {"NVDA": "100"}) as rig:
        broker = rig.brokers["paper"]
        rig.reader.expect("买入 NVDA 100", buy("NVDA", "100"))
        await rig.post("买入 NVDA 100")
        broker.move("NVDA", "130")
        post = "NVDA 100买的 130 卖出三分之一"
        rig.reader.expect(
            post, trim("NVDA", "130", bought_at="100", fraction=THIRD, fraction_said="三分之一")
        )
        await rig.post(post)
        rig.reader.expect(
            post,
            trim("NVDA", "130", bought_at="100", fraction=THIRD_AS_FLOAT, fraction_said="三分之一"),
        )
        again = await rig.post(post)

        assert outcomes(again, "paper") == ("duplicate",)
        assert len(broker.submitted("sell")) == 1
