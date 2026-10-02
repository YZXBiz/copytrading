"""The Alpaca adapter talks only to its chosen endpoint and tells outages from absence."""

import httpx
import pytest

from copytrading_engine.execution.adapters.alpaca.broker import (
    LIVE_URL,
    PAPER_URL,
)
from copytrading_engine.execution.application.ports import BrokerError

from .builders import make_broker


def test_only_paper_endpoint_and_no_redirect_following():
    requests = []

    def handler(request):
        requests.append(request)
        return httpx.Response(302, headers={"Location": "https://api.alpaca.markets/v2/account"})

    broker = make_broker("example-key", "example-secret", transport=httpx.MockTransport(handler))
    with pytest.raises(BrokerError):
        broker.account()
    assert len(requests) == 1
    assert str(requests[0].url) == PAPER_URL + "/v2/account"
    broker.close()


def test_alpaca_exposes_the_application_owned_restore_evidence_port():
    from copytrading_engine.execution.application.ports import RestoreEvidenceBroker

    broker = make_broker(
        "key",
        "secret",
        transport=httpx.MockTransport(lambda _: httpx.Response(200, json=[])),
    )
    try:
        assert isinstance(broker, RestoreEvidenceBroker)
    finally:
        broker.close()


def test_live_endpoint_requires_explicit_environment():
    requests = []

    def handler(request):
        requests.append(request)
        return httpx.Response(503)

    broker = make_broker(
        "key", "secret", environment="live", transport=httpx.MockTransport(handler)
    )
    try:
        with pytest.raises(BrokerError):
            broker.account()
        assert str(requests[0].url) == LIVE_URL + "/v2/account"
    finally:
        broker.close()
    with pytest.raises(ValueError, match="paper or live"):
        make_broker("key", "secret", environment="invalid")


def test_order_not_found_differs_from_broker_outage():
    broker = make_broker(
        "example-key",
        "example-secret",
        transport=httpx.MockTransport(lambda r: httpx.Response(404)),
    )
    assert broker.lookup("missing") is None
    broker.close()
    broker = make_broker(
        "example-key",
        "example-secret",
        transport=httpx.MockTransport(lambda r: httpx.Response(503, text="sensitive response")),
    )
    with pytest.raises(BrokerError) as error:
        broker.lookup("unknown")
    assert "sensitive" not in str(error.value)
    broker.close()
