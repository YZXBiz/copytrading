"""Zhao, a guru who posts in Chinese and English, and a model that reads his posts as a careful
interpreter would. The reading is scripted, but the engine still checks that every price, ticker,
and fraction it cites is in the post, exactly as it checks a real model's answer."""

from copytrading_engine.parsing.extraction import Answer
from copytrading_engine.shared.reading import (
    All,
    Buy,
    Fraction,
    NotGiven,
    NotSaid,
    PostReading,
    Sell,
    Stock,
)
from copytrading_engine.shared.route_keys import guru_for_channel

from .. import readings

# Zhao's channel names him (route_keys.guru_for_channel); the owner only ever sees the name.
CHANNEL = "900000000000000777"
GURU_ID = guru_for_channel("discord", CHANNEL)
NAME = "Zhao"


def buy(
    symbol: str,
    price: str,
    *,
    said: str = "买入",
    fraction: str | None = None,
    fraction_said: str | None = None,
) -> Buy:
    return readings.buy(
        symbol, price, said=said, ticker_said=symbol, fraction=fraction, fraction_said=fraction_said
    )


def trim(
    symbol: str,
    price: str,
    *,
    bought_at: str,
    fraction: str,
    fraction_said: str,
    said: str = "卖出",
) -> Sell:
    return readings.sell(
        symbol,
        price,
        bought_at=bought_at,
        said=said,
        ticker_said=symbol,
        fraction=fraction,
        fraction_said=fraction_said,
    )


def sell_now(symbol: str, *, said: str, share: Fraction | All) -> Sell:
    """A sell with no price and no buy named, such as "sell WMT half": out now, at the market."""
    return Sell(
        action_words=said,
        stock=Stock(ticker=symbol, words=symbol),
        price=NotGiven(),
        share=share,
        sell_from=NotSaid(),
    )


def close(symbol: str, price: str, *, bought_at: str, said: str = "清仓") -> Sell:
    return readings.sell(symbol, price, bought_at=bought_at, said=said, ticker_said=symbol)


class ZhaoReader:
    """The model: each post Zhao writes has the reading a careful interpreter gives it."""

    def __init__(self) -> None:
        self.readings: dict[str, PostReading] = {}
        self.read: list[str] = []

    def expect(self, text: str, *calls: Buy | Sell) -> None:
        self.readings[text] = readings.trade(*calls) if calls else readings.commentary()

    async def answer(self, text, route, recent=()):
        if text == "Market commentary only. No trade action.":  # the runtime's readiness probe
            return Answer(readings.commentary())
        self.read.append(text)
        return Answer(self.readings[text])

    async def close(self):
        pass


class ZhaoChannel:
    """The Discord session: Zhao's posts arrive when the test writes them."""

    def __init__(self, source) -> None:
        self.source = source
        self.ready = True

    def start(self, token):
        pass

    async def ensure_running(self):
        pass

    async def forward_if_ready(self, forwarder):
        await forwarder.flush()

    async def close(self):
        pass
