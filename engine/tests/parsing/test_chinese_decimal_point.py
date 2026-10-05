"""A Chinese keyboard types the decimal point as a full stop: "381。3" is 381.3."""

import pytest

from copytrading_engine.parsing.application import transform
from copytrading_engine.parsing.extraction import Route, normalize

from ..readings import sell, trade
from .builders import raw
from .fakes import FakeDecoder


@pytest.mark.parametrize(
    ("post", "reads"),
    [
        ("386.2出一半381。3的gld", "386.2出一半381.3的gld"),
        ("16 。1出一半15.85的cifr", "16.1出一半15.85的cifr"),
        ("198.8出剩下一半191｡5的coin", "198.8出剩下一半191.5的coin"),
        # A full stop that ends a sentence is not a decimal point.
        ("今天出完了。3点再看", "今天出完了。3点再看"),
        ("买了5股。明天再说", "买了5股。明天再说"),
    ],
)
def test_a_full_stop_between_digits_is_a_decimal_point(post, reads):
    assert normalize(post) == reads


async def test_a_sell_naming_its_lot_with_a_full_stop_passes_the_evidence_checks():
    reading = trade(
        sell("GLD", "386.2", bought_at="381.3", said="出", fraction="0.5", fraction_said="一半")
    )

    result = await transform(
        raw("386.2出一半381。3的gld"), Route(), FakeDecoder(reading), "fixture"
    )

    [sell_call] = result.instructions
    assert (sell_call.action, str(sell_call.price), str(sell_call.entry_price)) == (
        "reduce",
        "386.2",
        "381.3",
    )
