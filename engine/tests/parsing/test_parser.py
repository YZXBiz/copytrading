"""A reading trades only when every value it states is the post's own words (ADR-0007)."""

from decimal import Decimal

import pytest
from pydantic_ai.messages import ModelMessage, ModelResponse, RetryPromptPart, TextPart
from pydantic_ai.models.function import AgentInfo, FunctionModel
from pydantic_ai.models.test import TestModel
from pydantic_ai.profiles import ModelProfile

from copytrading_engine.parsing.application import transform
from copytrading_engine.parsing.extraction import (
    DecodeError,
    GroundingError,
    ReadingOutput,
    check_reading,
)
from copytrading_engine.parsing.providers.anthropic import build_decoder as build_anthropic_decoder
from copytrading_engine.parsing.routes import Route
from copytrading_engine.shared.model_providers import ProviderConfig
from copytrading_engine.shared.reading import (
    AtMarket,
    Batch,
    Buy,
    Conditional,
    Exact,
    NotGiven,
    Range,
    Stock,
    Suggestion,
    TradeMade,
    Unclear,
)

from ..readings import buy, commentary, sell, trade
from .builders import TEXT, raw
from .fakes import FakeDecoder

SIXTH = "0.1666666666666666666666666667"


async def read(post: str, reading, route: Route | None = None):
    return await transform(raw(post), route or Route(), FakeDecoder(reading), "test")


def check(post: str, reading, route: Route | None = None) -> None:
    check_reading(reading, post, route or Route())


def failure(post: str, reading, route: Route | None = None) -> GroundingError:
    with pytest.raises(GroundingError) as raised:
        check(post, reading, route)
    return raised.value


def _no_price(call: Buy) -> Buy:
    return call.model_copy(update={"price": NotGiven()})


# --- A grounded call trades -------------------------------------------------------------------


async def test_a_grounded_buy_trades_with_its_evidence():
    result = await read(TEXT, trade(buy("ABC", "25", fraction=SIXTH, fraction_said="6分之一")))

    assert result.decision == "trade"
    [instruction] = result.instructions
    assert (instruction.price, instruction.fraction) == (Decimal(25), Decimal(SIXTH))
    assert result.evidence[0].price_evidence == "25"
    assert isinstance(result.reading, TradeMade)


async def test_a_buy_with_no_size_keeps_no_size_through_json():
    result = await read("25加了常规仓abc", trade(buy("ABC", "25")))

    assert result.instructions[0].fraction is None
    assert result.model_validate_json(result.model_dump_json()) == result


async def test_a_buy_back_is_one_buy_at_the_current_price():
    result = await read("25加回29卖出的abc", trade(buy("ABC", "25", said="加回")))

    [instruction] = result.instructions
    assert (instruction.action, instruction.price, instruction.entry_price) == (
        "buy",
        Decimal(25),
        None,
    )


@pytest.mark.parametrize(
    ("post", "call", "action", "fraction"),
    [
        pytest.param(
            "27出一半25的abc",
            sell("ABC", "27", bought_at="25", said="出一半", fraction="0.5", fraction_said="一半"),
            "reduce",
            Decimal("0.5"),
            id="half-of-a-lot-is-a-trim",
        ),
        pytest.param(
            "28出掉25剩下一半abc",
            sell("ABC", "28", bought_at="25"),
            "close",
            Decimal(1),
            id="selling-out-is-a-close",
        ),
        pytest.param(
            "245出剩下一半236的abc",
            sell(
                "ABC",
                "245",
                bought_at="236",
                said="出剩下一半",
                fraction="0.5",
                fraction_said="一半",
                counts_from="remaining",
            ),
            "reduce",
            Decimal("0.5"),
            id="half-of-what-is-left-counts-from-the-remainder",
        ),
    ],
)
async def test_a_sell_names_its_lot(post, call, action, fraction):
    result = await read(post, trade(call))

    [instruction] = result.instructions
    assert (instruction.action, instruction.fraction) == (action, fraction)


