"""Paused accounts read live: balances and valuations from the broker, ownership from the ledger."""

import datetime as dt
from decimal import Decimal

from pydantic import SecretStr

from copytrading_engine.execution.application.ports import BrokerError
from copytrading_engine.execution.domain.market import HistoryWindow, Position
from copytrading_engine.execution.presentation.operator_views import (
    AccountOverview,
    PositionView,
    with_live_facts,
)
from copytrading_engine.trading.application.paused_reader import PausedAccountReader, ReadKeys

from ..execution.fakes import FakeBroker

NOW = dt.datetime(2026, 10, 9, 22, 0, tzinfo=dt.UTC)
KEYS = ReadKeys(
    account_id="primary", environment="paper", key=SecretStr("k"), secret=SecretStr("s")
)


class ReadOnly(FakeBroker):
    def __init__(self) -> None:
        super().__init__()
        self.reads = 0
        self.closed = False
        self.failing = False
        self.holdings["ABC"] = Decimal("4")

    def account(self):
        self.reads += 1
        if self.failing:
            raise BrokerError(503)
        return super().account()

    def close(self) -> None:
        self.closed = True


def _reader(broker: ReadOnly, clock: list[dt.datetime]) -> PausedAccountReader:
    reader = PausedAccountReader(lambda _: broker, clock=lambda: clock[0])
    reader.attach((KEYS,))
    return reader


async def test_reads_are_reused_briefly_then_read_again():
    broker, clock = ReadOnly(), [NOW]
    reader = _reader(broker, clock)
    first = await reader.facts("primary")
    assert first is not None
    assert first.positions[0].symbol == "ABC"
    await reader.facts("primary")
    assert broker.reads == 1
    clock[0] = NOW + dt.timedelta(seconds=11)
    await reader.facts("primary")
    assert broker.reads == 2


async def test_a_failed_read_keeps_the_last_answer_and_an_unknown_account_has_none():
    broker, clock = ReadOnly(), [NOW]
    reader = _reader(broker, clock)
    first = await reader.facts("primary")
    broker.failing = True
    clock[0] = NOW + dt.timedelta(seconds=30)
    assert await reader.facts("primary") == first
    assert await reader.facts("ira") is None


async def test_locking_forgets_the_keys_and_closes_the_clients():
    broker, clock = ReadOnly(), [NOW]
    reader = _reader(broker, clock)
    reader.detach()
    assert broker.closed
    assert not reader.holds("primary")
    assert await reader.facts("primary") is None
    assert await reader.equity_history("primary", HistoryWindow(range="day")) is None


def test_live_facts_value_the_ledgers_positions_and_add_the_owners_own():
    overview = AccountOverview(
        account_id="primary",
        environment="paper",
        active_configuration=True,
        broker_identity="b",
        entry_permission="enabled",
        recovery_preference="manual",
        readiness="processing_stopped",
        account_risk_status="unavailable",
        account_risk_reason="not_checked",
        account_activity_status="unavailable",
        account_activity_reason="not_checked",
        total_exposure_usd=None,
        app_cost_basis_usd=None,
        positions=(PositionView(symbol="ABC", owned_qty=Decimal("4"), external_qty=Decimal("0")),),
        unresolved_incidents=(),
        ownership_incidents=(),
        pending_orders=None,
        balance=None,
    )
    broker = FakeBroker()
    positions = (
        Position(
            symbol="ABC",
            qty=Decimal("4"),
            market_value=Decimal("100"),
            currency="USD",
            asset_class="us_equity",
        ),
        Position(
            symbol="XYZ",
            qty=Decimal("2"),
            market_value=Decimal("50"),
            currency="USD",
            asset_class="us_equity",
        ),
    )
    live = with_live_facts(overview, broker.account(), positions, NOW)
    assert [item.symbol for item in live.positions] == ["ABC", "XYZ"]
    assert live.positions[0].market_value == Decimal("100")
    assert live.positions[0].broker_qty == "4"
    assert live.positions[1].owned_qty == 0
    assert live.positions[1].broker_qty == "2"
    assert live.total_exposure_usd == Decimal("150")
    assert live.balance is not None
    assert live.balance.observed_at == NOW
