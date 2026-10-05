"""The runtime starts, fences, restarts, and shuts down without losing owned work."""

import asyncio
import datetime as dt
import sqlite3
from contextlib import asynccontextmanager

import pytest

from copytrading_engine.parsing.sqlite import SQLiteExtractionStore
from copytrading_engine.shared.raw_message import RawMessage
from copytrading_engine.sources.sqlite import SQLiteSourceStore
from copytrading_engine.trading.adapters.routing import (
    AccountOwnershipPending,
    RoutingChangePending,
    RoutingRevision,
)
from copytrading_engine.trading.domain.config import TradingConfiguration
from copytrading_engine.trading.entrypoints.factories import TradingFactories
from copytrading_engine.trading.entrypoints.runtime import TradingRuntime

from .builders import (
    channel,
    connection,
    trading_configuration,
    trading_secrets,
    trading_secrets_for,
    wait_for,
    wait_for_value,
)
from .fakes import Decoder, Owner, Session


async def test_maintenance_fence_drains_runtime_before_yield_and_blocks_start(tmp_path):
    owners: list[Owner] = []
    decoder_created = asyncio.Event()

    async def owner_factory(path, credentials, policy, environment):
        owner = Owner(path, {}, {})
        owners.append(owner)
        return owner

    async def decoder_factory(name, config):
        decoder_created.set()
        return Decoder()

    factories = TradingFactories(
        owner=owner_factory,
        decoder=decoder_factory,
        session=lambda source, channels, authors, stop, report: Session(source, None),
    )
    runtime = TradingRuntime(tmp_path, factories=factories)
    await runtime.start(trading_configuration(), trading_secrets())
    await decoder_created.wait()

    @asynccontextmanager
    async def hold_fence():
        async with runtime.maintenance_fence():
            with pytest.raises(ValueError, match="maintenance"):
                await runtime.start(trading_configuration(), trading_secrets())
            yield

    async with hold_fence():
        assert runtime.status().state == "paused"
        assert len(owners) == 2
        assert all(owner.closed for owner in owners)

    assert runtime.status().state == "paused"
    assert all(owner.closed for owner in owners)
    await runtime.shutdown()


async def test_a_post_for_an_account_that_failed_to_open_is_delivered_after_restart(tmp_path):
    event = RawMessage(
        schema_version=1,
        event_type="raw_message",
        source="discord",
        channel_id=channel("second"),
        id="456",
        timestamp=dt.datetime.now(dt.UTC),
        text="ALERT: Bought AAPL at 200",
    )
    fail_once = {"second": 1}
    attempts: dict[str, int] = {}
    opened: dict[str, Owner] = {}

    async def owner_factory(path, credentials, policy, environment):
        assert environment == "paper"
        assert policy.sources == ("discord:123", "discord:124")
        assert credentials.key.get_secret_value().endswith("-key")
        owner = Owner(path, fail_once, attempts)
        opened[path.name] = owner
        return owner

    async def decoder_factory(name, config):
        assert name == "anthropic"
        assert config.api_key.get_secret_value() == "provider-secret"
        return Decoder()

    def session_factory(source, channels, authors, stop, report_failure):
        assert channels == {123, 124}
        assert authors is None
        return Session(source, event)

    factories = TradingFactories(
        owner=owner_factory, decoder=decoder_factory, session=session_factory
    )
    runtime = TradingRuntime(tmp_path, factories=factories)
    assert runtime.status().state == "paused"
    assert not (tmp_path / "accounts").exists()

    await runtime.start(trading_configuration(), trading_secrets())
    degraded = await wait_for(
        runtime,
        lambda status: (
            status.state == "degraded"
            and any(account.state == "failed" for account in status.accounts)
        ),
    )
    assert degraded.error_code == "account_unavailable"
    assert degraded.active_accounts == 1
    assert opened["first"].stopped is False
    await wait_for(runtime, lambda status: status.pending_signals >= 1)
    await wait_for(runtime, lambda status: opened["first"].cycles >= 2)
    db = sqlite3.connect(tmp_path / "application.db")
    assert db.execute("SELECT delivered_at FROM parser_signal_deliveries").fetchone() == (None,)
    db.close()
    await runtime.shutdown()

    await runtime.start(trading_configuration(), trading_secrets())
    running = await wait_for(
        runtime,
        lambda status: status.processed_signals == 1 and status.pending_signals == 0,
    )
    assert running.state == "running"
    await runtime.shutdown()
    assert runtime.status().state == "paused"
    assert attempts["second"] == 2
    # One guru per account: the post was only ever for "second".
    assert opened["first"].deliveries == []
    [accepted] = opened["second"].deliveries
    assert accepted.signal.guru_id == accepted.terms.guru_id == "second-guru"
    assert accepted.terms.profile_revision == accepted.signal.profile_revision
    receipt = sqlite3.connect(tmp_path / "accounts" / "second" / "fake-receipts.sqlite3")
    assert receipt.execute("SELECT count(*) FROM receipts").fetchone() == (1,)
    receipt.close()