async def test_lots_named_in_one_post_stay_separate():
    post = "28出掉27的abc出掉25的一半"
    calls = (
        sell("ABC", "28", bought_at="27"),
        sell("ABC", "28", bought_at="25", fraction="0.5", fraction_said="一半"),
    )

    result = await read(post, trade(*calls))

    assert [(i.action, i.entry_price) for i in result.instructions] == [
        ("close", Decimal(27)),
        ("reduce", Decimal(25)),
    ]


async def test_one_price_cannot_be_both_the_sale_and_the_lot():
    call = sell("ABC", "25", bought_at="25", said="出一半", fraction="0.5", fraction_said="一半")

    assert failure("出一半25的abc", trade(call)).issue.code == "price_occurrence_reused"
    assert (await read("25出一半25的abc", trade(call))).decision == "trade"


# --- Act or ask -------------------------------------------------------------------------------


SCO = Buy(
    action_words="买",
    stock=Stock(ticker="SCO", words="sco"),
    price=Exact(value=Decimal(20), words="20"),
    size=NotGiven(),
)


@pytest.mark.parametrize(
    ("post", "reading", "decision", "reason"),
    [
        pytest.param("大盘今天很强", commentary("Market talk"), "ignore", "Market talk", id="talk"),
        pytest.param("sco ???", Unclear(summary="Cannot tell"), "review", "unclear", id="unclear"),
        pytest.param(
            "如果明天20以下买sco",
            Conditional(summary="Buy if below 20", condition="如果明天20以下", calls=(SCO,)),
            "review",
            "conditional",
            id="conditional",
        ),
        pytest.param(
            "sco 20可以考虑买",
            Suggestion(summary="Consider SCO at 20", calls=(SCO,)),
            "review",
            "suggestion",
            id="suggestion",
        ),
        pytest.param(
            "sco 18-20买",
            trade(
                SCO.model_copy(
                    update={"price": Range(low=18, high=20, low_words="18", high_words="20")}
                )
            ),
            "review",
            "price_range",
            id="a-price-range",
        ),
        pytest.param(
            "现价买sco",
            trade(_no_price(SCO).model_copy(update={"price": AtMarket(words="现价")})),
            "review",
            "price_at_market",
            id="at-market",
        ),
        pytest.param("买sco", trade(_no_price(SCO)), "review", "price_not_given", id="no-price"),
        pytest.param(
            "sco 20买第二批",
            trade(SCO.model_copy(update={"size": Batch(number=2, words="第二批")})),
            "review",
            "batch_size_unknown",
            id="a-batch",
        ),
        pytest.param(
            "sco 20跑路了",
            trade(sell("SCO", "20", bought_at=None, said="跑路了")),
            "review",
            "sell_names_no_buy",
            id="a-sell-naming-no-buy",
        ),
    ],
)
async def test_only_a_placeable_current_call_trades(post, reading, decision, reason):
    result = await read(post, reading)

    assert (result.decision, result.reason, result.instructions) == (decision, reason, ())
    assert result.reading == reading


async def test_a_post_with_one_unplaceable_call_places_none_of_them():
    reading = trade(buy("ABC", "25"), sell("SCO", "20", bought_at=None, said="跑路了"))

    result = await read("25加了abc sco 20跑路了", reading)

    assert (result.decision, result.instructions) == ("review", ())


async def test_a_prefix_mismatch_never_calls_the_model():
    decoder = FakeDecoder(trade(buy("ABC", "25")))

    result = await transform(raw(), Route(prefix="Different:"), decoder, "test")

    assert (result.decision, decoder.calls) == ("ignore", 0)


async def test_prefix_and_post_are_normalized_alike():
    result = await read(
        "Example：" + TEXT,  # noqa: RUF001 - the fullwidth colon is the input under test
        trade(buy("ABC", "25", fraction=SIXTH, fraction_said="6分之一")),
        Route(prefix="Example："),  # noqa: RUF001 - the fullwidth colon is the input under test
    )

    assert result.decision == "trade"


# --- Every value is the post's words ----------------------------------------------------------


