"""One slow or failing source, decoder, or account never stalls the others."""

import asyncio
import datetime as dt
import sqlite3
from uuid import uuid4

from copytrading_engine.parsing.sqlite import SQLiteExtractionStore
from copytrading_engine.shared.raw_message import RawMessage
from copytrading_engine.sources.sqlite import SQLiteSourceStore
from copytrading_engine.trading.adapters.routing import (
    RoutingRevision,
)
from copytrading_engine.trading.domain.config import TradingConfiguration
from copytrading_engine.trading.entrypoints.factories import TradingFactories
from copytrading_engine.trading.entrypoints.runtime import TradingRuntime

from ...readings import sell, trade
from .builders import (
    connection,
    trading_configuration,
    trading_secrets,
    trading_secrets_for,
    wait_for,
)
from .fakes import Decoder, Owner, Session


async def test_slow_decoder_does_not_block_broker_reconciliation(tmp_path):
    entered_decode = asyncio.Event()
    release_decode = asyncio.Event()
    event = RawMessage(
        schema_version=1,
        event_type="raw_message",
        source="discord",
        channel_id="123",
        id="slow-model",
        timestamp=dt.datetime.now(dt.UTC),
        text="ALERT: Bought AAPL at 200",
    )

    class SlowDecoder(Decoder):
        async def decode(self, text, route):
            if text != "Market commentary only. No trade action.":
                entered_decode.set()
                await release_decode.wait()
            return await super().decode(text, route)

    opened: dict[str, Owner] = {}

    async def owner_factory(path, credentials, policy, environment):
        owner = Owner(path, {}, {})
        opened[path.name] = owner
        return owner

    async def decoder_factory(name, config):
        return SlowDecoder()

    factories = TradingFactories(
        owner=owner_factory,
        decoder=decoder_factory,
        session=lambda source, channels, authors, stop, report_failure: Session(source, event),
    )
    config = trading_configuration().model_dump(mode="json")
    config["accounts"] = [{"id": "first", "environment": "paper", "policy": {"poll_seconds": 1}}]
    config["routes"][0]["connections"] = [connection("first")]
    runtime = TradingRuntime(tmp_path, factories=factories)
    await runtime.start(TradingConfiguration.model_validate(config), trading_secrets_for("first"))
    await asyncio.wait_for(entered_decode.wait(), timeout=3)
    try:
        await asyncio.wait_for(wait_for(runtime, lambda _: opened["first"].cycles >= 2), 3)
        assert runtime.status().state in {"running", "degraded"}
    finally:
        release_decode.set()
        await runtime.shutdown()


async def test_failed_source_does_not_stop_broker_reconciliation(tmp_path):
    class FailedSession(Session):
        async def ensure_running(self):
            raise RuntimeError("fake source disconnected")

    opened: dict[str, Owner] = {}

    async def owner_factory(path, credentials, policy, environment):
        owner = Owner(path, {}, {})
        opened[path.name] = owner
        return owner

    config = trading_configuration().model_dump(mode="json")
    config["accounts"] = [{"id": "first", "environment": "paper", "policy": {"poll_seconds": 1}}]
    config["routes"][0]["connections"] = [connection("first")]
    event = RawMessage(
        schema_version=1,
        event_type="raw_message",
        source="discord",
        channel_id="123",
        id="source-failure",
        timestamp=dt.datetime.now(dt.UTC),
        text="ALERT: Bought AAPL at 200",
    )
    runtime = TradingRuntime(
        tmp_path,
        factories=TradingFactories(
            owner=owner_factory,
            decoder=lambda name, config: asyncio.sleep(0, result=Decoder()),
            session=lambda source, channels, authors, stop, report_failure: FailedSession(
                source, event
            ),
        ),
    )
    await runtime.start(TradingConfiguration.model_validate(config), trading_secrets_for("first"))
    degraded = await wait_for(runtime, lambda status: status.error_code == "source_unavailable")
    assert degraded.active_accounts == 1
    await wait_for(runtime, lambda status: opened["first"].cycles >= 2)
    await runtime.shutdown()


async def test_uncertain_shared_delivery_stops_all_accounts(tmp_path):
    class BrokenForwardSession(Session):
        async def forward_if_ready(self, forwarder):
            raise sqlite3.OperationalError("fake shared database unavailable")

    opened: dict[str, Owner] = {}

    async def owner_factory(path, credentials, policy, environment):
        owner = Owner(path, {}, {})
        opened[path.name] = owner
        return owner

    runtime = TradingRuntime(
        tmp_path,
        factories=TradingFactories(
            owner=owner_factory,
            decoder=lambda name, config: asyncio.sleep(0, result=Decoder()),
            session=lambda source, channels, authors, stop, report_failure: BrokenForwardSession(
                source, None
            ),
        ),
    )
    await runtime.start(trading_configuration(), trading_secrets())
    failed = await wait_for(runtime, lambda status: status.state == "failed")
    assert failed.error_code == "processing_unavailable"
    assert all(owner.stopped for owner in opened.values())


