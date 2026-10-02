"""Zhao, a guru who posts in Chinese and English, and a model that reads his posts as a careful
interpreter would. The reading is scripted, but the engine still checks that every price, ticker,
and fraction it cites is in the post, exactly as it checks a real model's answer."""

from decimal import Decimal

from copytrading_engine.parsing.extraction import DecodedMessage, ExtractedInstruction

PREFIX = "ZHAO:"
# The app gives every guru an id of its own; the owner only ever sees the name.
GURU_ID = "guru-2a3b4c5d"
NAME = "Zhao"


def buy(
    symbol: str,
    price: str,
    *,
    said: str = "买入",
    fraction: str | None = None,
    fraction_said: str | None = None,
) -> ExtractedInstruction:
    return ExtractedInstruction(
        action="buy",
        symbol=symbol,
        price=Decimal(price),
        fraction=Decimal(fraction) if fraction else None,
        action_evidence=said,
        symbol_evidence=symbol,
        price_evidence=price,
        fraction_evidence=fraction_said,
    )


def trim(
    symbol: str,
    price: str,
    *,
    bought_at: str,
    fraction: str,
    fraction_said: str,
    said: str = "卖出",
) -> ExtractedInstruction:
    return ExtractedInstruction(
        action="reduce",
        symbol=symbol,
        price=Decimal(price),
        entry_price=Decimal(bought_at),
        fraction=Decimal(fraction),
        exit_basis="original_position",
        action_evidence=said,
        symbol_evidence=symbol,
        price_evidence=price,
        entry_evidence=bought_at,
        fraction_evidence=fraction_said,
    )


def close(symbol: str, price: str, *, bought_at: str, said: str = "清仓") -> ExtractedInstruction:
    return ExtractedInstruction(
        action="close",
        symbol=symbol,
        price=Decimal(price),
        entry_price=Decimal(bought_at),
        fraction=Decimal(1),
        action_evidence=said,
        symbol_evidence=symbol,
        price_evidence=price,
        entry_evidence=bought_at,
    )


class ZhaoReader:
    """The model: each post Zhao writes has the reading a careful interpreter gives it."""

    def __init__(self) -> None:
        self.readings: dict[str, DecodedMessage] = {}
        self.read: list[str] = []

    def expect(self, text: str, *instructions: ExtractedInstruction) -> None:
        self.readings[text] = (
            DecodedMessage(decision="trade", reason="A current call", instructions=instructions)
            if instructions
            else DecodedMessage(decision="ignore", reason="No trade action", instructions=())
        )

    async def decode(self, text, route):
        if text == "Market commentary only. No trade action.":  # the runtime's readiness probe
            return DecodedMessage(decision="ignore", reason="No trade action", instructions=())
        assert route.prefix == PREFIX
        self.read.append(text)
        return self.readings[text]

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
