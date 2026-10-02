"""Equity history keeps Alpaca's exact amounts for the chosen window."""

import datetime as dt
from decimal import Decimal

import httpx
import pytest

from copytrading_engine.execution.application.ports import BrokerError
from copytrading_engine.execution.domain.market import HistoryWindow

from .builders import make_broker


def test_equity_history_keeps_the_exact_amounts_alpaca_sent_and_skips_gaps():
    requests = []

    def handler(request):
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

    broker = make_broker("key", "secret", transport=httpx.MockTransport(handler))
    try:
        history = broker.equity_history(HistoryWindow(range="day"))
    finally:
        broker.close()
    assert requests[0].url.path == "/v2/account/portfolio/history"
    assert requests[0].url.params["period"] == "1D"
    assert "start" not in requests[0].url.params
    assert history.base_value == Decimal("25000.1")
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
        (HistoryWindow(range="week"), {"period": "1W", "timeframe": "1H"}),
        (HistoryWindow(range="three_months"), {"period": "3M", "timeframe": "1D"}),
        (HistoryWindow(range="year"), {"period": "1A", "timeframe": "1D"}),
        (
            HistoryWindow(range="day", day=dt.date(2026, 9, 25)),
            {"period": "1D", "timeframe": "5Min", "start": "2026-09-25T00:00:00-04:00"},
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
