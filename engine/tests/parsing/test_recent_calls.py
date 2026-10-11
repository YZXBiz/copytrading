"""The reader reads each post beside the guru's recent calls (ADR-0010): which buys are open, what
a re-post restates, and the owner's corrections in place of the reader's own reading."""

import datetime as dt
from decimal import Decimal

import pytest
from pydantic_ai.messages import ModelMessage, ModelResponse, RetryPromptPart, TextPart
from pydantic_ai.models.function import AgentInfo, FunctionModel
from pydantic_ai.profiles import ModelProfile

from copytrading_engine.parsing.application import transform
from copytrading_engine.parsing.extraction import ReadingOutput
from copytrading_engine.parsing.history import PastCall, describe, recent_calls
from copytrading_engine.parsing.providers.anthropic import build_decoder as build_anthropic_decoder
from copytrading_engine.parsing.routes import Route
from copytrading_engine.parsing.sqlite import SQLiteExtractionStore, record_owner_correction
from copytrading_engine.shared.model_providers import ProviderConfig
from copytrading_engine.shared.reading import Fraction, NotGiven, NotSaid, Sell, Stock
from copytrading_engine.shared.signals import Instruction

from ..readings import buy, commentary, sell, trade
from .builders import raw
from .fakes import FakeDecoder

NOW = dt.datetime(2026, 10, 7, 15, 0, tzinfo=dt.UTC)
SIXTH = str(Decimal(1) / 6)


def _past(key: str, minutes_ago: int, *instructions: Instruction) -> list[PastCall]:
    at = NOW - dt.timedelta(minutes=minutes_ago)
    return [
        PastCall(source_key=key, index=index, at=at, instruction=instruction)
        for index, instruction in enumerate(instructions)
    ]


def _buy(symbol: str, price: str) -> Instruction:
    return Instruction(action="buy", symbol=symbol, price=Decimal(price), fraction=Decimal(1) / 6)


def _close(symbol: str, price: str, entry: str | None = None) -> Instruction:
    return Instruction(
        action="close",
        symbol=symbol,
        price=Decimal(price),
        entry_price=None if entry is None else Decimal(entry),
        fraction=Decimal(1),
    )


# --- The guru's book ---------------------------------------------------------------------------


def test_a_buy_stays_open_until_a_sell_closes_it_by_its_price():
    calls = recent_calls(
        [
            *_past("p1", 90, _buy("IREN", "39.5")),
            *_past("p2", 60, _buy("IREN", "41")),
            *_past("p3", 30, _close("IREN", "45", entry="39.5")),
        ]
    )

    assert [(c.ref, c.action, c.price, c.open) for c in calls] == [
        ("c1", "buy", Decimal("39.5"), False),
        ("c2", "buy", Decimal("41"), True),
        ("c3", "close", Decimal("45"), False),
    ]


def test_a_sell_naming_no_buy_closes_every_buy_of_the_stock():
    calls = recent_calls(
        [
            *_past("p1", 90, _buy("IREN", "39.5"), _buy("RCL", "250")),
            *_past("p2", 60, _buy("IREN", "41")),
            *_past("p3", 30, _close("IREN", "45")),
        ]
    )

    assert [(c.symbol, c.open) for c in calls if c.action == "buy"] == [
        ("IREN", False),
        ("RCL", True),
        ("IREN", False),
    ]


def test_every_open_buy_is_shown_however_old_and_only_the_last_ten_closed_calls():
    past = _past("old", 60 * 24 * 30, _buy("NVDA", "100"))
    for n in range(15):
        past += _past(
            f"s{n}", 600 - n, _buy("SOUN", str(5 + n)), _close("SOUN", str(6 + n), str(5 + n))
        )

    calls = recent_calls(past)

    assert calls[0].symbol == "NVDA"
    assert calls[0].open
    assert len([c for c in calls if not c.open]) == 10
    assert [c.ref for c in calls] == [f"c{n}" for n in range(1, len(calls) + 1)]


