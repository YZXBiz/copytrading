"""Equity history keeps Alpaca's exact amounts for the chosen window."""

import datetime as dt
from decimal import Decimal

import httpx
import pytest

from copytrading_engine.execution.application.ports import BrokerError
from copytrading_engine.execution.domain.market import HistoryWindow

from .builders import make_broker

ACCOUNT = {
    "id": "paper-demo",
    "status": "ACTIVE",
    "cash": "5000",
    "equity": "25400",
    "last_equity": "24990.5",
    "buying_power": "5000",
    "currency": "USD",
    "trading_blocked": False,
    "account_blocked": False,
    "trade_suspended_by_user": False,
}


def test_equity_history_keeps_the_exact_amounts_alpaca_sent_and_skips_gaps():
    requests = []

    def handler(request):
        if request.url.path == "/v2/account":
            return httpx.Response(200, json=ACCOUNT)
        requests.append(request)
        return httpx.Response(
            200,
            json={
                "timestamp": [1790429400, 1790429700, 1790430000],
                "equity": [25000.1, None, 25412.8],
                "profit_loss": [0, None, 412.7],
                "base_value": 25000.1,
                "timeframe": "5Min",
            },
        )

    broker = make_broker(
        "key",
        "secret",
        transport=httpx.MockTransport(handler),
        clock=lambda: dt.datetime(2026, 10, 24, 5, 30, tzinfo=dt.UTC),
    )
    try:
        history = broker.equity_history(HistoryWindow(range="day"))
    finally:
        broker.close()
    assert requests[0].url.path == "/v2/account/portfolio/history"
    assert requests[0].url.params["period"] == "1D"
    assert requests[0].url.params["intraday_reporting"] == "continuous"
    # 5:30 UTC is 1:30 AM in New York: today starts at that midnight, not the UTC one.
    assert requests[0].url.params["start"] == "2026-10-24T00:00:00-04:00"
    # Today counts from the close the account's day change counts from, not Alpaca's history
    # base, which over a weekend is Thursday's close.
    assert history.base_value == Decimal("24990.5")
    assert [point.equity for point in history.points] == [Decimal("25000.1"), Decimal("25412.8")]
    assert history.points[0].at.timestamp() == 1790429400


def test_equity_history_series_of_different_lengths_cannot_cross_the_adapter():
    broker = make_broker(
        "key",
        "secret",
        transport=httpx.MockTransport(
            lambda _: httpx.Response(200, json={"timestamp": [1, 2], "equity": [1.0]})
        ),
    )
    try:
        with pytest.raises(BrokerError):
            broker.equity_history(HistoryWindow(range="month"))
    finally:
        broker.close()


@pytest.mark.parametrize(
    ("window", "expected"),
    [
        (
            HistoryWindow(range="week"),
            {"period": "1W", "timeframe": "15Min", "intraday_reporting": "continuous"},
        ),
        (HistoryWindow(range="three_months"), {"period": "3M", "timeframe": "1D"}),
        (HistoryWindow(range="year"), {"period": "1A", "timeframe": "1D"}),
        (
            HistoryWindow(range="day", day=dt.date(2026, 9, 25)),
            {"period": "1D", "timeframe": "1Min", "start": "2026-09-25T00:00:00-04:00"},
        ),
    ],
)
def test_equity_history_asks_alpaca_for_the_chosen_window(window, expected):
    requests: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        return httpx.Response(200, json={"timestamp": [], "equity": [], "base_value": 1})

    broker = make_broker("key", "secret", transport=httpx.MockTransport(handler))
    try:
        history = broker.equity_history(window)
    finally:
        broker.close()
    assert history.window == window
    assert {key: requests[0].url.params.get(key) for key in expected} == expected


def test_a_chosen_past_day_keeps_the_base_alpaca_sent():
    def handler(request: httpx.Request) -> httpx.Response:
        assert request.url.path == "/v2/account/portfolio/history"
        return httpx.Response(200, json={"timestamp": [], "equity": [], "base_value": 2900.64})

    broker = make_broker("key", "secret", transport=httpx.MockTransport(handler))
    try:
        history = broker.equity_history(HistoryWindow(range="day", day=dt.date(2026, 10, 23)))
    finally:
        broker.close()
    assert history.base_value == Decimal("2900.64")
