"""Active routes keep guru identity separate from Discord message identity."""

import pytest
from pydantic import ValidationError

from copytrading_engine.trading.domain.profiles import ProfileBuilder, ProfileDraft


def _profile(guru_id: str, prefix: str):
    return ProfileBuilder().build(
        ProfileDraft(
            guru_id=guru_id,
            display_name=guru_id,
            prefix=prefix,
            playbook="",
            examples=(),
            exit_basis="original_position",
        )
    )


def _route(profile, account_id: str, author_id: str | None):
    return {
        "channel_id": "123",
        "author_id": author_id,
        "guru_id": profile.guru_id,
        "profile_revision": profile.profile_revision,
        "connections": [{"account_id": account_id, "mode": "fixed", "amount_usd": "100"}],
    }


def _configuration(routes):
    profile_list = (_profile("guru-a", "ALERT:"), _profile("guru-b", "SIGNAL:"))
    return {
        "version": 4,
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
            prefix="ALERT:",
            playbook="",
            examples=(),
            exit_basis="original_position",
        )
    )
    raw = _configuration(lambda _: [_route(profile, "paper-a", "100")])
    stale = profile.model_dump(mode="json") | {"aliases": [{"phrase": "苹果", "symbol": "AAPL"}]}
    raw["profiles"] = [stale]

    with pytest.raises(ValidationError):
        TradingConfiguration.model_validate(raw)
