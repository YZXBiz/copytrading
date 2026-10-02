"""Persisted source lineage reaches every retrying destination before account work."""

from __future__ import annotations

import asyncio
import datetime as dt
import sqlite3
from contextlib import closing
from decimal import Decimal

from copytrading_engine.execution.domain.sizing import DestinationTerms, RouteConnection
from copytrading_engine.parsing.application import outcome
from copytrading_engine.parsing.sqlite import SQLiteExtractionStore
from copytrading_engine.shared.correlation import current_workflow_attempt
from copytrading_engine.shared.raw_message import RawMessage
from copytrading_engine.trading.application.accounts import AccountUnavailable, SignalFanout


class _Receiver:
    def __init__(self, name: str, database: str, failures: int = 0) -> None:
        self.name = name
        self.database = database
        self.failures = failures
        self.observed = []

    async def receive(self, delivery, now: dt.datetime) -> None:
        correlation = current_workflow_attempt()
        assert correlation is not None
        assert correlation.destination_id is not None
        assert correlation.attempt > 0
        with closing(sqlite3.connect(self.database)) as db, db:
            persisted = db.execute(
                "SELECT destination_id,attempts FROM parser_destinations "
                "WHERE message_id=? AND account_id=?",
                (
                    f"{delivery.signal.source}:{delivery.signal.channel_id}:{delivery.signal.id}",
                    self.name,
                ),
            ).fetchone()
        assert persisted == (correlation.destination_id, correlation.attempt)
        self.observed.append(correlation)
        if self.failures:
            self.failures -= 1
            raise AccountUnavailable


def _terms(account_id: str) -> DestinationTerms:
    return DestinationTerms(
        connection=RouteConnection(
            account_id=account_id, mode="fixed", amount_usd=Decimal("100.00")
        ),
        environment="paper",
        configuration_revision="a" * 64,
    )


async def test_multi_destination_retries_keep_workflow_identity_and_commit_attempt_first(
    tmp_path,
) -> None:
    database = tmp_path / "parser.db"
    store = await SQLiteExtractionStore.open(database)
    event = RawMessage(
        schema_version=1,
        event_type="raw_message",
        source="discord",
        channel_id="123",
        id="456",
        timestamp=dt.datetime.now(dt.UTC),
        text="commentary",
    )
    await store.add(event)
    await store.finish(event.identity, outcome(event, "ignore", "commentary", model="test"))
    receivers = {
        "account-a": _Receiver("account-a", str(database), failures=1),
        "account-b": _Receiver("account-b", str(database)),
    }
    fanout = SignalFanout(
        store,
        {"discord:123:*": (_terms("account-a"), _terms("account-b"))},
        receivers,
        asyncio.Event(),
    )
    try:
        assert await fanout.deliver() == 0
        assert await fanout.deliver() == 1

        a_first, a_retry = receivers["account-a"].observed
        b_first, b_retry = receivers["account-b"].observed
        assert a_first.workflow_id == a_retry.workflow_id
        assert a_first.trace_id == a_retry.trace_id
        assert b_first.workflow_id == a_first.workflow_id
        assert b_first.trace_id == a_first.trace_id
        assert a_first.destination_id != b_first.destination_id
        assert a_retry.destination_id == a_first.destination_id
        assert b_retry.destination_id == b_first.destination_id
        assert (a_first.attempt, a_retry.attempt) == (1, 2)
        assert (b_first.attempt, b_retry.attempt) == (1, 2)
    finally:
        await store.close()
