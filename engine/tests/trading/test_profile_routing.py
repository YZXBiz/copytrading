"""Active routes keep guru identity separate from Discord message identity."""

import pytest
from pydantic import ValidationError

from copytrading_engine.trading.domain.config import TradingConfiguration
from copytrading_engine.trading.domain.profiles import ProfileBuilder, ProfileDraft


def _profile(guru_id: str, prefix: str):
    return ProfileBuilder().build(
        ProfileDraft(
            guru_id=guru_id,
            display_name=guru_id,
            playbook="",
            examples=(),
        )
    )


def _route(profile, account_id: str, author_id: str | None):
    return {
        "channel_id": "123",
        "author_id": author_id,
        "guru_id": profile.guru_id,
        "profile_revision": profile.profile_revision,
        "connections": [{"account_id": account_id, "full_position_usd": "600"}],
    }


def _configuration(routes):
    profile_list = (_profile("guru-a", "ALERT:"), _profile("guru-b", "SIGNAL:"))
    return {
        "version": 8,
        "source": {"channel_ids": ["123"]},
        "provider": {"name": "anthropic", "model": "test-model"},
        "accounts": [
            {"id": "paper-a", "environment": "paper"},
            {"id": "paper-b", "environment": "paper"},
        ],
        "profiles": [item.model_dump(mode="json") for item in profile_list],
        "routes": routes(profile_list),
    }


def test_same_channel_can_bind_distinct_authors_to_distinct_gurus():
    from copytrading_engine.trading.domain.config import TradingConfiguration

    raw = _configuration(
        lambda profiles: [
            _route(profile, account_id, author_id)
            for profile, account_id, author_id in zip(
                profiles,
                ("paper-a", "paper-b"),
                ("100", "200"),
                strict=True,
            )
        ]
    )
    configuration = TradingConfiguration.model_validate(raw)

    assert {(route.author_id, route.guru_id) for route in configuration.routes} == {
        ("100", "guru-a"),
        ("200", "guru-b"),
    }


@pytest.mark.parametrize("author_ids", [(None, "100"), ("100", "100")])
def test_channel_collision_never_silently_selects_a_profile(author_ids):
    from copytrading_engine.trading.domain.config import TradingConfiguration

    raw = _configuration(
        lambda profiles: [
            _route(profile, account_id, author_id)
            for profile, account_id, author_id in zip(
                profiles,
                ("paper-a", "paper-b"),
                author_ids,
                strict=True,
            )
        ]
    )

    with pytest.raises(ValidationError):
        TradingConfiguration.model_validate(raw)


def test_configuration_with_removed_alias_fields_is_rejected():
    from copytrading_engine.trading.domain.config import TradingConfiguration

    profile = ProfileBuilder().build(
        ProfileDraft(
            guru_id="guru-a",
            display_name="Guru A",
            playbook="",
            examples=(),
        )
    )
    raw = _configuration(lambda _: [_route(profile, "paper-a", "100")])
    stale = profile.model_dump(mode="json") | {"aliases": [{"phrase": "苹果", "symbol": "AAPL"}]}
    raw["profiles"] = [stale]

    with pytest.raises(ValidationError):
        TradingConfiguration.model_validate(raw)


def _two_gurus(accounts=("paper-a", "paper-b"), full_position="600"):
    return _configuration(
        lambda profiles: [
            {
                **_route(profile, account_id, author_id),
                "connections": [{"account_id": account_id, "full_position_usd": full_position}],
            }
            for profile, account_id, author_id in zip(
                profiles, accounts, ("100", "200"), strict=True
            )
        ]
    )


@pytest.mark.parametrize(
    ("change", "problem"),
    [
        pytest.param(
            lambda raw: raw["routes"][1].update(
                guru_id=raw["routes"][0]["guru_id"],
                profile_revision=raw["routes"][0]["profile_revision"],
            ),
            "a guru copies into one account",
            id="one-guru-in-two-routes",
        ),
        pytest.param(
            lambda raw: raw["routes"][0]["connections"].append(
                {"account_id": "paper-b", "full_position_usd": "600"}
            ),
            "exactly one account",
            id="one-guru-into-two-accounts",
        ),
        pytest.param(
            lambda raw: raw["routes"][1]["connections"][0].update(account_id="paper-a"),
            "an account copies one guru",
            id="two-gurus-into-one-account",
        ),
        pytest.param(
            lambda raw: raw["routes"][0]["connections"][0].update(full_position_usd="100"),
            "maximum per stock",
            id="full-position-differs-from-the-maximum-per-stock",
        ),
    ],
)
def test_one_guru_copies_into_one_account_at_its_maximum_per_stock(change, problem):
    from copytrading_engine.trading.domain.config import TradingConfiguration

    raw = _two_gurus()
    TradingConfiguration.model_validate(raw)
    change(raw)

    with pytest.raises(ValidationError, match=problem):
        TradingConfiguration.model_validate(raw)


@pytest.mark.parametrize(("value", "expected"), [(None, None), (1, 1), (1440, 1440)])
def test_a_guru_repeat_window_is_off_or_a_number_of_minutes(value, expected):
    def routes(profiles):
        return [_route(profiles[0], "paper-a", None) | {"repeat_window_minutes": value}]

    [route] = TradingConfiguration.model_validate(_configuration(routes)).routes
    assert route.repeat_window_minutes == expected


def test_a_saved_route_without_a_repeat_window_checks_ten_minutes():
    [route] = TradingConfiguration.model_validate(
        _configuration(lambda profiles: [_route(profiles[0], "paper-a", None)])
    ).routes
    assert route.repeat_window_minutes == 10


@pytest.mark.parametrize("value", [0, -5, 1441, "ten"])
def test_a_repeat_window_outside_one_minute_to_a_day_is_refused(value):
    def routes(profiles):
        return [_route(profiles[0], "paper-a", None) | {"repeat_window_minutes": value}]

    with pytest.raises(ValidationError):
        TradingConfiguration.model_validate(_configuration(routes))
