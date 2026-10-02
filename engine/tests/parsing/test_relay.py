"""The relay retries an unconfirmed delivery without losing its result."""

import datetime as dt

import pytest

from copytrading_engine.parsing.application import outcome
from copytrading_engine.parsing.relay import (
    accept_live_sources,
    deliver_notifications,
    deliver_signals,
)
from copytrading_engine.parsing.sqlite import SQLiteExtractionStore
from copytrading_engine.shared.raw_message import RawMessage
from copytrading_engine.sources.sqlite import SQLiteSourceStore


async def test_relay_retries_unconfirmed_delivery_without_losing_result(tmp_path):
    path = tmp_path / "app.db"
    source = await SQLiteSourceStore.open(path)
    parser = await SQLiteExtractionStore.open(path)
    raw = RawMessage(
        schema_version=1,
        event_type="raw_message",
        source="discord",
        channel_id="7",
        id="42",
        timestamp=dt.datetime.now(dt.UTC),
        text="commentary",
    )
    await source.add(raw)
    assert await accept_live_sources(source, parser) == 1
    assert await accept_live_sources(source, parser) == 0
    await parser.finish(raw.identity, outcome(raw, "ignore", "commentary", model="test"))

    received = []

    async def fail_once(signal):
        received.append(signal)
        raise RuntimeError("downstream unavailable")

    with pytest.raises(RuntimeError):
        await deliver_signals(parser, fail_once)
    assert len(await parser.claim_pending_signals()) == 1

    async def accept(signal):
        received.append(signal)

    assert await deliver_signals(parser, accept) == 1
    assert received[0] == received[1]

    notifications = []

    async def notify(intent):
        notifications.append(intent)

    assert await deliver_notifications(parser, notify) == 1
    assert notifications[0].key == raw.identity
    assert await parser.claim_pending_notifications() == ()
    await source.close()
    await parser.close()