def test_the_reader_is_shown_fields_never_a_posts_text():
    [call] = recent_calls(_past("p1", 5, _buy("SOUN", "5.85")))

    assert (
        describe((call,), NOW)
        == "c1 · buy · SOUN · at 5.85 · share 0.1666666666666666666666666667 · open · 5 min ago"
    )


def test_a_sell_at_the_market_is_shown_with_no_price():
    sold = Instruction(action="reduce", symbol="WMT", price=None, fraction=Decimal("0.5"))
    [bought, call] = recent_calls(_past("p1", 5, _buy("WMT", "113"), sold))

    shown = describe((call,), NOW)
    assert shown == "c2 · reduce · WMT · at market · share 0.5 · closed · 5 min ago"
    assert bought.open


# --- The reader sees them, and is held to them -------------------------------------------------

JSON_OUTPUT = ModelProfile(supports_json_schema_output=True)


def _decoder(model):
    from anthropic import AsyncAnthropic

    decoder = build_anthropic_decoder(
        ProviderConfig(api_key="test-only", model="claude-haiku-4-5-20251001", timeout=20),
        AsyncAnthropic(api_key="test-only", max_retries=0),
    )
    return decoder, decoder.agent.override(model=model)


def _answer(reading) -> str:
    return ReadingOutput(reading=reading).model_dump_json()


async def test_the_reader_gets_the_playbook_then_the_recent_calls_after_its_fixed_instructions():
    shown: list[str] = []
    reading = trade(sell("IREN", "45", bought_at="39.5", said="出掉"))

    def reader(messages: list[ModelMessage], info: AgentInfo) -> ModelResponse:
        shown.append(info.instructions or "")
        return ModelResponse(parts=[TextPart(_answer(reading))])

    recent = recent_calls(_past("p1", 5, _buy("IREN", "39.5")))
    decoder, model = _decoder(FunctionModel(reader, profile=JSON_OUTPUT))
    try:
        with model:
            assert (
                await decoder.decode(
                    "iren 39.5的 45出掉", Route(playbook="艾伦 means IREN"), recent
                )
                == reading
            )
    finally:
        await decoder.close()
    [instructions] = shown
    fixed = instructions.index("Read one stock or ETF post")
    playbook = instructions.index("艾伦 means IREN")
    listed = instructions.index("c1 · buy · IREN · at 39.5")
    assert fixed < playbook < listed


async def test_a_repeat_must_name_a_listed_call_or_the_reader_is_asked_again():
    recent = recent_calls(_past("p1", 5, _buy("SOUN", "5.85")))
    wrong = trade(buy("SOUN", "5.85").model_copy(update={"repeats": "c9"}))
    right = trade(buy("SOUN", "5.85").model_copy(update={"repeats": "c1"}))
    told: list[str] = []

    def reader(messages: list[ModelMessage], info: AgentInfo) -> ModelResponse:
        told.extend(
            str(part.content)
            for message in messages
            for part in message.parts
            if isinstance(part, RetryPromptPart)
        )
        return ModelResponse(parts=[TextPart(_answer(right if told else wrong))])

    decoder, model = _decoder(FunctionModel(reader, profile=JSON_OUTPUT))
    try:
        with model:
            assert await decoder.decode("5.85加了soun", Route(), recent) == right
    finally:
        await decoder.close()
    assert len(told) == 1
    assert "c9 is not one of the listed calls" in told[0]


async def test_a_sell_naming_a_buy_the_guru_does_not_hold_is_asked_about_once_then_believed():
    recent = recent_calls(_past("p1", 5, _buy("IREN", "39.5")))
    named = trade(sell("IREN", "45", bought_at="40", said="出掉"))
    asked: list[str] = []

    def reader(messages: list[ModelMessage], info: AgentInfo) -> ModelResponse:
        asked.extend(
            str(part.content)
            for message in messages
            for part in message.parts
            if isinstance(part, RetryPromptPart)
        )
        # The post really says 40: the reader keeps its answer, which then stands.
        return ModelResponse(parts=[TextPart(_answer(named))])

    decoder, model = _decoder(FunctionModel(reader, profile=JSON_OUTPUT))
    try:
        with model:
            assert await decoder.decode("iren 40的 45出掉", Route(), recent) == named
    finally:
        await decoder.close()
    assert len(asked) == 1
    assert "open IREN buys are at 39.5" in asked[0]


