"""A symbol's daily bars: the range plus a warm-up before it, exact prices, every page read."""

import datetime as dt
from decimal import Decimal

import httpx
import pytest

from copytrading_engine.execution.application.ports import BrokerError

from .builders import make_broker

# Sunday 22 Nov 2026 noon in New York.
SUNDAY_NOON = dt.datetime(2026, 11, 22, 17, tzinfo=dt.UTC)


def _bar(at, open_, high, low, close, volume=1000):
    return {"t": at, "o": open_, "h": high, "l": low, "c": close, "v": volume, "n": 1, "vw": 5}


def _broker(handler):
    return make_broker(
        "key", "secret", transport=httpx.MockTransport(handler), clock=lambda: SUNDAY_NOON
    )


def test_a_stocks_daily_bars_reach_back_over_the_range_and_its_warm_up_across_every_page():
    requests = []

    def handler(request):
        requests.append(request)
        if "page_token" not in request.url.params:
            return httpx.Response(
                200,
                json={
                    "bars": [_bar("2026-11-19T05:00:00Z", 40.1, 41.5, 39.9, 40.2, 5_000_000)],
                    "next_page_token": "more",
                },
            )
        return httpx.Response(
            200,
            json={
                "bars": [_bar("2026-11-20T05:00:00Z", 40.2, 40.9, 40.0, 40.35)],
                "next_page_token": None,
            },
        )

    broker = _broker(handler)
    try:
        bars = broker.daily_bars("SOXL", "six_months")
    finally:
        broker.close()

    first = requests[0].url
    assert first.path == "/v2/stocks/SOXL/bars"
    assert first.params["timeframe"] == "1Day"
    assert first.params["feed"] == "iex"
    assert first.params["adjustment"] == "split"
    # 183 days of range and 75 of warm-up before Sunday 22 Nov 2026.
    assert first.params["start"] == "2026-03-09T00:00:00-04:00"
    assert requests[1].url.params["page_token"] == "more"
    assert [(b.open, b.high, b.low, b.close, b.volume) for b in bars] == [
        (Decimal("40.1"), Decimal("41.5"), Decimal("39.9"), Decimal("40.2"), 5_000_000),
        (Decimal("40.2"), Decimal("40.9"), Decimal("40"), Decimal("40.35"), 1000),
    ]


def test_each_range_asks_for_its_own_stretch():
    starts = {}

    def handler(request):
        starts[len(starts)] = request.url.params["start"]
        return httpx.Response(200, json={"bars": []})

    broker = _broker(handler)
    try:
        for name in ("month", "six_months", "year"):
            assert broker.daily_bars("SOXL", name) == ()
    finally:
        broker.close()
    assert list(starts.values()) == [
        "2026-08-08T00:00:00-04:00",
        "2026-03-09T00:00:00-04:00",
        "2025-09-07T00:00:00-04:00",
    ]


def test_a_coins_daily_bars_come_from_the_crypto_feed_keyed_by_its_pair_with_fractional_volume():
    def handler(request):
        assert request.url.path == "/v1beta3/crypto/us/bars"
        assert request.url.params["symbols"] == "BTC/USD"
        assert "adjustment" not in request.url.params
        return httpx.Response(
            200,
            json={
                "bars": {
                    "BTC/USD": [_bar("2026-11-20T06:00:00Z", 90000, 91000, 89000, 90500.5, 12.7)]
                }
            },
        )

    broker = _broker(handler)
    try:
        (bar,) = broker.daily_bars("BTC/USD", "month")
    finally:
        broker.close()
    assert (bar.high, bar.close, bar.volume) == (Decimal("91000"), Decimal("90500.5"), 12)


def test_a_refusal_is_a_broker_error():
    broker = _broker(lambda request: httpx.Response(403, json={"message": "no"}))
    try:
        with pytest.raises(BrokerError):
            broker.daily_bars("SOXL", "month")
    finally:
        broker.close()
