"""A parsed signal reaches the accounts of the route that parsed it, whoever posted it."""

from __future__ import annotations

import asyncio
import datetime as dt
from decimal import Decimal

from copytrading_engine.execution.domain.sizing import DestinationTerms, RouteConnection
from copytrading_engine.parsing.application import outcome
from copytrading_engine.parsing.sqlite import SQLiteExtractionStore
from copytrading_engine.shared.raw_message import RawMessage
from copytrading_engine.trading.application.accounts import SignalFanout


class _Receiver:
    def __init__(self) -> None:
        self.received = 0

    async def receive(self, delivery, now: dt.datetime) -> None:
        self.received += 1


def _terms(account_id: str) -> DestinationTerms:
    return DestinationTerms(
        connection=RouteConnection(
            account_id=account_id, mode="fixed", amount_usd=Decimal("100.00")
        ),
        environment="paper",
        configuration_revision="a" * 64,
    )


async def _delivered(tmp_path, routes, author_id: str | None) -> int:
    store = await SQLiteExtractionStore.open(tmp_path / "parser.db")
    event = RawMessage(
        schema_version=1,
        event_type="raw_message",
        source="discord",
        channel_id="123",
        id="456",
        author_id=author_id,
        timestamp=dt.datetime.now(dt.UTC),
        text="commentary",
    )
    receiver = _Receiver()
    try:
        await store.add(event)
        await store.finish(event.identity, outcome(event, "ignore", "commentary", model="test"))
        fanout = SignalFanout(store, routes, {"account-a": receiver}, asyncio.Event())
        assert await fanout.deliver() == 1
    finally:
        await store.close()
    return receiver.received


async def test_a_channel_route_serves_a_message_from_any_author(tmp_path) -> None:
    routes = {"discord:123:*": (_terms("account-a"),)}
    assert await _delivered(tmp_path, routes, author_id="999") == 1


async def test_an_author_route_serves_that_author(tmp_path) -> None:
    routes = {"discord:123:999": (_terms("account-a"),)}
    assert await _delivered(tmp_path, routes, author_id="999") == 1


async def test_an_author_route_ignores_other_authors(tmp_path) -> None:
    routes = {"discord:123:999": (_terms("account-a"),)}
    assert await _delivered(tmp_path, routes, author_id="111") == 0
