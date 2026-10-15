"""A cycle records each fill at the time it reads it, never before the order that filled."""

import datetime as dt
import sqlite3
from contextlib import closing

from copytrading_engine.execution.domain.events import JournalEvent
from copytrading_engine.execution.domain.lifecycle import AccountControlCommand
from copytrading_engine.shared.signals import StockSignal

from .builders import destination_signal, event
from .test_account_lifecycle import _open
from .test_overview_after_fill import AcknowledgeThenFill

QUEUED_AT = dt.datetime(2026, 1, 5, 15, 0, tzinfo=dt.UTC)


def _journal(tmp_path) -> list[JournalEvent]:
    path = tmp_path / "accounts" / "paper" / "execution.sqlite3"
    with closing(sqlite3.connect(path)) as db:
        rows = db.execute("SELECT event FROM journal ORDER BY id").fetchall()
    return [JournalEvent.model_validate_json(raw) for (raw,) in rows]


async def test_a_fill_read_in_the_cycle_that_placed_it_is_stamped_after_the_order(
    tmp_path, monkeypatch
):
    datetime_type = dt.datetime
    ticks = iter(range(10_000))

    class RunningClock(datetime_type):
        """The supervisor asked for the cycle at QUEUED_AT; the clock has moved on since, one
        second every time anything reads it."""

        @classmethod
        def now(cls, tz=None):
            moment = cls(2026, 1, 5, 15, 0, 5, tzinfo=dt.UTC) + dt.timedelta(seconds=next(ticks))
            return moment if tz is None else moment.astimezone(tz)

    monkeypatch.setattr(dt, "datetime", RunningClock)
    owner = await _open(tmp_path, AcknowledgeThenFill())
    try:
        await owner.recover_account(QUEUED_AT)
        await owner.control_account(
            AccountControlCommand(command_id="enable", account_id="paper", action="resume"),
            QUEUED_AT,
        )
        buy = StockSignal.model_validate(event("fills-at-once", price="25.10", timestamp=QUEUED_AT))
        await owner.receive(destination_signal(buy, account_id="paper"), QUEUED_AT)
        await owner.cycle(QUEUED_AT, halted=False)
    finally:
        await owner.close()

    events = _journal(tmp_path)
    [prepared] = [item for item in events if item.payload.kind == "order_prepared"]
    [filled] = [
        item
        for item in events
        if item.payload.kind == "order_update" and getattr(item.payload, "status", None) == "filled"
    ]
    assert filled.at > prepared.at
