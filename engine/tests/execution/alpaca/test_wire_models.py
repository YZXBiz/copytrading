"""Alpaca wire payloads become strict domain values, or never cross the adapter."""

from decimal import Decimal

import httpx
import pytest

from copytrading_engine.execution.domain.market import Asset

from .builders import make_broker


def test_domain_asset_does_not_accept_alpaca_wire_alias():
    from pydantic import ValidationError

    with pytest.raises(ValidationError):
        Asset.model_validate(
            {
                "symbol": "AAPL",
                "class": "us_equity",
                "status": "active",
                "tradable": True,
                "fractionable": True,
            }
        )


def test_position_normalization_preserves_value_and_rejects_unknown_units():
    from decimal import Decimal

    from pydantic import ValidationError

    from copytrading_engine.execution.adapters.alpaca.models import decode_positions
    from copytrading_engine.execution.domain.risk import account_exposure

    actual_shaped = [
        {"symbol": "ABC", "qty": "100", "market_value": "2510.50", "asset_class": "us_equity"}
    ]
    unknown = decode_positions(actual_shaped)
    assert unknown[0].currency is None
    with pytest.raises(ValueError, match="valuation"):
        account_exposure(unknown, (), (), account_currency="USD")
    observed = decode_positions(actual_shaped, account_currency="USD")
    assert observed[0].market_value == Decimal("2510.50")
    assert observed[0].currency == "USD"
    assert account_exposure(observed, (), (), account_currency="USD").total == Decimal("2510.50")

    missing = decode_positions([{"symbol": "ABC", "qty": "100", "asset_class": "us_equity"}])
    assert missing[0].market_value is None
    with pytest.raises(ValueError, match="valuation"):
        account_exposure(missing, (), (), account_currency="USD")
    with pytest.raises(ValueError, match="currency"):
        account_exposure(observed, (), (), account_currency="EUR")
    contrary = decode_positions([actual_shaped[0] | {"currency": "EUR"}], account_currency="USD")
    assert contrary[0].currency == "EUR"
    with pytest.raises(ValueError, match="valuation"):
        account_exposure(contrary, (), (), account_currency="USD")
    with pytest.raises(ValidationError):
        decode_positions(
            [{"symbol": "ABC", "qty": "100", "market_value": "NaN", "asset_class": "us_equity"}]
        )


def test_broker_positions_use_verified_account_currency_for_missing_wire_currency():
    from decimal import Decimal

    from copytrading_engine.execution.application.ports import BrokerResponseError
    from copytrading_engine.execution.domain.risk import account_exposure

    account = {
        "id": "paper-demo",
        "status": "ACTIVE",
        "cash": "5000",
        "equity": "5000",
        "last_equity": "5000",
        "buying_power": "5000",
        "currency": "USD",
        "trading_blocked": False,
        "account_blocked": False,
        "trade_suspended_by_user": False,
    }
    calls = []
    position_currency = None

    def handler(request):
        calls.append(request.url.path)
        if request.url.path == "/v2/account":
            return httpx.Response(200, json=account)
        assert request.url.path == "/v2/positions"
        position = {
            "symbol": "ABC",
            "qty": "100",
            "market_value": "2510.50",
            "asset_class": "us_equity",
        }
        if position_currency is not None:
            position["currency"] = position_currency
        return httpx.Response(200, json=[position])

    broker = make_broker("key", "secret", transport=httpx.MockTransport(handler))
    try:
        positions = broker.positions()
        assert positions[0].currency == "USD"
        assert positions[0].market_value == Decimal("2510.50")
        assert calls == ["/v2/account", "/v2/positions"]
        position_currency = "EUR"
        contrary = broker.positions()
        assert contrary[0].currency == "EUR"
        with pytest.raises(ValueError, match="valuation"):
            account_exposure(contrary, (), (), account_currency="USD")
        account.pop("currency")
        with pytest.raises(BrokerResponseError):
            broker.positions()
    finally:
        broker.close()


