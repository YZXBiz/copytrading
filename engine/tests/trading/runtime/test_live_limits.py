"""Changed account limits reach the copying in progress without a pause, and stay after it."""

import asyncio
from decimal import Decimal
from uuid import uuid4

import pytest

from copytrading_engine.trading.domain.config import TradingConfiguration
from copytrading_engine.trading.entrypoints.factories import TradingFactories
from copytrading_engine.trading.entrypoints.runtime import TradingRuntime

from .builders import trading_configuration, trading_secrets, wait_for
from .fakes import Decoder, Owner, Session


def _runtime(tmp_path, owners: dict[str, Owner]) -> TradingRuntime:
    async def owner_factory(path, credentials, policy, environment):
        owner = Owner(path, {}, {})
        owner.opened_with = policy
        owners[path.name] = owner
        return owner

    return TradingRuntime(
        tmp_path,
        factories=TradingFactories(
            owner=owner_factory,
            decoder=lambda name, config: asyncio.sleep(0, result=Decoder()),
            session=lambda source, channels, authors, stop, report: Session(source, None),
        ),
    )


def _with_policy(configuration: TradingConfiguration, account_id: str, **policy):
    changed = configuration.model_dump(mode="json")
    for account in changed["accounts"]:
        if account["id"] == account_id:
            account["policy"] |= policy
    return TradingConfiguration.model_validate(changed)


async def test_changed_limits_reach_the_running_account_without_a_pause(tmp_path):
    owners: dict[str, Owner] = {}
    runtime = _runtime(tmp_path, owners)
    activation_id = str(uuid4())
    original = trading_configuration()
    await runtime.start(original, trading_secrets(), activation_id)
    await wait_for(runtime, lambda status: status.state == "running")
    changed = _with_policy(original, "first", max_order_usd="500", max_signal_age_seconds=300)

    revision = await runtime.update_account_limits(changed)

    assert revision == changed.revision() != original.revision()
    assert owners["first"].opened_with.max_order_usd == Decimal("100")
    assert owners["first"].configs[-1].max_order_usd == Decimal("500")
    assert not owners["first"].stopped
    assert not owners["second"].stopped
    assert runtime.status().state == "running"
    assert runtime._worker is not None
    assert runtime._worker.max_age == 300
    assert runtime.activation_status(activation_id).candidate_revision == revision
    await runtime.shutdown()

    # A restart reads the same revision, and Start with the new limits strands no queued work.
    restarted = _runtime(tmp_path, owners)
    assert restarted.activation_status(activation_id).candidate_revision == revision
    await restarted.start(changed, trading_secrets())
    await wait_for(restarted, lambda status: status.state == "running")
    assert owners["first"].opened_with.max_order_usd == Decimal("500")
    await restarted.shutdown()


async def test_a_change_beyond_limits_is_refused_while_copying(tmp_path):
    owners: dict[str, Owner] = {}
    runtime = _runtime(tmp_path, owners)
    original = trading_configuration()
    await runtime.start(original, trading_secrets())
    await wait_for(runtime, lambda status: status.state == "running")
    changed = original.model_dump(mode="json")
    changed["provider"]["model"] = "other-model"

    with pytest.raises(ValueError, match="Only account limits"):
        await runtime.update_account_limits(TradingConfiguration.model_validate(changed))

    assert owners["first"].configs == []
    assert owners["second"].configs == []
    await runtime.shutdown()


async def test_limits_changed_while_paused_wait_for_the_next_start(tmp_path):
    runtime = _runtime(tmp_path, {})
    changed = _with_policy(trading_configuration(), "first", max_order_usd="500")

    assert await runtime.update_account_limits(changed) == changed.revision()
    assert runtime.status().state == "paused"
