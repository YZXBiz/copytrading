"""The model check's one post: the reader must answer it as nothing to trade."""

import pytest

from copytrading_engine.parsing.extraction import Answer
from copytrading_engine.parsing.readiness import ModelReadiness, probe_model
from copytrading_engine.parsing.routes import Route
from copytrading_engine.shared.reading import Chatter, Commentary, PostReading, Unclear


class _Reads:
    def __init__(self, reading: PostReading) -> None:
        self.reading = reading

    async def answer(self, text: str, route: Route, recent=()) -> Answer:
        return Answer(self.reading)


@pytest.mark.parametrize("reading", [Commentary(summary="Market talk"), Chatter()])
async def test_nothing_to_trade_passes_the_model_check(reading):
    health = ModelReadiness()

    await probe_model(_Reads(reading), health)

    assert (health.ready, health.error) == (True, None)


async def test_a_post_it_cannot_place_fails_the_model_check():
    health = ModelReadiness()

    await probe_model(_Reads(Unclear(summary="?")), health)

    assert (health.ready, health.error) == (False, "unexpected_probe_output")
