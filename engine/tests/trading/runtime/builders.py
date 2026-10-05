"""Configurations, secrets, and waits the runtime tests build on."""

import asyncio

from copytrading_engine.trading.domain.config import TradingConfiguration, TradingSecrets
from copytrading_engine.trading.domain.profiles import ProfileBuilder, ProfileDraft
from copytrading_engine.trading.entrypoints.runtime import TradingRuntime

# The account's default maximum per stock, which is its guru's full position (ADR-0007).
FULL_POSITION_USD = "600"
ACCOUNTS = ("first", "second", "third")


def channel(account_id: str) -> str:
    """One guru per account: the guru for "first" posts on 123, for "second" on 124, and so on."""
    return str(123 + ACCOUNTS.index(account_id))


def connection(account_id: str, *, full_position_usd: str = FULL_POSITION_USD) -> dict:
    return {"account_id": account_id, "full_position_usd": full_position_usd}


def guru(account_id: str):
    return ProfileBuilder().build(
        ProfileDraft(
            guru_id=f"{account_id}-guru",
            display_name=f"{account_id.title()} Guru",
            prefix="ALERT:",
            playbook="",
            examples=(),
            exit_basis="original_position",
        )
    )


def route(account_id: str, channel_id: str) -> dict:
    profile = guru(account_id)
    return {
        "channel_id": channel_id,
        "author_id": None,
        "guru_id": profile.guru_id,
        "profile_revision": profile.profile_revision,
        "connections": [connection(account_id)],
    }


def trading_configuration(*accounts: str, policy: dict | None = None):
    accounts = accounts or ("first", "second")
    account_policy = {} if policy is None else {"policy": policy}
    return TradingConfiguration.model_validate(
        {
            "version": 5,
            "source": {"channel_ids": [channel(account) for account in accounts]},
            "provider": {"name": "anthropic", "model": "test-model"},
            "accounts": [
                {"id": account, "environment": "paper", **account_policy} for account in accounts
            ],
            "profiles": [guru(account).model_dump(mode="json") for account in accounts],
            "routes": [route(account, channel(account)) for account in accounts],
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