@pytest.mark.parametrize(
    ("reading", "path"),
    [
        pytest.param(trade(buy("ABC", "250", price_said="250")), "calls.0.price", id="price"),
        pytest.param(trade(buy("ABC", "5", price_said="5")), "calls.0.price", id="part-of-25"),
        pytest.param(trade(buy("DEF", "25")), "calls.0.stock", id="ticker"),
        pytest.param(trade(buy("ABC", "25", said="buy")), "calls.0.action_words", id="action"),
    ],
)
async def test_a_value_the_post_does_not_state_goes_to_review(reading, path):
    with pytest.raises(DecodeError) as raised:
        await read(TEXT, reading)

    assert raised.value.reason == "evidence_validation_failed"
    assert raised.value.issues[0].path == path


@pytest.mark.parametrize("post", ["如果" + TEXT, "昨天" + TEXT, "计划" + TEXT])
def test_conditional_or_past_words_cannot_be_read_as_a_trade(post):
    assert failure(post, trade(buy("ABC", "25"))).issue.code == "noncurrent_trade"


def test_a_condition_must_be_the_posts_words():
    reading = Conditional(summary="Buy if below 20", condition="如果跌破20", calls=(SCO,))

    assert failure("如果明天20以下买sco", reading).issue.path == "condition"


@pytest.mark.parametrize(
    ("words", "value"),
    [
        pytest.param("6分之一", SIXTH, id="chinese-sixth"),
        pytest.param("6分之一", "0.16666666666666666", id="a-model-rounded-sixth"),
        pytest.param("6分之一常规仓", "0.16666666666666666", id="words-around-the-size"),
    ],
)
def test_a_stated_size_is_grounded(words, value):
    check(TEXT, trade(buy("ABC", "25", fraction=value, fraction_said=words)))


@pytest.mark.parametrize(
    ("post", "words", "value"),
    [
        pytest.param("25加了1/6常规仓abc", "1/6", SIXTH, id="ascii-sixth"),
        pytest.param("25加了1/3常规仓abc", "1/3", "0.3333333333333333333333333333", id="third"),
        pytest.param("25加了half仓abc", "half", "0.5", id="half-beside-chinese"),
        pytest.param("25加了full仓abc", "full", "1", id="full-beside-chinese"),
    ],
)
async def test_a_stated_size_keeps_its_value(post, words, value):
    result = await read(post, trade(buy("ABC", "25", fraction=value, fraction_said=words)))

    assert result.instructions[0].fraction == Decimal(value)


@pytest.mark.parametrize(
    ("post", "words", "value"),
    [
        pytest.param(TEXT, "6分之一", "0.5", id="another-value"),
        pytest.param(TEXT, "6分之一", "0.1667", id="a-sixth-rounded-too-far"),
        pytest.param(TEXT, "6分之一常规仓", "0.5", id="another-value-with-words-around"),
        pytest.param("25加了halfway仓abc", "half", "0.5", id="half-inside-halfway"),
        pytest.param("25加了fullest仓abc", "full", "1", id="full-inside-fullest"),
        pytest.param("25加了11/6仓abc", "1/6", SIXTH, id="part-of-11/6"),
        pytest.param("25加了125%仓abc", "25%", "0.25", id="part-of-125%"),
        pytest.param("25加了11分之一仓abc", "1分之一", "1", id="part-of-11分之一"),
    ],
)
def test_a_size_must_be_a_whole_stated_size(post, words, value):
    reading = trade(buy("ABC", "25", fraction=value, fraction_said=words))

    assert failure(post, reading).issue.code == "fraction_not_grounded"


@pytest.mark.parametrize("word", ["halfway", "fullest"])
def test_a_word_containing_a_size_is_no_size(word):
    check(f"25加了{word}仓abc", trade(buy("ABC", "25")))


@pytest.mark.parametrize(
    "post",
    [
        "25加了6分之一常规仓abc",
        "25加了1/6常规仓abc",
        "25加了25%常规仓abc",
        "25加了half仓abc",
        "25加了full仓abc",
    ],
)
def test_the_reader_cannot_drop_a_stated_size(post):
    assert failure(post, trade(buy("ABC", "25"))).issue.code == "source_fraction_omitted"


@pytest.mark.parametrize("post", ["Bought ABC at 25, half position", "Bought ABC at 25, full"])
def test_the_reader_cannot_drop_a_size_stated_in_english(post):
    reading = trade(buy("ABC", "25", said="Bought", ticker_said="ABC"))

    assert failure(post, reading).issue.code == "source_fraction_omitted"


