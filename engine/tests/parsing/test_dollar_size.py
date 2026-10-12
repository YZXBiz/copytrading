"""A buy the post sizes in dollars buys that amount, not a full position."""

from decimal import Decimal

import pytest

from copytrading_engine.parsing.application import transform
from copytrading_engine.parsing.extraction import GroundingError, check_reading
from copytrading_engine.parsing.routes import Route
from copytrading_engine.shared.reading import Buy, Dollars, Exact, Stock

from ..readings import buy, trade
from .builders import raw
from .fakes import FakeDecoder

SIXTH = "0.1666666666666666666666666667"


def dollar_buy(post: str, amount: str, words: str) -> Buy:
    return Buy(
        action_words="买" if "买" in post else "buy",
        stock=Stock(ticker="NFLX", words="nflx"),
        price=Exact(value=Decimal(71), words="71"),
        size=Dollars(value=Decimal(amount), words=words),
    )


def grounding_code(post: str, reading) -> str:
    with pytest.raises(GroundingError) as raised:
        check_reading(reading, post, Route())
    return raised.value.issue.code


@pytest.mark.parametrize(
    ("post", "words", "amount"),
    [
        pytest.param("buy 200$ of nflx at 71", "200$ of", "200", id="dollars-after"),
        pytest.param("buy $200 of nflx at 71", "$200 of", "200", id="dollars-before"),
        pytest.param("buy nflx 200 dollars at 71", "200 dollars", "200", id="dollars-word"),
        pytest.param("buy $1,500 of nflx at 71", "$1,500 of", "1500", id="thousands"),
        pytest.param("nflx 71 买两百刀", "两百刀", "200", id="chinese-amount"),
        pytest.param("nflx 71 买一千五刀", "一千五刀", "1500", id="chinese-thousands"),
    ],
)
async def test_a_dollar_size_buys_that_amount(post, words, amount):
    reading = trade(dollar_buy(post, amount, words))

    result = await transform(raw(post), Route(), FakeDecoder(reading), "test")

    assert result.decision == "trade"
    [instruction] = result.instructions
    assert (instruction.usd_amount, instruction.fraction) == (Decimal(amount), None)
    assert result.evidence[0].usd_amount_evidence == words


@pytest.mark.parametrize(
    ("post", "words", "amount"),
    [
        pytest.param("buy 200$ of nflx at 71", "200$ of", "300", id="another-amount"),
        pytest.param("buy 200$ of nflx at 71", "nflx", "200", id="words-without-an-amount"),
        pytest.param("buy nflx at $71", "$71", "71", id="a-price-is-not-a-size"),
    ],
)
def test_a_dollar_size_must_be_the_posts_amount(post, words, amount):
    reading = trade(dollar_buy(post, amount, words))

    assert grounding_code(post, reading) == "dollars_not_grounded"


@pytest.mark.parametrize(
    "post", ["buy 200$ of nflx at 71", "buy $200 of nflx at 71", "buy nflx 200 dollars at 71"]
)
def test_the_reader_cannot_drop_a_dollar_size(post):
    reading = trade(buy("NFLX", "71", said="buy", ticker_said="nflx"))

    assert grounding_code(post, reading) == "source_dollars_omitted"


def test_a_dollar_sign_on_the_price_is_no_size():
    reading = trade(buy("NFLX", "71", said="buy", ticker_said="nflx"))

    check_reading(reading, "buy nflx at $71", Route())


async def test_a_fraction_still_sizes_as_a_share():
    reading = trade(
        buy("NFLX", "73", said="Buy", ticker_said="NFLX", fraction=SIXTH, fraction_said="1/6")
    )

    result = await transform(raw("Buy 1/6 of NFLX at 73"), Route(), FakeDecoder(reading), "test")

    assert result.instructions[0].usd_amount is None
    assert result.instructions[0].fraction == Decimal(SIXTH)
