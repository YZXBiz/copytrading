"""Reads on the owner thread use the ledger in place; only state that leaves it is copied."""

import datetime as dt

from copytrading_engine.execution.application.ledger import TradingLedger

from .builders import NOW
from .fakes import FakeBroker
from .test_account_lifecycle import _open


async def test_a_cycle_and_a_status_read_copy_the_ledger_at_most_once(tmp_path, monkeypatch):
    """Each copy of a live ledger costs tens of milliseconds (32 ms for a 1.6 MB paper ledger);
    an idle cycle made nine and every status refresh three, a third of a second of CPU per account
    every two seconds. The cycle now copies once, for the observation it hands back."""
    datetime_type = dt.datetime

    class FixedDateTime(datetime_type):
        @classmethod
        def now(cls, tz=None):
            fixed = cls(2026, 1, 5, 15, 0, tzinfo=dt.UTC)
            return fixed if tz is None else fixed.astimezone(tz)

    monkeypatch.setattr(dt, "datetime", FixedDateTime)
    copies = []
    copy = TradingLedger.snapshot
    monkeypatch.setattr(TradingLedger, "snapshot", lambda self: copies.append(1) or copy(self))
    owner = await _open(tmp_path, FakeBroker())
    try:
        await owner.recover_account(NOW)
        copies.clear()
        await owner.cycle(NOW, halted=False)
        assert len(copies) == 1
        copies.clear()
        await owner.account_status()
        assert copies == []
    finally:
        await owner.close()
