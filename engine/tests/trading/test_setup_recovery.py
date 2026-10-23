"""What an account does after a restart is a setup choice, copied with the account's limits."""

import json

import pytest
from pydantic import ValidationError

from copytrading_engine.backup.configuration import read_configuration_identities
from copytrading_engine.backup.manifest import BackupManifestError
from copytrading_engine.trading.domain.config import TradingConfiguration
from copytrading_engine.trading.domain.profiles import ProfileBuilder, ProfileDraft
from copytrading_engine.trading.entrypoints.runtime import copy_config


def _raw(version: int = 10, recovery: str | None = "automatic") -> dict:
    profile = ProfileBuilder().build(
        ProfileDraft(guru_id="guru-a", display_name="Zhao", playbook="")
    )
    policy = {"max_symbol_usd": "600"}
    if recovery is not None:
        policy["recovery_preference"] = recovery
    return {
        "version": version,
        "source": {"channel_ids": ["123"]},
        "provider": {"name": "anthropic", "model": "test-model"},
        "accounts": [{"id": "paper", "environment": "paper", "policy": policy}],
        "profiles": [profile.model_dump(mode="json")],
        "routes": [
            {
                "channel_id": "123",
                "guru_id": profile.guru_id,
                "profile_revision": profile.profile_revision,
                "connections": [{"account_id": "paper", "full_position_usd": "600"}],
            }
        ],
    }


def test_the_setup_chooses_recovery_and_the_account_copies_with_it():
    configuration = TradingConfiguration.model_validate(_raw())
    assert configuration.accounts[0].policy.recovery_preference == "automatic"
    assert copy_config(configuration, "paper").recovery_preference == "automatic"


def test_an_account_without_a_choice_waits_for_the_owner():
    configuration = TradingConfiguration.model_validate(_raw(recovery=None))
    assert copy_config(configuration, "paper").recovery_preference == "manual"


def test_changing_recovery_is_a_limits_change_that_keeps_routing():
    manual = TradingConfiguration.model_validate(_raw(recovery="manual"))
    automatic = TradingConfiguration.model_validate(_raw(recovery="automatic"))
    assert manual.routing_revision() == automatic.routing_revision()
    assert manual.revision() != automatic.revision()


def test_an_earlier_setup_is_upgraded_by_the_app_never_read_by_the_engine():
    with pytest.raises(ValidationError):
        TradingConfiguration.model_validate(_raw(version=9))


def _saved(version: int) -> bytes:
    return json.dumps(
        {"version": 1, "configuration": _raw(version=version), "revision": "a" * 64}
    ).encode()


@pytest.mark.parametrize("version", [8, 9, 10])
def test_a_backup_of_this_or_the_last_setup_version_restores(version):
    assert read_configuration_identities(_saved(version)) == ("paper:paper",)


def test_a_backup_from_before_upgrades_existed_is_refused():
    with pytest.raises(BackupManifestError):
        read_configuration_identities(_saved(7))