async def test_a_channel_route_delivers_a_post_that_carries_its_author(tmp_path):
    """Discord posts always name their author; a route with no author filter still serves them."""
    event = RawMessage(
        schema_version=1,
        event_type="raw_message",
        source="discord",
        channel_id="123",
        id="456",
        author_id="999",
        timestamp=dt.datetime.now(dt.UTC),
        text="ALERT: Bought AAPL at 200",
    )
    opened: dict[str, Owner] = {}

    async def owner_factory(path, credentials, policy, environment):
        opened[path.name] = Owner(path, {}, {})
        return opened[path.name]

    async def decoder_factory(name, config):
        return Decoder()

    factories = TradingFactories(
        owner=owner_factory,
        decoder=decoder_factory,
        session=lambda source, channels, authors, stop, report_failure: Session(source, event),
    )
    runtime = TradingRuntime(tmp_path, factories=factories)
    await runtime.start(trading_configuration(), trading_secrets())
    await wait_for(
        runtime, lambda status: status.processed_signals == 1 and status.pending_signals == 0
    )
    await runtime.shutdown()
    [delivered] = opened["first"].deliveries
    assert delivered.signal.author_id == "999"
    assert opened["second"].deliveries == []


async def test_pending_signal_rejects_changed_destination_after_restart(tmp_path):
    event = RawMessage(
        schema_version=1,
        event_type="raw_message",
        source="discord",
        channel_id=channel("second"),
        id="pending",
        timestamp=dt.datetime.now(dt.UTC),
        text="ALERT: Bought AAPL at 200",
    )
    opened: list[str] = []

    async def owner_factory(path, credentials, policy, environment):
        opened.append(path.name)
        return Owner(path, {"second": 1}, {})

    factories = TradingFactories(
        owner=owner_factory,
        decoder=lambda name, config: asyncio.sleep(0, result=Decoder()),
        session=lambda source, channels, authors, stop, report_failure: Session(source, event),
    )
    runtime = TradingRuntime(tmp_path, factories=factories)
    await runtime.start(trading_configuration(), trading_secrets())
    await wait_for(
        runtime,
        lambda status: any(
            account.id == "second" and account.state == "failed" for account in status.accounts
        ),
    )
    await runtime.shutdown()
    changed = trading_configuration().model_dump(mode="json")
    changed["accounts"].append({"id": "third", "environment": "paper"})
    changed["routes"][1]["connections"] = [connection("third")]
    await runtime.start(
        TradingConfiguration.model_validate(changed),
        trading_secrets_for("first", "second", "third"),
    )
    rejected = await wait_for(runtime, lambda status: status.state == "failed")
    assert rejected.error_code == "routing_change_pending"
    assert "third" not in opened


