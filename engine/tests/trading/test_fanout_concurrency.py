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

    def __init__(
        self,
        gauge: list[int],
        *,
        fails_with: BaseException | None = None,
        meeting: asyncio.Barrier | None = None,
    ) -> None:
        self.gauge = gauge
        self.fails_with = fails_with
        self.meeting = meeting
        self.finished = False

    async def receive(self, delivery, now: dt.datetime) -> None:
        self.gauge[0] += 1
        self.gauge[1] = max(self.gauge[1], self.gauge[0])
        try:
            if self.meeting is None:
                await asyncio.sleep(0.1)
            else:
                await self.meeting.wait()
            if self.fails_with is not None:
                raise self.fails_with
            self.finished = True
        finally:
            self.gauge[0] -= 1


def _terms(account_id: str) -> DestinationTerms:
    return DestinationTerms(
        connection=RouteConnection(account_id=account_id, full_position_usd=Decimal("100.00")),
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
    # Each account decides only once all three are deciding, so taking them in turn never ends
    # and the timeout fails the test, however slow the machine.
    meeting = asyncio.Barrier(3)
    gauge = [0, 0]
    accounts = {
        name: _SlowAccount(gauge, meeting=meeting)
        for name in ("account-a", "account-b", "account-c")
    }

    async with asyncio.timeout(30):
        assert await _deliver(tmp_path, accounts) == 1

    assert gauge[1] == 3
    assert all(account.finished for account in accounts.values())


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


async def test_stopping_between_two_accounts_leaves_no_unawaited_work(tmp_path) -> None:
    """A stop that lands after one account's attempt is reserved must not strand its coroutine.

    The engine stops at that moment whenever it shuts down mid-post. Work for the reserved
    account used to be built before the loop ended, then dropped unawaited, which Python reports
    as "coroutine was never awaited" (a failure here, where warnings are errors).
    """
    stop = asyncio.Event()
    accounts = {name: _SlowAccount([0, 0]) for name in ("account-a", "account-b")}
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
    reserve = store.reserve_destination_attempt

    async def reserve_then_stop(key: str, account_id: str):
        identity = await reserve(key, account_id)
        stop.set()
        return identity

    store.reserve_destination_attempt = reserve_then_stop  # type: ignore[method-assign]
    routes = {"discord:123:*": tuple(_terms(account_id) for account_id in accounts)}
    try:
        await store.add(event)
        await store.finish(event.identity, outcome(event, "ignore", "commentary", model="test"))
        assert await SignalFanout(store, routes, accounts, stop).deliver() == 0
    finally:
        await store.close()

    assert not any(account.finished for account in accounts.values())