async def test_sell_half_of_a_held_stock_with_no_price_trades_through_the_reader():
    """Zhao, Oct 9 2026: "buy wmt at 110 1/6", "buy wmt at 113 1/6", then "sell wmt half". The
    reader read it right (a sell of half, no price, no buy named) and the post still waited for
    the owner with price_not_given. With both buys listed as open, the real reader agent and its
    checks pass the reading on the first try, and it becomes a sell of half of every WMT buy at
    the market."""
    recent = recent_calls(
        [*_past("p1", 6, _buy("WMT", "110")), *_past("p2", 3, _buy("WMT", "113"))]
    )
    reading = trade(
        Sell(
            action_words="sell",
            stock=Stock(ticker="WMT", words="wmt"),
            price=NotGiven(),
            share=Fraction(value=Decimal("0.5"), words="half"),
            sell_from=NotSaid(),
        )
    )
    shown: list[str] = []
    retried: list[str] = []

    def reader(messages: list[ModelMessage], info: AgentInfo) -> ModelResponse:
        shown.append(info.instructions or "")
        retried.extend(
            str(part.content)
            for message in messages
            for part in message.parts
            if isinstance(part, RetryPromptPart)
        )
        return ModelResponse(parts=[TextPart(_answer(reading))])

    decoder, model = _decoder(FunctionModel(reader, profile=JSON_OUTPUT))
    try:
        with model:
            result = await transform(_post("sell wmt half"), Route(), decoder, "test", recent)
    finally:
        await decoder.close()

    assert retried == []
    assert "c1 · buy · WMT · at 110" in shown[0]
    assert "c2 · buy · WMT · at 113" in shown[0]
    assert (result.decision, result.reading) == ("trade", reading)
    assert result.instructions == (
        Instruction(
            action="reduce",
            symbol="WMT",
            price=None,
            fraction=Decimal("0.5"),
            exit_basis="remaining_position",
        ),
    )


async def test_a_buy_with_no_price_still_waits_through_the_reader():
    """Only a sell goes at the market: a buy needs the guru's price to bound what it pays."""
    reading = trade(buy("WMT", "113", said="buy").model_copy(update={"price": NotGiven()}))

    def reader(messages: list[ModelMessage], info: AgentInfo) -> ModelResponse:
        return ModelResponse(parts=[TextPart(_answer(reading))])

    decoder, model = _decoder(FunctionModel(reader, profile=JSON_OUTPUT))
    try:
        with model:
            result = await transform(_post("buy wmt"), Route(), decoder, "test")
    finally:
        await decoder.close()

    assert (result.decision, result.reason, result.suggested) == ("review", "price_not_given", ())


# --- What a repeat does, under the guru's window -----------------------------------------------


def _post(text: str, minutes_after: int = 0):
    return raw(text).model_copy(update={"timestamp": NOW + dt.timedelta(minutes=minutes_after)})


async def _read(text, reading, window, minutes_after=0):
    recent = recent_calls(_past("p1", 0, _buy("SOUN", "5.85")))
    route = Route(repeat_window_minutes=window)
    return await transform(_post(text, minutes_after), route, FakeDecoder(reading), "test", recent)


REPOST = trade(
    buy("SOUN", "5.85", fraction=SIXTH, fraction_said="6分之一").model_copy(
        update={"repeats": "c1"}
    )
)


async def test_a_repost_within_the_window_is_not_a_new_call():
    result = await _read("5.85加了6分之一soun", REPOST, window=10, minutes_after=5)

    assert (result.decision, result.reason, result.instructions) == (
        "ignore",
        "repeats_a_recent_call",
        (),
    )


async def test_a_repost_after_the_window_waits_for_the_owner():
    result = await _read("5.85加了6分之一soun", REPOST, window=10, minutes_after=30)

    assert (result.decision, result.reason) == ("review", "repeats_an_earlier_call")
    assert [i.symbol for i in result.suggested] == ["SOUN"]


