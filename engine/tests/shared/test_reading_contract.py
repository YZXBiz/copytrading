"""The app decodes these readings for Activity's "Read as"; the engine must write exactly them."""

import json
from decimal import Decimal

from pydantic import TypeAdapter

from copytrading_engine.shared.reading import (
    AtMarket,
    Batch,
    Buy,
    Commentary,
    Conditional,
    Exact,
    NotGiven,
    PostReading,
    Range,
    Stock,
    Suggestion,
    Unclear,
)

from ..contracts import CONTRACTS
from ..readings import buy, sell, trade

READINGS = TypeAdapter(list[PostReading])


def examples() -> list:
    sco = Stock(ticker="SCO", words="Sco")
    return [
        trade(
            sell(
                "IREN",
                "41.27",
                bought_at="39.5",
                said="出一半",
                fraction="0.5",
                fraction_said="一半",
            ),
            summary="Sold half of the IREN bought at 39.5",
        ),
        trade(
            buy("SOUN", "5.85", fraction=str(Decimal(1) / 6), fraction_said="6分之一"),
            summary="Bought a sixth of SOUN",
        ),
        trade(sell("RCL", "260", bought_at=None, said="跑路了"), summary="Sold all RCL"),
        Suggestion(
            summary="Build CBRS between 160 and 179",
            calls=(
                Buy(
                    action_words="建仓",
                    stock=Stock(ticker="CBRS", words="Cbrs"),
                    price=Range(low=160, high=179, low_words="160", high_words="179"),
                    size=NotGiven(),
                ),
            ),
        ),
        Conditional(
            summary="Buys a first batch of SCO under 20",
            condition="如果明天20以下",
            calls=(
                Buy(
                    action_words="我会买",
                    stock=sco,
                    price=Exact(value=20, words="20"),
                    size=Batch(number=1, words="第一批"),
                ),
            ),
        ),
        trade(
            Buy(action_words="现价买", stock=sco, price=AtMarket(words="现价"), size=NotGiven()),
            summary="Buy SCO at the market",
        ),
        Commentary(summary="TSLA 373 is still resistance today"),
        Unclear(summary="Cannot tell"),
    ]


def test_the_engine_writes_the_readings_the_app_decodes():
    written = json.loads(READINGS.dump_json(examples()))

    expected = json.loads((CONTRACTS / "post-readings.json").read_text())

    assert written == expected, "post-readings.json is out of date with the engine's reading"
