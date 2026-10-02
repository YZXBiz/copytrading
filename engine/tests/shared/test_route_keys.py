"""One rule picks a message's route, so parsing and delivery never disagree about it."""

from copytrading_engine.shared.route_keys import AMBIGUOUS_SOURCE_PROFILE, choose_route, route_key


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
