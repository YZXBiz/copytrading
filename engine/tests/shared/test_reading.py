"""Every guru's post is read into one shape, and a reading that makes no sense cannot be built."""

from decimal import Decimal

import pytest
from pydantic import TypeAdapter, ValidationError

from copytrading_engine.shared.reading import (
    Batch,
    Buy,
    Commentary,
    Conditional,
    Exact,
    Fraction,
    Lot,
    NotGiven,
    NotSaid,
    PostReading,
    Range,
    Sell,
    Suggestion,
    TradeMade,
)

READING = TypeAdapter(PostReading)


def read(value: dict) -> object:
    return READING.validate_python(value)


ZHAO_SELL_HALF = {
    "kind": "trade_made",
    "summary": "Sold half of the IREN bought at 39.5, at 41.27.",
    "calls": [
        {
            "action": "sell",
            "action_words": "出一半",
            "stock": {"ticker": "IREN", "words": "iren"},
            "price": {"kind": "exact", "value": "41.27", "words": "41.27"},
            "share": {"kind": "fraction", "value": "0.5", "words": "一半"},
            "counts_from": "original",
            "sell_from": {"kind": "lot", "buy_price": "39.5", "words": "39.5"},
        }
    ],
}


def test_zhao_sells_half_of_a_named_lot():
    reading = read(ZHAO_SELL_HALF)

    assert isinstance(reading, TradeMade)
    [sell] = reading.calls
    assert isinstance(sell, Sell)
    assert sell.price == Exact(value=Decimal("41.27"), words="41.27")
    assert sell.share == Fraction(value=Decimal("0.5"), words="一半")
    assert sell.sell_from == Lot(buy_price=Decimal("39.5"), words="39.5")


def test_a_sell_that_names_no_buy_says_so():
    reading = read(
        {
            "kind": "trade_made",
            "summary": "Sold all RCL at 260.",
            "calls": [
                {
                    "action": "sell",
                    "action_words": "跑路了",
                    "stock": {"ticker": "RCL", "words": "Rcl"},
                    "price": {"kind": "exact", "value": "260", "words": "260"},
                    "share": {"kind": "all", "words": "跑路了"},
                    "sell_from": {"kind": "not_said"},
                }
            ],
        }
    )

    [sell] = reading.calls
    assert sell.sell_from == NotSaid()
    assert sell.counts_from is None


def test_a_zone_is_a_suggestion_with_a_range_and_no_size():
    reading = read(
        {
            "kind": "suggestion",
            "summary": "Build a CBRS position between 160 and 179.",
            "calls": [
                {
                    "action": "buy",
                    "action_words": "建仓",
                    "stock": {"ticker": "CBRS", "words": "Cbrs"},
                    "price": {
                        "kind": "range",
                        "low": "160",
                        "high": "179",
                        "low_words": "160",
                        "high_words": "179",
                    },
                    "size": {"kind": "not_given"},
                }
            ],
        }
    )

    assert isinstance(reading, Suggestion)
    [buy] = reading.calls
    assert isinstance(buy, Buy)
    assert isinstance(buy.price, Range)
    assert buy.size == NotGiven()


def test_a_conditional_keeps_its_condition_and_batch():
    reading = read(
        {
            "kind": "conditional",
            "summary": "Would buy a first batch of SCO if it is under 20 tomorrow.",
            "condition": "如果明天20以下",
            "calls": [
                {
                    "action": "buy",
                    "action_words": "我会买",
                    "stock": {"ticker": "SCO", "words": "Sco"},
                    "price": {"kind": "not_given"},
                    "size": {"kind": "batch", "number": 1, "words": "第一批"},
                }
            ],
        }
    )

    assert isinstance(reading, Conditional)
    assert reading.calls[0].size == Batch(number=1, words="第一批")


def test_commentary_has_nothing_to_trade():
    reading = read({"kind": "commentary", "summary": "TSLA 373 is still resistance today."})

    assert isinstance(reading, Commentary)


@pytest.mark.parametrize(
    ("label", "change"),
    [
        ("commentary cannot carry calls", {"kind": "commentary"}),
        ("a trade needs at least one call", {"calls": []}),
        ("an unknown kind", {"kind": "rumour"}),
    ],
)
def test_readings_that_make_no_sense_cannot_be_built(label, change):
    with pytest.raises(ValidationError):
        read(ZHAO_SELL_HALF | change)


def _sell(**fields) -> dict:
    return ZHAO_SELL_HALF | {"calls": [ZHAO_SELL_HALF["calls"][0] | fields]}


@pytest.mark.parametrize(
    ("label", "fields"),
    [
        (
            "an exact price and a range at once",
            {"price": {"kind": "exact", "value": "1", "words": "1", "low": "1"}},
        ),
        (
            "a range from high to low",
            {
                "price": {
                    "kind": "range",
                    "low": "9",
                    "high": "8",
                    "low_words": "9",
                    "high_words": "8",
                }
            },
        ),
        ("a price without the post's words", {"price": {"kind": "exact", "value": "41.27"}}),
        ("a share over one whole", {"share": {"kind": "fraction", "value": "1.5", "words": "x"}}),
        ("a sell sized by a batch", {"share": {"kind": "batch", "number": 2, "words": "第二批"}}),
        ("a lowercase ticker", {"stock": {"ticker": "iren", "words": "iren"}}),
        ("a field the contract does not have", {"confidence": "high"}),
    ],
)
def test_calls_that_make_no_sense_cannot_be_built(label, fields):
    with pytest.raises(ValidationError):
        read(_sell(**fields))


def test_the_model_is_given_one_tagged_schema():
    schema = READING.json_schema()

    assert set(schema["discriminator"]["mapping"]) == {
        "trade_made",
        "instruction",
        "conditional",
        "suggestion",
        "commentary",
        "unclear",
    }