async def test_pending_source_rejects_changed_destination(tmp_path):
    database = tmp_path / "application.db"
    source = await SQLiteSourceStore.open(database)
    parser = await SQLiteExtractionStore.open(database)
    guard = await RoutingRevision.open(database)
    try:
        await guard.accept(trading_configuration())
        await source.add(
            RawMessage(
                schema_version=1,
                event_type="raw_message",
                source="discord",
                channel_id="123",
                id="captured",
                timestamp=dt.datetime.now(dt.UTC),
                text="ALERT: Bought AAPL at 200",
            )
        )
        changed = trading_configuration().model_dump(mode="json")
        changed["routes"][0]["connections"] = [connection("second")]
        changed["routes"][1]["connections"] = [connection("first")]
        changed_configuration = TradingConfiguration.model_validate(changed)
        with pytest.raises(RoutingChangePending):
            await guard.validate(changed_configuration)
        with pytest.raises(RoutingChangePending):
            await guard.accept(changed_configuration)
    finally:
        await guard.close()
        await parser.close()
        await source.close()


async def test_account_removal_requires_settled_execution_ownership(tmp_path, monkeypatch):
    database = tmp_path / "application.db"
    source = await SQLiteSourceStore.open(database)
    parser = await SQLiteExtractionStore.open(database)
    guard = await RoutingRevision.open(database)
    try:
        await guard.accept(trading_configuration())
        replacement = trading_configuration("first")
        monkeypatch.setattr(
            "copytrading_engine.trading.adapters.routing.has_unresolved_ownership",
            lambda path: True,
        )
        with pytest.raises(AccountOwnershipPending):
            await guard.accept(replacement)
        monkeypatch.setattr(
            "copytrading_engine.trading.adapters.routing.has_unresolved_ownership",
            lambda path: False,
        )
        await guard.accept(replacement)
    finally:
        await guard.close()
        await parser.close()
        await source.close()


class _SlowClosingOwner(Owner):
    async def close(self):
        await asyncio.sleep(0.1)
        await super().close()


class _FailingCloseOwner(Owner):
    async def close(self):
        await asyncio.sleep(0.01)
        self.db.close()  # The fake's own file still closes; only the lock release fails.
        raise OSError("lock release failed")


async def test_shutdown_waits_for_an_owner_that_just_finished_opening_late(tmp_path, caplog):
    """An owner that opened late hands itself off to be closed a moment later; shutdown waits.

    With nothing else left to wait for, shutdown used to return in that moment, and the close,
    with its error, ran after shutdown had returned.
    """
    runtime = TradingRuntime(tmp_path)
    (tmp_path / "second").mkdir()
    opening: asyncio.Future[Owner] = asyncio.get_running_loop().create_future()
    runtime._watch_late_owner(opening)
    opening.set_result(_FailingCloseOwner(tmp_path / "second", {}, {}))

    await runtime.shutdown()

    assert "late_account_owner_close_failed type=OSError" in caplog.text


@pytest.mark.parametrize("late_owner_type", [_SlowClosingOwner, _FailingCloseOwner])
async def test_shutdown_waits_for_late_account_owner_close(tmp_path, caplog, late_owner_type):
    release = asyncio.Event()
    opened: dict[str, Owner] = {}
    event = RawMessage(
        schema_version=1,
        event_type="raw_message",
        source="discord",
        channel_id="123",
        id="late-owner",
        timestamp=dt.datetime.now(dt.UTC),
        text="ALERT: Bought AAPL at 200",
    )

    async def owner_factory(path, credentials, policy, environment):
        if path.name == "second":
            await release.wait()
            owner: Owner = late_owner_type(path, {}, {})
        else:
            owner = Owner(path, {}, {})
        opened[path.name] = owner
        return owner

    runtime = TradingRuntime(
        tmp_path,
        factories=TradingFactories(
            owner=owner_factory,
            decoder=lambda name, config: asyncio.sleep(0, result=Decoder()),
            session=lambda source, channels, authors, stop, report_failure: Session(source, event),
        ),
        owner_open_timeout_seconds=0.05,
    )
    await runtime.start(trading_configuration(), trading_secrets())
    await wait_for(runtime, lambda status: status.active_accounts == 1)
    release.set()
    await wait_for_value(lambda: "second" in opened)

    await runtime.shutdown()

    if late_owner_type is _SlowClosingOwner:
        assert opened["second"].closed
    else:
        assert "late_account_owner_close_failed type=OSError" in caplog.text
