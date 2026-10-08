"""Accounts shows a position the way a trader reads it: what it cost, what it is worth now, and the
gain or loss, from the broker's own valuation; each copied lot against the current price."""

import datetime as dt
from decimal import Decimal

from copytrading_engine.execution.adapters.alpaca.models import decode_positions
from copytrading_engine.execution.domain.lifecycle import AccountControlCommand
from copytrading_engine.shared.signals import StockSignal

from .builders import destination_signal, event
from .fakes import FakeBroker
from .test_account_lifecycle import _open

PRICE = Decimal("26.00")


class ValuedBroker(FakeBroker):
    """Positions carry the broker's valuation, the way Alpaca's do."""

    def positions(self):
        return tuple(
            position.model_copy(
                update={
                    "avg_entry_price": Decimal("25.10"),
                    "current_price": PRICE,
                    "market_value": position.qty * PRICE,
                    "unrealized_pl": (position.qty * (PRICE - Decimal("25.10"))).quantize(
                        Decimal("0.01")
                    ),
                    "unrealized_plpc": Decimal("0.0359"),
                }
            )
            for position in super().positions()
        )


def test_alpacas_valuation_fields_are_read():
    [position] = decode_positions(
        [
            {
                "symbol": "PM",
                "qty": "1",
                "market_value": "200.4",
                "asset_class": "us_equity",
                "avg_entry_price": "199.59",
                "current_price": "200.4",
                "unrealized_pl": "0.81",
                "unrealized_plpc": "0.0040583195",
            }
        ],
        account_currency="USD",
    )

    assert (position.avg_entry_price, position.current_price) == (
        Decimal("199.59"),
        Decimal("200.4"),
    )
    assert (position.unrealized_pl, position.unrealized_plpc) == (
        Decimal("0.81"),
        Decimal("0.0040583195"),
    )
    # The valuation moves with every tick, so it never takes part in comparing holdings.
    assert set(position.holding()) == {"symbol", "qty", "currency", "asset_class"}


async def test_a_copied_position_reads_with_its_cost_value_and_gain(tmp_path, monkeypatch):
    datetime_type = dt.datetime

    class FixedDateTime(datetime_type):
        @classmethod
        def now(cls, tz=None):
            fixed = cls(2026, 1, 5, 15, 0, tzinfo=dt.UTC)
            return fixed if tz is None else fixed.astimezone(tz)

    monkeypatch.setattr(dt, "datetime", FixedDateTime)
    now = FixedDateTime(2026, 1, 5, 15, 0, tzinfo=dt.UTC)
    broker = ValuedBroker()
    owner = await _open(tmp_path, broker)
    try:
        await owner.recover_account(now)
        await owner.control_account(
            AccountControlCommand(command_id="enable", account_id="paper", action="resume"), now
        )
        buy = StockSignal.model_validate(event("valued", price="25.10", timestamp=now))
        await owner.receive(destination_signal(buy, account_id="paper"), now)
        for _ in range(3):
            await owner.cycle(now, halted=False)

        overview = await owner.operator_overview()
        [position] = [p for p in overview.positions if p.symbol == "ABC"]
        assert position.current_price == PRICE
        assert position.avg_entry_price == Decimal("25.10")
        assert position.market_value == position.owned_qty * PRICE
        assert position.unrealized_pl is not None
        assert position.unrealized_pl > 0
        [lot] = position.lots
        assert lot.unrealized_pl == ((PRICE - lot.average_price) * lot.remaining_qty).quantize(
            Decimal("0.01")
        )
    finally:
        await owner.close()