async def test_old_failed_account_deliveries_do_not_starve_later_healthy_route(tmp_path):
    database = tmp_path / "application.db"
    source = await SQLiteSourceStore.open(database)
    parser = await SQLiteExtractionStore.open(database)
    guard = await RoutingRevision.open(database)
    config = trading_configuration().model_dump(mode="json")
    config["source"]["channel_ids"] = ["123", "124"]
    shared = config["routes"][0]
    config["routes"] = [
        {**shared, "channel_id": "123", "connections": [connection("second")]},
        {**shared, "channel_id": "124", "connections": [connection("first")]},
    ]
    configuration = TradingConfiguration.model_validate(config)
    await guard.accept(configuration)
    try:
        for index in range(101):
            await parser.add(
                RawMessage(
                    schema_version=1,
                    event_type="raw_message",
                    source="discord",
                    channel_id="123" if index < 100 else "124",
                    id=f"message-{index:03d}",
                    timestamp=dt.datetime.now(dt.UTC),
                    text="ALERT: Bought AAPL at 200",
                )
            )
    finally:
        await guard.close()
        await parser.close()
        await source.close()

    healthy: dict[str, Owner] = {}

    async def owner_factory(path, credentials, policy, environment):
        if path.name == "second":
            raise RuntimeError("fake account unavailable")
        owner = Owner(path, {}, {})
        healthy[path.name] = owner
        return owner

    runtime = TradingRuntime(
        tmp_path,
        factories=TradingFactories(
            owner=owner_factory,
            decoder=lambda name, config: asyncio.sleep(0, result=Decoder()),
            session=lambda source, channels, authors, stop, report_failure: Session(source, None),
        ),
    )
    activation_id = str(uuid4())
    await runtime.start(configuration, trading_secrets(), activation_id)
    try:
        status = await wait_for(runtime, lambda value: value.processed_signals == 1)
        assert status.state == "degraded"
        assert status.active_accounts == 1
        assert status.accounts[0].state == "running"
        assert status.accounts[1].state == "failed"
        activation = runtime.activation_status(activation_id)
        assert activation.phase == "failed"
        assert activation.committed_revision is None
        assert activation.runtime_state == "degraded"
        receipt = sqlite3.connect(tmp_path / "accounts" / "first" / "fake-receipts.sqlite3")
        try:
            assert receipt.execute("SELECT count(*) FROM receipts").fetchone() == (1,)
        finally:
            receipt.close()
    finally:
        await runtime.shutdown()
    paused_activation = runtime.activation_status(activation_id)
    assert paused_activation.phase == "failed"
    assert paused_activation.runtime_state == "paused"


async def test_slow_account_open_does_not_block_healthy_account_or_capture(tmp_path):
    release = asyncio.Event()
    opened: dict[str, Owner] = {}
    event = RawMessage(
        schema_version=1,
        event_type="raw_message",
        source="discord",
        channel_id="123",
        id="slow-account",
        timestamp=dt.datetime.now(dt.UTC),
        text="ALERT: Bought AAPL at 200",
    )

    async def owner_factory(path, credentials, policy, environment):
        if path.name == "second":
            await release.wait()
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
    try:
        await runtime.start(trading_configuration(), trading_secrets())
        await wait_for(
            runtime, lambda status: status.source_connected and status.active_accounts == 1
        )
        await wait_for(runtime, lambda status: "first" in opened and opened["first"].cycles > 0)
        summaries = (await runtime.operator.account_overviews()).items
        assert {item.account_id for item in summaries} == {"first", "second"}
        failed = next(item for item in summaries if item.account_id == "second")
        assert failed.readiness == "account_unavailable"
        assert failed.total_exposure_usd is None
        assert failed.pending_orders is None
        await wait_for(runtime, lambda status: status.pending_signals > 0)
        activity = await runtime.operator.source_activity(None, 10)
        assert activity.items
        assert any(
            destination.account_id == "second" and destination.status == "pending_delivery"
            for destination in activity.items[0].destinations
        )
    finally:
        release.set()
        await runtime.shutdown()
        await asyncio.sleep(0)


class _UngroundedThenBuyDecoder:
    """Reads the first post with a fraction the post never states, then a clean buy."""

    async def decode(self, text, route):
        if text == "Sold AAPL at 210 from 200":
            return trade(
                sell(
                    "AAPL",
                    "210",
                    bought_at="200",
                    said="Sold",
                    ticker_said="AAPL",
                    fraction="0.5",
                    fraction_said="half",
                ),
                summary="Close",
            )
        return await Decoder().decode(text, route)

    async def close(self):
        pass


class _TwoPostSession(Session):
    def __init__(self, source, events):
        super().__init__(source, None)
        self.events = events

    def start(self, token):
        async def capture():
            for event in self.events:
                await self.source.add(event)

        self.capture_task = asyncio.create_task(capture())


async def test_post_that_fails_evidence_checks_goes_to_review_and_processing_continues(tmp_path):
    now = dt.datetime.now(dt.UTC)
    events = tuple(
        RawMessage(
            schema_version=1,
            event_type="raw_message",
            source="discord",
            channel_id="123",
            id=message_id,
            timestamp=now,
            text=text,
        )
        for message_id, text in (
            ("501", "ALERT: Sold AAPL at 210 from 200"),
            ("502", "ALERT: Bought AAPL at 200"),
        )
    )
    opened: dict[str, Owner] = {}

    async def owner_factory(path, credentials, policy, environment):
        opened[path.name] = Owner(path, {}, {})
        return opened[path.name]

    runtime = TradingRuntime(
        tmp_path,
        factories=TradingFactories(
            owner=owner_factory,
            decoder=lambda name, config: asyncio.sleep(0, result=_UngroundedThenBuyDecoder()),
            session=lambda source, channels, authors, stop, report: _TwoPostSession(source, events),
        ),
    )
    await runtime.start(trading_configuration(), trading_secrets())
    try:
        await wait_for(runtime, lambda status: status.processed_signals >= 1)
        assert runtime.status().state == "running"
        delivered = [delivery.signal.id for delivery in opened["first"].deliveries]
        assert "502" in delivered
        page = await runtime.operator.source_activity(None, 10)
        review = next(item for item in page.items if item.text.endswith("from 200"))
        assert review.decision == "review"
        assert review.parser_reason == "evidence_validation_failed"
    finally:
        await runtime.shutdown()
