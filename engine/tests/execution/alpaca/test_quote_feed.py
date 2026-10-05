"""Quotes come from the venue that is trading: Alpaca's overnight venue at night, IEX by day."""

import datetime as dt

import httpx
import pytest
from pydantic import SecretStr

from copytrading_engine.execution.adapters.alpaca.broker import AlpacaBroker, AlpacaCredentials
from copytrading_engine.execution.application.ports import BrokerResponseError

ET = dt.timezone(dt.timedelta(hours=-4))


@pytest.mark.parametrize(
    ("new_york", "feed"),
    [
        (dt.datetime(2026, 10, 4, 23, 43, tzinfo=ET), "overnight"),
        (dt.datetime(2026, 10, 5, 3, 59, tzinfo=ET), "overnight"),
        (dt.datetime(2026, 10, 5, 4, 0, tzinfo=ET), "iex"),
        (dt.datetime(2026, 10, 5, 12, 0, tzinfo=ET), "iex"),
        (dt.datetime(2026, 10, 5, 19, 59, tzinfo=ET), "iex"),
        (dt.datetime(2026, 10, 5, 20, 0, tzinfo=ET), "overnight"),
    ],
)
def test_a_quote_reads_the_venue_trading_at_that_hour(new_york, feed):
    requests = []

    def handler(request):
        requests.append(request)
        return httpx.Response(
            200, json={"quote": {"bp": 5.84, "ap": 5.9, "t": "2026-10-05T03:43:00Z"}}
        )

    broker = AlpacaBroker(
        AlpacaCredentials(SecretStr("key"), SecretStr("secret")),
        "paper",
        transport=httpx.MockTransport(handler),
        clock=lambda: new_york,
    )
    try:
        quote = broker.quote("SOUN")
    finally:
        broker.close()

    assert requests[0].url.params["feed"] == feed
    assert quote.feed == feed
    assert (str(quote.bid), str(quote.ask)) == ("5.84", "5.9")


def _broker(reply):
    return AlpacaBroker(
        AlpacaCredentials(SecretStr("key"), SecretStr("secret")),
        "paper",
        transport=httpx.MockTransport(lambda _request: httpx.Response(200, json=reply)),
        clock=lambda: dt.datetime(2026, 10, 5, 12, tzinfo=ET),
    )


def test_a_side_alpaca_reports_as_zero_has_no_price():
    broker = _broker({"quote": {"bp": 5.07, "ap": 0, "t": "2026-10-02T20:00:00Z"}})
    try:
        quote = broker.quote("SOUN")
    finally:
        broker.close()

    assert (str(quote.bid), quote.ask) == ("5.07", None)


def test_a_reply_without_a_quote_is_a_broker_response_error():
    broker = _broker({"message": "not found"})
    try:
        with pytest.raises(BrokerResponseError):
            broker.quote("SOUN")
    finally:
        broker.close()
