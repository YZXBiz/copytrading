"""Accounts reads the ledger and the broker together: a fill never shows as shares at the broker
that CopyTrading didn't copy."""

import datetime as dt
from decimal import Decimal

from copytrading_engine.execution.domain.lifecycle import AccountControlCommand
from copytrading_engine.shared.signals import StockSignal

from .builders import destination_signal, event
from .fakes import FakeBroker
from .test_account_lifecycle import _open


class AcknowledgeThenFill(FakeBroker):
    """Like Alpaca: the submit answers "new", and the shares are at the broker a moment later."""

    def __init__(self):
        super().__init__()
        self.auto_fill = False

    def submit(self, order):
        acknowledged = super().submit(order)
        self.fill(order.client_order_id, order.qty)
        return acknowledged


def _resume():
    return AccountControlCommand(command_id="enable", account_id="paper", action="resume")


async def test_a_buy_filled_in_the_cycle_reads_as_copied_or_not_at_all(tmp_path, monkeypatch):
    datetime_type = dt.datetime

    class FixedDateTime(datetime_type):
        @classmethod
        def now(cls, tz=None):
            fixed = cls(2026, 1, 5, 15, 0, tzinfo=dt.UTC)
            return fixed if tz is None else fixed.astimezone(tz)

    monkeypatch.setattr(dt, "datetime", FixedDateTime)
    now = FixedDateTime(2026, 1, 5, 15, 0, tzinfo=dt.UTC)
    broker = AcknowledgeThenFill()
    owner = await _open(tmp_path, broker)
    try:
        await owner.recover_account(now)
        await owner.control_account(_resume(), now)
        buy = StockSignal.model_validate(event("fills-at-once", price="25.10", timestamp=now))
        await owner.receive(destination_signal(buy, account_id="paper"), now)
        await owner.cycle(now, halted=False)
        assert broker.calls == 1
        assert broker.holdings

        # Right after the cycle that placed it, and after the next one.
        for _ in range(2):
            overview = await owner.operator_overview()
            [position] = [p for p in overview.positions if p.symbol == "ABC"] or [None]
            if position is not None and position.broker_qty is not None:
                held = Decimal(position.broker_qty)
                assert position.owned_qty + position.external_qty == held, (
                    f"broker holds {held} but the overview counts "
                    f"{position.owned_qty} copied and {position.external_qty} outside"
                )
            await owner.cycle(now, halted=False)
        overview = await owner.operator_overview()
        [position] = [p for p in overview.positions if p.symbol == "ABC"]
        assert position.owned_qty == Decimal(position.broker_qty) > 0
    finally:
        await owner.close()


async def test_a_closed_owner_falls_back_without_a_warning(tmp_path, caplog):
    from copytrading_engine.trading.application.account_access import (
        OwnerUnavailable,
        bounded_owner_read,
    )

    owner = await _open(tmp_path, FakeBroker())
    await owner.close()

    with caplog.at_level("WARNING"):
        result = await bounded_owner_read(owner.operator_overview())

    assert isinstance(result, OwnerUnavailable)
    assert "operator_account_read_failed" not in caplog.text
