"""Paused accounts read live: balances and valuations from the broker, ownership from the ledger."""

import datetime as dt
from decimal import Decimal

import pytest
from pydantic import SecretStr

from copytrading_engine.execution.application.ports import BrokerError
from copytrading_engine.execution.domain.market import (
    Bar,
    DailyBar,
    DailyRange,
    HistoryWindow,
    Position,
    Quote,
)
from copytrading_engine.execution.presentation.operator_views import (
    AccountOverview,
    PositionView,
    with_live_facts,
)
from copytrading_engine.trading.adapters.operator_queries import SQLiteOperatorEvidence
from copytrading_engine.trading.application.account_access import AccountAccess
from copytrading_engine.trading.application.operator_service import OperatorQueryService
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
        self.quotes = 0
        self.quoted: Quote | None = Quote(
            feed="iex", bid=Decimal("226.5"), ask=Decimal("226.56"), timestamp=NOW
        )

    def quote(self, symbol: str) -> Quote:
        self.quotes += 1
        if self.quoted is None:
            raise BrokerError(404)
        return self.quoted

    def account(self):
        self.reads += 1
        if self.failing:
            raise BrokerError(503)
        return super().account()

    def close(self) -> None:
        self.closed = True


class WithBars(ReadOnly):
    def __init__(self) -> None:
        super().__init__()
        self.asked: list[str] = []
        self.bar_failing = False

    def bars(self, symbol: str) -> tuple[Bar, ...]:
        self.asked.append(symbol)
        if self.bar_failing:
            raise BrokerError(503)
        return (Bar(at=NOW, open=Decimal("40"), close=Decimal("41")),)


class WithDailyBars(ReadOnly):
    def __init__(self) -> None:
        super().__init__()
        self.asked: list[tuple[str, DailyRange]] = []
        self.failing_daily = False

    def daily_bars(self, symbol: str, period: DailyRange) -> tuple[DailyBar, ...]:
        self.asked.append((symbol, period))
        if self.failing_daily:
            raise BrokerError(503)
        return (
            DailyBar(
                at=NOW,
                open=Decimal("40"),
                high=Decimal("42"),
                low=Decimal("39.5"),
                close=Decimal("41"),
                volume=1200,
            ),
        )


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


async def test_a_quote_is_reused_for_two_seconds_then_asked_again():
    broker, clock = ReadOnly(), [NOW]
    reader = _reader(broker, clock)
    first = await reader.quote("primary", "AAPL")
    assert first is not None
    assert first.ask == Decimal("226.56")
    await reader.quote("primary", "AAPL")
    assert broker.quotes == 1
    await reader.quote("primary", "MSFT")
    assert broker.quotes == 2
    clock[0] = NOW + dt.timedelta(seconds=3)
    await reader.quote("primary", "AAPL")
    assert broker.quotes == 3


async def test_an_unknown_symbol_or_an_empty_book_has_no_quote():
    broker, clock = ReadOnly(), [NOW]
    reader = _reader(broker, clock)
    broker.quoted = None
    assert await reader.quote("primary", "ZZZZ") is None
    broker.quoted = Quote(feed="overnight", bid=None, ask=None, timestamp=None)
    assert await reader.quote("primary", "EMPTY") is None
    assert await reader.quote("ira", "AAPL") is None
    reader.detach()
    assert await reader.quote("primary", "AAPL") is None


async def test_history_of_an_account_with_a_record_but_no_keys_is_empty_not_missing(tmp_path):
    # Copying has not started in this engine yet (an app relaunch) and no keys are attached: the
    # account is listed from its record, so its history is "nothing yet", never "not found".
    (tmp_path / "accounts" / "primary").mkdir(parents=True)
    (tmp_path / "accounts" / "primary" / "execution.sqlite3").touch()
    service = OperatorQueryService(
        AccountAccess(
            tmp_path,
            lambda: {},
            configuration=lambda: None,
            runtime_state=lambda: "paused",
            evidence=SQLiteOperatorEvidence(),
        )
    )
    window = HistoryWindow(range="month")
    assert await service.equity_history("primary", window) is None
    with pytest.raises(KeyError):
        await service.equity_history("ira", window)


async def test_bars_are_read_once_a_minute_per_symbol_and_forgotten_when_locked():
    broker, clock = WithBars(), [NOW]
    reader = _reader(broker, clock)
    first = await reader.bars("primary", ("ABC", "DEF"))
    assert set(first) == {"ABC", "DEF"}
    assert first["ABC"][0].close == Decimal("41")
    clock[0] = NOW + dt.timedelta(seconds=59)
    await reader.bars("primary", ("ABC",))
    assert broker.asked == ["ABC", "DEF"]
    clock[0] = NOW + dt.timedelta(seconds=61)
    await reader.bars("primary", ("ABC",))
    assert broker.asked == ["ABC", "DEF", "ABC"]
    reader.detach()
    assert await reader.bars("primary", ("ABC",)) == {}


async def test_a_failed_bars_read_keeps_the_last_answer_or_has_none():
    broker, clock = WithBars(), [NOW]
    reader = _reader(broker, clock)
    broker.bar_failing = True
    assert await reader.bars("primary", ("ABC",)) == {"ABC": ()}
    broker.bar_failing = False
    first = await reader.bars("primary", ("ABC",))
    broker.bar_failing = True
    clock[0] = NOW + dt.timedelta(seconds=120)
    assert await reader.bars("primary", ("ABC",)) == first


async def test_daily_bars_are_read_once_in_five_minutes_per_symbol_and_range_and_forgotten_when_locked():
    broker, clock = WithDailyBars(), [NOW]
    reader = _reader(broker, clock)
    first = await reader.daily_bars("primary", "ABC", "six_months")
    assert first[0].close == Decimal("41")
    clock[0] = NOW + dt.timedelta(seconds=299)
    assert await reader.daily_bars("primary", "ABC", "six_months") == first
    await reader.daily_bars("primary", "ABC", "year")
    await reader.daily_bars("primary", "DEF", "six_months")
    assert broker.asked == [("ABC", "six_months"), ("ABC", "year"), ("DEF", "six_months")]
    clock[0] = NOW + dt.timedelta(seconds=301)
    await reader.daily_bars("primary", "ABC", "six_months")
    assert broker.asked[-1] == ("ABC", "six_months")
    assert len(broker.asked) == 4
    reader.detach()
    assert await reader.daily_bars("primary", "ABC", "six_months") == ()


async def test_a_failed_daily_bars_read_keeps_the_last_answer_or_has_none():
    broker, clock = WithDailyBars(), [NOW]
    reader = _reader(broker, clock)
    broker.failing_daily = True
    assert await reader.daily_bars("primary", "ABC", "month") == ()
    broker.failing_daily = False
    first = await reader.daily_bars("primary", "ABC", "month")
    broker.failing_daily = True
    clock[0] = NOW + dt.timedelta(minutes=10)
    assert await reader.daily_bars("primary", "ABC", "month") == first
