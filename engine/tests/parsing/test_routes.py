"""Routes are frozen copies the worker cannot see change."""

from collections.abc import MutableMapping
from operator import setitem
from typing import cast

import pytest

from copytrading_engine.parsing.routes import Route, freeze_routes


def test_route_is_immutable():
    route = Route(prefix="ALERT:", playbook="苹果 means AAPL")
    with pytest.raises(AttributeError):
        route.playbook = "苹果 means MSFT"  # type: ignore[misc]


def test_freeze_routes_copies_the_outer_mapping():
    routes = {"discord:demo": Route(playbook="苹果 means AAPL")}
    frozen = freeze_routes(routes)

    routes["discord:other"] = Route(prefix="ALERT:")

    assert frozen["discord:demo"].playbook == "苹果 means AAPL"
    assert set(frozen) == {"discord:demo"}
    with pytest.raises(TypeError):
        setitem(cast(MutableMapping[str, Route], frozen), "discord:demo", Route())


def test_worker_freezes_caller_supplied_route_mapping():
    from copytrading_engine.parsing.extraction import Decoder
    from copytrading_engine.parsing.worker import ExtractionStore, ParseWorker

    routes = {"discord:demo": Route(playbook="苹果 means AAPL")}
    worker = ParseWorker(cast(ExtractionStore, object()), cast(Decoder, object()), routes, "test")

    routes["discord:other"] = Route(prefix="ALERT:")

    assert worker.routes["discord:demo"].playbook == "苹果 means AAPL"
    assert set(worker.routes) == {"discord:demo"}
    with pytest.raises(TypeError):
        setitem(
            cast(MutableMapping[str, Route], worker.routes),
            "discord:other",
            Route(),
        )
