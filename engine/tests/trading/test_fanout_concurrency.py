"""Accounts take the same post side by side, and one account's trouble never cuts another short."""

from __future__ import annotations

import asyncio
import datetime as dt
from decimal import Decimal

import pytest

from copytrading_engine.execution.domain.sizing import DestinationTerms, RouteConnection
from copytrading_engine.parsing.application import outcome
from copytrading_engine.parsing.sqlite import SQLiteExtractionStore
from copytrading_engine.shared.raw_message import RawMessage
from copytrading_engine.trading.application.accounts import AccountUnavailable, SignalFanout


class _SlowAccount:
    """Takes a while to decide, and records how many accounts were deciding at once."""

    def __init__(self, gauge: list[int], *, fails_with: BaseException | None = None) -> None:
        self.gauge = gauge
        self.fails_with = fails_with
        self.finished = False

    async def receive(self, delivery, now: dt.datetime) -> None:
        self.gauge[0] += 1
        self.gauge[1] = max(self.gauge[1], self.gauge[0])
        try:
            await asyncio.sleep(0.1)
            if self.fails_with is not None:
                raise self.fails_with
            self.finished = True
        finally:
            self.gauge[0] -= 1


def _terms(account_id: str) -> DestinationTerms:
    return DestinationTerms(
        connection=RouteConnection(
            account_id=account_id, mode="fixed", amount_usd=Decimal("100.00")
        ),
        environment="paper",
        configuration_revision="a" * 64,
    )


async def _deliver(tmp_path, accounts: dict[str, _SlowAccount]) -> int:
    store = await SQLiteExtractionStore.open(tmp_path / "parser.db")
    event = RawMessage(
        schema_version=1,
        event_type="raw_message",
        source="discord",
        channel_id="123",
        id="456",
        author_id="999",
        timestamp=dt.datetime.now(dt.UTC),
        text="Bought AAPL",
    )
    routes = {"discord:123:*": tuple(_terms(account_id) for account_id in accounts)}
    try:
        await store.add(event)
        await store.finish(event.identity, outcome(event, "ignore", "commentary", model="test"))
        return await SignalFanout(store, routes, accounts, asyncio.Event()).deliver()
    finally:
        await store.close()


async def test_every_account_decides_on_a_post_at_the_same_time(tmp_path) -> None:
    gauge = [0, 0]
    accounts = {name: _SlowAccount(gauge) for name in ("account-a", "account-b", "account-c")}

    started = asyncio.get_running_loop().time()
    assert await _deliver(tmp_path, accounts) == 1
    elapsed = asyncio.get_running_loop().time() - started

    assert gauge[1] == 3
    assert all(account.finished for account in accounts.values())
    assert elapsed < 0.25, "three 0.1 s decisions in turn would take 0.3 s"


async def test_an_unavailable_account_holds_the_post_without_stopping_the_others(tmp_path) -> None:
    gauge = [0, 0]
    accounts = {
        "account-a": _SlowAccount(gauge, fails_with=AccountUnavailable()),
        "account-b": _SlowAccount(gauge),
    }

    assert await _deliver(tmp_path, accounts) == 0

    assert accounts["account-b"].finished


async def test_an_unexpected_failure_surfaces_only_after_every_account_finishes(tmp_path) -> None:
    gauge = [0, 0]
    accounts = {
        "account-a": _SlowAccount(gauge, fails_with=RuntimeError("broker exploded")),
        "account-b": _SlowAccount(gauge),
    }

    with pytest.raises(RuntimeError, match="broker exploded"):
        await _deliver(tmp_path, accounts)

    assert accounts["account-b"].finished, "a sibling's failure must not cancel an order in flight"
