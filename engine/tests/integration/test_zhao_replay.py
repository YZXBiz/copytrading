# ruff: noqa: RUF001 - 赵哥's real posts and prefix use a fullwidth colon
"""Opt-in live replay of 赵哥's own SOXL wording, against DeepSeek and Alpaca paper.

His posts name the buy a sell takes from by its price ("91出一半92.3的soxl": sell half of the shares
bought at 92.3). These replay his real phrasing, priced at the live market so every order fills,
and check each sell takes from exactly the buy it names (ADR-0010), and that a sell naming a buy
the account never made waits for the owner and says so.

    uv run --directory engine pytest tests/integration/test_zhao_replay.py -p no:randomly
"""

import asyncio
from decimal import ROUND_DOWN, Decimal

import pytest
import pytest_asyncio

from .paper import (
    LIVE,
    LIVE_REASON,
    Post,
    Rig,
    decided,
    destination_of,
    filled,
    flatten,
    guru_price,
    guru_sell_price,
)

pytestmark = [
    pytest.mark.skipif(not LIVE, reason=LIVE_REASON),
    pytest.mark.asyncio(loop_scope="module"),
]

SOXL = "SOXL"
SHARE = Decimal("0.000001")


def _zhao(words: str) -> Post:
    """A post as his channel carries it: the @everyone ping and his name before his words."""
    return Post(f"@everyone\n赵哥-股票： {words}")


@pytest_asyncio.fixture(autouse=True, loop_scope="module")
async def _clean_account():
    await asyncio.sleep(15)
    await flatten((SOXL,))


async def test_zhaos_sells_take_from_the_buy_each_names(tmp_path):
    first, second = await guru_price(SOXL), await guru_price(SOXL) + Decimal("0.05")
    sale = await guru_sell_price(SOXL)
    never = (first - Decimal("7.13")).quantize(Decimal("0.01"))
    posts = (
        _zhao(f"{first}加了6分之一常规仓soxl"),
        _zhao(f"{second}加了6分之一常规仓soxl 做日内 走势不对在日内撤"),
        _zhao("今天的轮廓图 盘前消息冲涨会带来盘中走低的反噬效应 尾盘附近在买回"),
        _zhao(f"{sale}出一半{first}的soxl"),
        _zhao(f"{sale}出掉{never}的soxl"),
        _zhao(f"{sale}出掉{second}的soxl"),
        # The rest goes at its own price, as he posts it: the same sell at the same price within
        # minutes is him re-posting one call.
        _zhao(f"{sale - Decimal('0.02')}出剩下一半{first}的soxl"),
    )
    async with Rig(tmp_path, posts) as rig:
        # Each buy is a sixth of his full position ($40 here), so about $6.66.
        [bought_first] = (await rig.post(0, until=filled))[1]
        [bought_second] = (await rig.post(1, until=filled))[1]
        for buy in (bought_first, bought_second):
            assert (buy.side, buy.status) == ("buy", "filled"), buy
            assert Decimal("6") <= buy.budget_usd <= Decimal("7"), buy
        held = await rig.owned(SOXL)
        assert held == bought_first.filled_quantity + bought_second.filled_quantity

        # Market talk trades nothing: read as talk, or held for the owner when the reader takes
        # "尾盘附近在买回" for a call it cannot ground in the post.
        chatter, orders = await rig.post(2, until=decided)
        assert orders == [], orders
        assert chatter.decision in {"ignore", "review"}, chatter

        # "出一半{first}的": half of the first buy, none of the second.
        [half] = (await rig.post(3, until=filled))[1]
        assert half.side == "sell", half
        expected = (bought_first.filled_quantity / 2).quantize(SHARE, ROUND_DOWN)
        assert abs(half.quantity - expected) <= SHARE, (half, bought_first)

        # A buy at a price he never bought at here: nothing is sold, and it waits for the owner,
        # saying no buy at that price ever reached this account.
        missing, orders = await rig.post(4, until=decided)
        assert orders == [], orders
        destination = destination_of(missing)
        assert destination.instruction_outcomes == ("named_buy_not_held",), destination
        [named] = destination.named_buys
        assert (named.posted_at, named.outcome) == (None, None), named

        # "出掉{second}的": all of the second buy.
        [out] = (await rig.post(5, until=filled))[1]
        assert out.quantity == bought_second.filled_quantity, (out, bought_second)

        # "出剩下一半{first}的": the rest of the first buy, and nothing is left.
        [rest] = (await rig.post(6, until=filled))[1]
        assert rest.quantity == bought_first.filled_quantity - half.filled_quantity, rest
        assert await rig.owned(SOXL) == 0
