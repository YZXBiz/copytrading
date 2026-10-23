"""One rule picks a message's route, so parsing and delivery never disagree about it."""

from copytrading_engine.shared.route_keys import (
    AMBIGUOUS_SOURCE_PROFILE,
    choose_route,
    guru_for_channel,
    route_key,
)
from copytrading_engine.shared.signals import StockSignal


def test_the_channel_names_its_guru_in_every_setup() -> None:
    """The same ID in Swift (GuruIdentity); a setup made again gives the guru the same one."""
    assert guru_for_channel("discord", "1517754775674949742") == "guru-3909e2aa"
    assert guru_for_channel("discord", "123") == "guru-be6f68ea"


def test_a_post_belongs_to_its_channels_guru_whatever_id_it_was_read_with() -> None:
    """Posts read under a setup whose guru had a made-up ID still show under that guru."""
    read = StockSignal(
        source="discord",
        channel_id="1517754775674949742",
        id="1562741036357263371",
        timestamp="2026-10-22T08:14:57+00:00",
        text="92.3加了6分之一常规仓soxl",
        parser_profile="stock-extraction-v2",
        model="test",
        guru_id="guru-445d352c",
        profile_revision="0" * 64,
        decision="ignore",
        reason="test",
        instructions=(),
        evidence=(),
    )

    assert read.guru == "guru-3909e2aa"
    assert read.model_copy(update={"guru_id": None, "profile_revision": None}).guru is None


def test_a_route_is_bound_to_an_author_or_to_the_whole_channel() -> None:
    assert route_key("discord", "123", "999") == "discord:123:999"
    assert route_key("discord", "123", None) == "discord:123:*"


def test_the_channel_route_serves_any_author() -> None:
    routes = {"discord:123:*": "channel"}
    assert choose_route(routes, "discord", "123", "999").route == "channel"
    assert choose_route(routes, "discord", "123", None).route == "channel"


def test_an_author_route_serves_only_that_author() -> None:
    routes = {"discord:123:999": "author"}
    assert choose_route(routes, "discord", "123", "999").route == "author"
    assert choose_route(routes, "discord", "123", "111").route is None
    assert choose_route(routes, "discord", "123", None).route is None


def test_a_channel_and_an_author_route_for_one_author_is_ambiguous() -> None:
    routes = {"discord:123:999": "author", "discord:123:*": "channel"}
    choice = choose_route(routes, "discord", "123", "999")
    assert (choice.route, choice.error) == (None, AMBIGUOUS_SOURCE_PROFILE)
    assert choose_route(routes, "discord", "123", "111").route == "channel"


def test_another_channel_has_no_route() -> None:
    assert choose_route({"discord:123:*": "channel"}, "discord", "456", "999").route is None
