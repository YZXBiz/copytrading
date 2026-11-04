"""A symbol's five-minute bars: the latest session only, exact prices, every page read."""

import datetime as dt
from decimal import Decimal

import httpx
import pytest

from copytrading_engine.execution.application.ports import BrokerError

from .builders import make_broker

# Friday 20 Nov 2026 14:30 and 14:35 UTC, then Monday 23 Nov 14:30 UTC.
FRIDAY, FRIDAY_LATER, MONDAY = (
    "2026-11-20T14:30:00Z",
    "2026-11-20T14:35:00Z",
    "2026-11-23T14:30:00Z",
)
SUNDAY_NOON = dt.datetime(2026, 11, 22, 17, tzinfo=dt.UTC)


def _bar(at, open_, close):
    return {"t": at, "o": open_, "h": 99, "l": 1, "c": close, "v": 10, "n": 1, "vw": 5}


def _broker(handler):
    return make_broker(
        "key", "secret", transport=httpx.MockTransport(handler), clock=lambda: SUNDAY_NOON
    )


def test_a_stocks_bars_are_the_latest_session_at_their_exact_prices_over_every_page():
    requests = []

    def handler(request):
        requests.append(request)
        if "page_token" not in request.url.params:
            return httpx.Response(
                200,
                json={
                    "bars": [_bar(FRIDAY, 40.1, 40.2), _bar(FRIDAY_LATER, 40.2, 40.35)],
                    "next_page_token": "more",
                },
            )
        return httpx.Response(
            200, json={"bars": [_bar(MONDAY, 41.05, 41.1)], "next_page_token": None}
        )

    broker = _broker(handler)
    try:
        bars = broker.bars("SOXL")
    finally:
        broker.close()

    assert requests[0].url.path == "/v2/stocks/SOXL/bars"
    assert requests[0].url.params["timeframe"] == "5Min"
    assert requests[0].url.params["feed"] == "iex"
    # Sunday in New York: four days back reaches over the weekend to Wednesday's midnight.
    assert requests[0].url.params["start"] == "2026-11-18T00:00:00-05:00"
    assert requests[1].url.params["page_token"] == "more"
    # Only Monday's session, the latest, is kept.
    assert [(b.open, b.close) for b in bars] == [(Decimal("41.05"), Decimal("41.1"))]


def test_a_coins_bars_come_from_the_crypto_feed_keyed_by_its_pair():
    def handler(request):
        assert request.url.path == "/v1beta3/crypto/us/bars"
        assert request.url.params["symbols"] == "BTC/USD"
        return httpx.Response(200, json={"bars": {"BTC/USD": [_bar(FRIDAY, 90000, 90500.5)]}})

    broker = _broker(handler)
    try:
        (bar,) = broker.bars("BTC/USD")
    finally:
        broker.close()
    assert bar.close == Decimal("90500.5")


def test_a_symbol_with_no_bars_has_none_and_a_refusal_is_a_broker_error():
    broker = _broker(lambda request: httpx.Response(200, json={"bars": None}))
    try:
        assert broker.bars("SOXL") == ()
    finally:
        broker.close()
    broker = _broker(lambda request: httpx.Response(403, json={}))
    try:
        with pytest.raises(BrokerError):
            broker.bars("SOXL")
    finally:
        broker.close()