@pytest.mark.parametrize("value", ["NaN", "Infinity", "-Infinity", True, None])
def test_invalid_account_money_is_rejected_without_response_details(value):
    from copytrading_engine.execution.application.ports import BrokerResponseError

    payload = {
        "id": "paper-demo",
        "status": "ACTIVE",
        "cash": value,
        "equity": "5000",
        "last_equity": "5000",
        "buying_power": "5000",
        "currency": "USD",
        "trading_blocked": False,
        "account_blocked": False,
        "trade_suspended_by_user": False,
        "private": "secret-detail",
    }
    broker = make_broker(
        "key", "secret", transport=httpx.MockTransport(lambda _: httpx.Response(200, json=payload))
    )
    try:
        with pytest.raises(BrokerResponseError) as error:
            broker.account()
        assert "secret-detail" not in str(error.value)
    finally:
        broker.close()


def test_typed_order_request_is_serialized_once_when_response_is_malformed():
    import json
    from decimal import Decimal

    from copytrading_engine.execution.application.ports import BrokerResponseError
    from copytrading_engine.execution.domain.orders import OrderRequest

    calls = []

    def handler(request):
        calls.append(json.loads(request.content))
        return httpx.Response(200, json={"unexpected": "private payload"})

    broker = make_broker("key", "secret", transport=httpx.MockTransport(handler))
    request = OrderRequest(
        symbol="ABC",
        side="buy",
        position_intent="buy_to_open",
        qty=Decimal("1.25"),
        type="limit",
        limit_price=Decimal("25.25"),
        client_order_id="copy-fixture",
        extended_hours=True,
    )
    try:
        with pytest.raises(BrokerResponseError):
            broker.submit(request)
        assert calls == [
            {
                "symbol": "ABC",
                "side": "buy",
                "position_intent": "buy_to_open",
                "qty": "1.25",
                "limit_price": "25.25",
                "client_order_id": "copy-fixture",
                "type": "limit",
                "time_in_force": "day",
                "extended_hours": True,
            }
        ]
    finally:
        broker.close()


@pytest.mark.parametrize(
    "changes",
    [
        {"filled_qty": "2"},
        {"filled_qty": "1", "filled_avg_price": None},
        {"filled_qty": "NaN"},
        {"filled_avg_price": "Infinity"},
        {"qty": "0"},
        {"status": "filled", "filled_qty": "0"},
    ],
)
def test_invalid_broker_fills_cannot_cross_the_adapter(changes):
    from copytrading_engine.execution.application.ports import BrokerResponseError

    payload = {
        "id": "broker-1",
        "client_order_id": "copy-1",
        "symbol": "ABC",
        "side": "buy",
        "qty": "1",
        "filled_qty": "0",
        "filled_avg_price": None,
        "status": "new",
    } | changes
    broker = make_broker(
        "key", "secret", transport=httpx.MockTransport(lambda _: httpx.Response(200, json=payload))
    )
    try:
        with pytest.raises(BrokerResponseError):
            broker.lookup("copy-1")
    finally:
        broker.close()


def test_market_sell_payload_has_no_limit_price_and_is_never_retried():
    import json

    from copytrading_engine.execution.application.ports import BrokerResponseError
    from copytrading_engine.execution.domain.orders import OrderRequest

    calls = []

    def handler(request):
        calls.append(json.loads(request.content))
        return httpx.Response(200, json={"malformed": True})

    broker = make_broker("key", "secret", transport=httpx.MockTransport(handler))
    try:
        with pytest.raises(BrokerResponseError):
            broker.submit(
                OrderRequest(
                    symbol="ABC",
                    side="sell",
                    position_intent="sell_to_close",
                    qty=Decimal("1.170905"),
                    type="market",
                    client_order_id="copy-market",
                    extended_hours=False,
                )
            )
        assert calls == [
            {
                "symbol": "ABC",
                "side": "sell",
                "position_intent": "sell_to_close",
                "qty": "1.170905",
                "type": "market",
                "client_order_id": "copy-market",
                "time_in_force": "day",
                "extended_hours": False,
            }
        ]
    finally:
        broker.close()


@pytest.mark.parametrize(
    "changes",
    [
        {"limit_price": "27"},
        {"extended_hours": True},
        {"side": "buy"},
        {"type": "limit"},
    ],
)
def test_invalid_market_order_terms_are_rejected(changes):
    from pydantic import ValidationError

    from copytrading_engine.execution.domain.orders import OrderRequest

    with pytest.raises(ValidationError):
        OrderRequest.model_validate(
            {
                "symbol": "ABC",
                "side": "sell",
                "qty": "1",
                "type": "market",
                "client_order_id": "copy-market",
                "extended_hours": False,
            }
            | changes
        )