async def test_with_the_window_off_a_repost_is_copied_as_a_new_call():
    result = await _read("5.85加了6分之一soun", REPOST, window=None, minutes_after=5)

    assert result.decision == "trade"
    assert [i.symbol for i in result.instructions] == ["SOUN"]


async def test_a_post_with_a_repost_and_a_new_call_copies_only_the_new_one():
    reading = trade(
        buy("SOUN", "5.85", fraction=SIXTH, fraction_said="6分之一").model_copy(
            update={"repeats": "c1"}
        ),
        buy("ABC", "25", fraction=SIXTH, fraction_said="6分之一"),
    )

    result = await _read(
        "5.85加了6分之一soun 25加了6分之一abc", reading, window=10, minutes_after=5
    )

    assert result.decision == "trade"
    assert [i.symbol for i in result.instructions] == ["ABC"]


# --- Where the calls come from ----------------------------------------------------------------


@pytest.fixture
async def store(tmp_path):
    opened = await SQLiteExtractionStore.open(tmp_path / "application.db")
    yield opened
    await opened.close()


async def _finish(store, message_id: str, text: str, reading, at: dt.datetime, channel="demo"):
    event = raw(text).model_copy(update={"id": message_id, "timestamp": at, "channel_id": channel})
    await store.add(event)
    result = await transform(event, Route(), FakeDecoder(reading), "test")
    await store.finish(f"discord:{channel}:{message_id}", result)
    return event


async def test_the_store_replays_the_channels_traded_calls_before_the_post(store):
    await _finish(store, "1", "25加了abc", trade(buy("ABC", "25")), NOW)
    await _finish(store, "2", "今天大盘不错", commentary(), NOW + dt.timedelta(minutes=1))
    await _finish(store, "3", "25加了abc", trade(buy("ABC", "25")), NOW, channel="other")
    current = raw("abc 30出掉").model_copy(update={"id": "4"})
    await store.add(current)

    past = await store.past_calls("demo", "discord:demo:4")

    assert [(c.source_key, c.instruction.symbol) for c in past] == [("discord:demo:1", "ABC")]


async def test_the_owners_correction_replaces_the_readers_call(store, tmp_path):
    await _finish(store, "1", "25加了abc", trade(buy("ABC", "25")), NOW)
    record_owner_correction(
        tmp_path / "application.db", "discord:demo:1", (_buy("ABD", "25"),), NOW
    )
    await store.add(raw("abc 30出掉").model_copy(update={"id": "2"}))

    [past] = await store.past_calls("demo", "discord:demo:2")

    assert past.instruction.symbol == "ABD"


@pytest.mark.parametrize(
    "second", ["Sells half of WMT", "卖出一半WMT"], ids=["corrected", "stands"]
)
async def test_an_english_post_read_with_a_chinese_summary_is_asked_about_once(second):
    """Oct 9 2026: "Out of all my NIO" came back summarized as "全部卖出NIO。". The reader is told
    once to write the post's language; whatever it answers next stands."""
    recent = recent_calls(_past("p1", 3, _buy("WMT", "110")))

    def reading(summary: str):
        return trade(
            Sell(
                action_words="sell",
                stock=Stock(ticker="WMT", words="wmt"),
                price=NotGiven(),
                share=Fraction(value=Decimal("0.5"), words="half"),
                sell_from=NotSaid(),
            ),
            summary=summary,
        )

    asked: list[str] = []

    def reader(messages: list[ModelMessage], info: AgentInfo) -> ModelResponse:
        asked.extend(
            str(part.content)
            for message in messages
            for part in message.parts
            if isinstance(part, RetryPromptPart)
        )
        summary = "卖出一半WMT" if not asked else second
        return ModelResponse(parts=[TextPart(_answer(reading(summary)))])

    decoder, model = _decoder(FunctionModel(reader, profile=JSON_OUTPUT))
    try:
        with model:
            assert await decoder.decode("sell wmt half", Route(), recent) == reading(second)
    finally:
        await decoder.close()
    assert len(asked) == 1
    assert "English" in asked[0]
