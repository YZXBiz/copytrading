"""Alpaca's coin replies, as the paper account gave them on 23 October 2026, become the pair the
engine uses everywhere: BTC/USD, never BTCUSD (ADR-0014)."""

import datetime as dt
import json
from decimal import Decimal

import httpx
import pytest

from copytrading_engine.execution.adapters.alpaca.models import decode_positions
from copytrading_engine.execution.domain.orders import OrderPlan, OrderRequest
from copytrading_engine.execution.domain.sessions import Session

from .builders import make_broker

# GET /v2/assets/BTCUSD on paper, ids removed.
BTC_ASSET = {
    "attributes": ["fractional_eh_enabled"],
    "class": "crypto",
    "easy_to_borrow": False,
    "exchange": "CRYPTO",
    "fractionable": True,
    "marginable": False,
    "min_order_size": "0.000012307",
    "min_trade_increment": "0.000000001",
    "name": "Bitcoin  / US Dollar",
    "price_increment": "0.000000001",
    "shortable": False,
    "status": "active",
    "symbol": "BTC/USD",
    "tradable": True,
}
# GET /v2/positions after buying 0.000123071 BTC/USD: the 0.25% fee came out of the coin.
BTC_POSITION = {
    "asset_class": "crypto",
    "avg_entry_price": "81247.97",
    "cost_basis": "9.974245",
    "market_value": "9.973978",
    "qty": "0.000122763",
    "qty_available": "0.000122763",
    "symbol": "BTCUSD",
}


def test_a_coin_held_as_btcusd_is_the_btc_usd_pair_and_a_stock_is_unchanged():
    stock = {"asset_class": "us_equity", "qty": "2.779841", "symbol": "SOXL"}

    coin, soxl = decode_positions([BTC_POSITION, stock], account_currency="USD")

    assert (coin.symbol, coin.qty, coin.asset_class) == (
        "BTC/USD",
        Decimal("0.000122763"),
        "crypto",
    )
    assert soxl.symbol == "SOXL"


def test_a_coins_asset_is_asked_for_without_its_slash_and_keeps_its_steps():
    paths = []

    def handler(request):
        paths.append(request.url.path)
        return httpx.Response(200, json=BTC_ASSET)

    broker = make_broker("key", "secret", transport=httpx.MockTransport(handler))
    try:
        asset = broker.asset("BTC/USD")
    finally:
        broker.close()

    assert paths == ["/v2/assets/BTCUSD"]
    assert (asset.symbol, asset.crypto) == ("BTC/USD", True)
    assert (asset.min_order_size, asset.min_trade_increment, asset.price_increment) == (
        Decimal("0.000012307"),
        Decimal("0.000000001"),
        Decimal("0.000000001"),
    )


def test_a_coins_quote_comes_from_the_crypto_feed_at_any_hour():
    requests = []

    def handler(request):
        requests.append(request)
        return httpx.Response(
            200,
            json={
                "quotes": {
                    "BTC/USD": {
                        "ap": 81261.6,
                        "as": 0.0010094,
                        "bp": 81229.08,
                        "bs": 0.00100147,
                        "t": "2026-10-23T22:15:50.334081234Z",
                    }
                }
            },
        )

    broker = make_broker("key", "secret", transport=httpx.MockTransport(handler))
    try:
        quote = broker.quote("BTC/USD")
    finally:
        broker.close()

    [request] = requests
    assert request.url.host == "data.alpaca.markets"
    assert request.url.path == "/v1beta3/crypto/us/latest/quotes"
    assert request.url.params["symbols"] == "BTC/USD"
    assert (quote.feed, quote.bid, quote.ask) == ("crypto", Decimal("81229.08"), Decimal("81261.6"))
    assert quote.timestamp == dt.datetime(2026, 10, 23, 22, 15, 50, 334081, tzinfo=dt.UTC)


def test_a_coins_order_is_sent_good_till_canceled_with_no_hours():
    sent = []

    def handler(request):
        sent.append(json.loads(request.content))
        return httpx.Response(
            200,
            json={
                "id": "5a70a602-8ac3-4b4f-b70f-ffcca0d61a71",
                "client_order_id": "copy-coin",
                "symbol": "BTC/USD",
                "side": "buy",
                "qty": "0.000123071",
                "filled_qty": "0.000123071",
                "filled_avg_price": "81247.97",
                "status": "filled",
                "position_intent": "buy_to_open",
            },
        )

    plan = OrderPlan(
        symbol="BTC/USD",
        side="buy",
        position_intent="buy_to_open",
        qty=Decimal("0.000123071"),
        type="limit",
        limit_price=Decimal("81497.61"),
        source_price=Decimal("81497.61"),
        entry_tolerance_pct=Decimal(0),
        lot_id=None,
        entry_price=Decimal("81497.61"),
        session=Session.AROUND_THE_CLOCK,
    )
    broker = make_broker("key", "secret", transport=httpx.MockTransport(handler))
    try:
        filled = broker.submit(OrderRequest.for_plan(plan, "copy-coin", extended_hours=True))
    finally:
        broker.close()

    assert sent == [
        {
            "side": "buy",
            "position_intent": "buy_to_open",
            "type": "limit",
            "limit_price": "81497.61",
            "symbol": "BTC/USD",
            "qty": "0.000123071",
            "client_order_id": "copy-coin",
            "time_in_force": "gtc",
        }
    ]
    assert (filled.symbol, filled.filled_qty) == ("BTC/USD", Decimal("0.000123071"))


@pytest.mark.parametrize("extended", [True, False])
def test_a_stocks_order_is_still_a_day_order_marked_for_its_hours(extended):
    plan = OrderPlan(
        symbol="SOFI",
        side="buy",
        position_intent="buy_to_open",
        qty=Decimal(2),
        type="limit",
        limit_price=Decimal("25.25"),
        source_price=Decimal("25.25"),
        entry_tolerance_pct=Decimal(0),
        lot_id=None,
        entry_price=Decimal("25.25"),
        session=Session.EXTENDED if extended else Session.REGULAR,
    )

    request = OrderRequest.for_plan(plan, "copy-stock", extended_hours=extended)

    assert (request.time_in_force, request.extended_hours) == ("day", extended)
