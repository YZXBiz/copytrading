"""Configurations, secrets, and waits the runtime tests build on."""

import asyncio

from copytrading_engine.trading.domain.config import TradingConfiguration, TradingSecrets
from copytrading_engine.trading.domain.profiles import ProfileBuilder, ProfileDraft
from copytrading_engine.trading.entrypoints.runtime import TradingRuntime


def connection(account_id: str, *, mode: str = "fixed", amount_usd: str = "100") -> dict:
    return {"account_id": account_id, "mode": mode, "amount_usd": amount_usd}


def trading_configuration():
    profile = ProfileBuilder().build(
        ProfileDraft(
            guru_id="default-guru",
            display_name="Default Guru",
            prefix="ALERT:",
            playbook="",
            examples=(),
            exit_basis="original_position",
        )
    )
    return TradingConfiguration.model_validate(
        {
            "version": 4,
            "source": {"channel_ids": ["123"]},
            "provider": {"name": "anthropic", "model": "test-model"},
            "accounts": [
                {"id": "first", "environment": "paper"},
                {"id": "second", "environment": "paper"},
            ],
            "profiles": [profile.model_dump(mode="json")],
            "routes": [
                {
                    "channel_id": "123",
                    "author_id": None,
                    "guru_id": profile.guru_id,
                    "profile_revision": profile.profile_revision,
                    "connections": [connection("first"), connection("second")],
                }
            ],
        }
    )


def trading_secrets():
    return TradingSecrets.model_validate(
        {
            "discord_token": "discord-secret",
            "provider_api_key": "provider-secret",
            "brokers": [
                {"account_id": "first", "key": "first-key", "secret": "first-secret"},
                {"account_id": "second", "key": "second-key", "secret": "second-secret"},
            ],
        }
    )


async def wait_for(runtime: TradingRuntime, predicate):
    for _ in range(80):
        status = runtime.status()
        if predicate(status):
            return status
        await asyncio.sleep(0.05)
    raise AssertionError(f"runtime did not reach expected state: {runtime.status()}")


def trading_secrets_for(*account_ids: str) -> TradingSecrets:
    return TradingSecrets.model_validate(
        {
            "discord_token": "discord-secret",
            "provider_api_key": "provider-secret",
            "brokers": [
                {"account_id": account_id, "key": f"{account_id}-key", "secret": "secret"}
                for account_id in account_ids
            ],
        }
    )


async def wait_for_value(predicate):
    for _ in range(80):
        if predicate():
            return
        await asyncio.sleep(0.01)
    raise AssertionError("condition was not reached")
