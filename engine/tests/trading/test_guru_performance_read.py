"""The operator reads a guru's performance from a retained account: its ledger and journal on disk
for what was realized, the broker's price (when read keys are attached) for what is still open."""

import datetime as dt
from decimal import Decimal

import pytest
from pydantic import SecretStr

from copytrading_engine.execution.adapters.alpaca.broker import AlpacaCredentials
from copytrading_engine.execution.adapters.owner import ExecutionOwner
from copytrading_engine.execution.domain.lifecycle import AccountControlCommand
from copytrading_engine.execution.domain.market import Position
from copytrading_engine.execution.domain.signals import CopyConfig
from copytrading_engine.execution.domain.sizing import DestinationSignal
from copytrading_engine.shared.route_keys import guru_for_channel
from copytrading_engine.shared.signals import StockSignal
from copytrading_engine.trading.adapters.operator_queries import SQLiteOperatorEvidence
from copytrading_engine.trading.application.account_access import AccountAccess
from copytrading_engine.trading.application.operator_service import OperatorQueryService
from copytrading_engine.trading.application.paused_reader import PausedAccountReader, ReadKeys

from ..execution.builders import destination_signal, event
from ..execution.fakes import FakeBroker

GURU = guru_for_channel("discord", "demo")
NOW = dt.datetime(2026, 1, 5, 15, 0, tzinfo=dt.UTC)


def _delivery(message, now):
    guru = {"guru_id": GURU, "profile_revision": "a" * 64}
    terms = destination_signal(StockSignal.model_validate(message), account_id="paper").terms
    return DestinationSignal(
        signal=StockSignal.model_validate(message | guru), terms=terms.model_copy(update=guru)
    )


class PricedBroker(FakeBroker):
    """A read-only broker that says ABC is worth $30 a share."""

    def positions(self):
        return (
            Position(
                symbol="ABC",
                qty=Decimal("4"),
                market_value=Decimal("120"),
                current_price=Decimal("30"),
                currency="USD",
            ),
        )

    def close(self):
        pass


@pytest.fixture
async def copied(tmp_path, monkeypatch):
    """One buy and a half sold, left on disk by a real account owner that has since closed."""

    class FixedDateTime(dt.datetime):
        @classmethod
        def now(cls, tz=None):
            return NOW if tz is None else NOW.astimezone(tz)

    monkeypatch.setattr(dt, "datetime", FixedDateTime)
    broker = FakeBroker()
    owner = await ExecutionOwner.open(
        tmp_path / "accounts" / "paper",
        AlpacaCredentials(key=SecretStr("test"), secret=SecretStr("test")),
        CopyConfig(sources=("discord:demo",), recovery_preference="manual"),
        environment="paper",
        broker_factory=lambda _credentials, _environment: broker,
        account_lock_root=tmp_path / "locks",
    )
    try:
        await owner.recover_account(NOW)
        await owner.control_account(
            AccountControlCommand(command_id="on", account_id="paper", action="resume"), NOW
        )
        for message in (event("buy", price="25"), event("half", "reduce", "27")):
            await owner.receive(_delivery(message, NOW), NOW)
            await owner.cycle(NOW, halted=False)
        ledger = (await owner.observation()).ledger
    finally:
        await owner.close()
    return tmp_path, ledger


def _operator(tmp_path, reader=None):
    return OperatorQueryService(
        AccountAccess(
            tmp_path,
            lambda: {},
            configuration=lambda: None,
            runtime_state=lambda: "paused",
            evidence=SQLiteOperatorEvidence(),
        ),
        reader,
    )


async def test_realized_comes_from_the_retained_journal_and_unrealized_needs_a_price(copied):
    tmp_path, ledger = copied
    (buy,) = (o for o in ledger.orders.values() if o.side == "buy")
    (sell,) = (o for o in ledger.orders.values() if o.side == "sell")
    realized = ((sell.filled_avg_price - buy.filled_avg_price) * sell.filled_qty).quantize(
        Decimal("0.01")
    )

    performance = await _operator(tmp_path).guru_performance("paper", GURU)

    assert performance.realized_usd == realized
    assert performance.closed_trades == 1
    assert performance.unmatched_sells == 0
    # No read keys are attached, so what is still open has no price.
    assert performance.unrealized_usd is None


async def test_unrealized_is_the_open_shares_at_the_brokers_price(copied):
    tmp_path, ledger = copied
    (buy,) = (o for o in ledger.orders.values() if o.side == "buy")
    (lot,) = ledger.lots.values()
    reader = PausedAccountReader(lambda _: PricedBroker())
    operator = _operator(tmp_path, reader)
    operator.attach_readers(
        (
            ReadKeys(
                account_id="paper", environment="paper", key=SecretStr("k"), secret=SecretStr("s")
            ),
        )
    )

    performance = await operator.guru_performance("paper", GURU)

    expected = ((Decimal("30") - buy.filled_avg_price) * lot.remaining_qty).quantize(
        Decimal("0.01")
    )
    assert lot.remaining_qty > 0
    assert performance.unrealized_usd == expected


async def test_an_unknown_account_is_not_found(tmp_path):
    with pytest.raises(KeyError):
        await _operator(tmp_path).guru_performance("nobody", GURU)