@pytest.mark.parametrize(
    ("words", "number", "grounded"),
    [
        pytest.param("第二批", 2, True, id="chinese-number"),
        pytest.param("第2批", 2, True, id="digit"),
        pytest.param("第二批", 3, False, id="another-number"),
    ],
)
def test_a_batch_is_the_number_the_post_writes(words, number, grounded):
    post = f"sco 20买{words}"
    reading = trade(SCO.model_copy(update={"size": Batch(number=number, words=words)}))

    if grounded:
        check(post, reading)
    else:
        assert failure(post, reading).issue.code == "batch_not_grounded"


def test_a_range_names_both_ends_from_the_post():
    zone = Range(low=Decimal(160), high=Decimal(179), low_words="160", high_words="179")
    zone_buy = SCO.model_copy(update={"action_words": "建仓", "price": zone})
    reading = Suggestion(summary="A zone", calls=(zone_buy,))

    check("sco 建仓区域160-179", reading)
    assert failure("sco 建仓区域160-170", reading).issue.path == "calls.0.price.high"


# --- Tickers ----------------------------------------------------------------------------------


@pytest.mark.parametrize(
    ("playbook", "grounded"),
    [
        pytest.param("", False, id="no-playbook"),
        pytest.param("苹果 is a fruit\nAAPL is Apple", False, id="name-and-ticker-apart"),
        pytest.param("苹果 means AAPLX", False, id="a-longer-ticker"),
        pytest.param("加 means buy\n苹果 means AAPL", True, id="one-line-states-both"),
    ],
)
def test_a_name_becomes_a_ticker_only_through_the_playbook(playbook, grounded):
    reading = trade(buy("AAPL", "25", ticker_said="苹果"))
    route = Route(playbook=playbook)

    if grounded:
        check("25加了苹果", reading, route)
    else:
        assert failure("25加了苹果", reading, route).issue.code == "symbol_not_in_playbook"


def test_a_written_ticker_needs_no_playbook_but_must_be_a_whole_word():
    check("25加了abc", trade(buy("ABC", "25")))

    assert failure("25加了abc", trade(buy("AB", "25"))).issue.code == "partial_symbol"


# --- The model gets one retry with the reason -------------------------------------------------


def _decoder(model):
    from anthropic import AsyncAnthropic

    decoder = build_anthropic_decoder(
        ProviderConfig(api_key="test-only", model="claude-haiku-4-5-20251001", timeout=20),
        AsyncAnthropic(api_key="test-only", max_retries=0),
    )
    return decoder, decoder.agent.override(model=model)


JSON_OUTPUT = ModelProfile(supports_json_schema_output=True)


def _answer(reading) -> str:
    return ReadingOutput(reading=reading).model_dump_json()


async def test_the_adapter_returns_the_models_reading():
    reading = trade(buy("ABC", "25", fraction=SIXTH, fraction_said="6分之一"))
    decoder, model = _decoder(TestModel(custom_output_text=_answer(reading), profile=JSON_OUTPUT))
    try:
        with model:
            assert await decoder.decode(TEXT, Route()) == reading
    finally:
        await decoder.close()


async def test_an_ungrounded_reading_goes_back_once_with_its_reason():
    wrong = trade(buy("ABC", "250", price_said="250", fraction=SIXTH, fraction_said="6分之一"))
    right = trade(buy("ABC", "25", fraction=SIXTH, fraction_said="6分之一"))
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
            assert await decoder.decode(TEXT, Route()) == right
    finally:
        await decoder.close()
    assert len(told) == 1
    assert "calls.0.price" in told[0]


async def test_a_reading_still_ungrounded_after_the_retry_fails():
    wrong = trade(buy("ABC", "250", price_said="250"))
    decoder, model = _decoder(TestModel(custom_output_text=_answer(wrong), profile=JSON_OUTPUT))
    try:
        with model, pytest.raises(DecodeError) as raised:
            await decoder.decode(TEXT, Route())
    finally:
        await decoder.close()
    assert raised.value.reason in {"invalid_model_output", "model_output_budget_exceeded"}
