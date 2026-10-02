"""Opt-in: the native broker probe verifies real Alpaca paper credentials.

Runs only when COPYTRADING_TEST_ALPACA_KEY and COPYTRADING_TEST_ALPACA_SECRET are set, so CI and
ordinary local runs never need or see a credential. It reads account state, opens the live order
stream, and never places an order.
"""

import asyncio
import datetime as dt
import os

import pytest
from pydantic import SecretStr

from copytrading_engine.execution.adapters.alpaca.broker import AlpacaBroker, AlpacaCredentials
from copytrading_engine.execution.adapters.alpaca.order_stream import alpaca_order_stream
from copytrading_engine.execution.domain.market import HistoryWindow
from copytrading_engine.trading.adapters.capabilities import NativeCapabilityProbes
from copytrading_engine.trading.domain.config import AccountConfiguration, BrokerCredentials

_KEY = os.environ.get("COPYTRADING_TEST_ALPACA_KEY", "")
_SECRET = os.environ.get("COPYTRADING_TEST_ALPACA_SECRET", "")

pytestmark = pytest.mark.skipif(
    not (_KEY and _SECRET),
    reason="set COPYTRADING_TEST_ALPACA_KEY and COPYTRADING_TEST_ALPACA_SECRET",
)


async def test_paper_credentials_are_ready_and_identified():
    check = await NativeCapabilityProbes().broker(
        AccountConfiguration(id="paper-probe", environment="paper"),
        BrokerCredentials(account_id="paper-probe", key=SecretStr(_KEY), secret=SecretStr(_SECRET)),
    )

    assert check.state == "ready", check.reason_code
    assert check.environment == "paper"
    assert check.identity


async def test_paper_credentials_are_rejected_for_live_trading():
    check = await NativeCapabilityProbes().broker(
        AccountConfiguration(id="paper-probe", environment="live"),
        BrokerCredentials(account_id="paper-probe", key=SecretStr(_KEY), secret=SecretStr(_SECRET)),
    )

    assert check.state == "failed"


@pytest.mark.parametrize(
    "window",
    [
        HistoryWindow(range="day"),
        HistoryWindow(range="day", day=dt.date.today() - dt.timedelta(days=7)),
        HistoryWindow(range="week"),
        HistoryWindow(range="month"),
        HistoryWindow(range="three_months"),
        HistoryWindow(range="year"),
    ],
)
def test_paper_equity_history_decodes_from_the_real_endpoint(window):
    broker = AlpacaBroker(AlpacaCredentials(SecretStr(_KEY), SecretStr(_SECRET)), "paper")
    try:
        history = broker.equity_history(window)
    finally:
        broker.close()

    assert history.window == window
    assert all(point.at.tzinfo is not None for point in history.points)
    assert [point.at for point in history.points] == sorted(point.at for point in history.points)


async def test_paper_order_stream_authorizes_and_listens():
    """The live order stream really connects: the catch-up wake only follows auth and listen."""
    watch = alpaca_order_stream(AlpacaCredentials(SecretStr(_KEY), SecretStr(_SECRET)), "paper")
    stop = asyncio.Event()
    wakes: list[None] = []

    def on_update() -> None:
        wakes.append(None)
        stop.set()

    await asyncio.wait_for(watch(on_update, stop), timeout=20)

    assert wakes == [None]
