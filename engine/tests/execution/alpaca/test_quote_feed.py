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


def _after_hours(replies):
    """A broker at 18:50 New York time whose feeds answer from `replies`, by feed."""
    asked = []

    def handler(request):
        feed = request.url.params["feed"]
        asked.append(feed)
        reply = replies[feed]
        return reply if isinstance(reply, httpx.Response) else httpx.Response(200, json=reply)

    broker = AlpacaBroker(
        AlpacaCredentials(SecretStr("key"), SecretStr("secret")),
        "paper",
        transport=httpx.MockTransport(handler),
        clock=lambda: dt.datetime(2026, 10, 12, 18, 50, tzinfo=ET),
    )
    return broker, asked


def test_after_hours_the_newer_of_iex_and_the_delayed_tape_wins():
    # IEX's latest is the 16:00 close, hours old and wide; the tape is 15 minutes late but current.
    broker, asked = _after_hours(
        {
            "iex": {"quote": {"bp": 67.78, "ap": 75.02, "t": "2026-10-12T20:00:00Z"}},
            "delayed_sip": {"quote": {"bp": 70.62, "ap": 70.7, "t": "2026-10-12T22:36:10Z"}},
        }
    )
    try:
        quote = broker.quote("NFLX")
    finally:
        broker.close()

    assert asked == ["iex", "delayed_sip"]
    assert (quote.feed, str(quote.ask)) == ("delayed_sip", "70.7")


def test_after_hours_a_delayed_tape_that_fails_leaves_the_iex_quote():
    broker, _ = _after_hours(
        {
            "iex": {"quote": {"bp": 67.78, "ap": 75.02, "t": "2026-10-12T20:00:00Z"}},
            "delayed_sip": httpx.Response(403, json={"message": "forbidden"}),
        }
    )
    try:
        quote = broker.quote("NFLX")
    finally:
        broker.close()

    assert (quote.feed, str(quote.ask)) == ("iex", "75.02")


def test_in_regular_hours_only_iex_is_asked():
    requests = []

    def handler(request):
        requests.append(request.url.params["feed"])
        return httpx.Response(200, json={"quote": {"bp": 1, "ap": 2, "t": "2026-10-12T15:00:00Z"}})

    broker = AlpacaBroker(
        AlpacaCredentials(SecretStr("key"), SecretStr("secret")),
        "paper",
        transport=httpx.MockTransport(handler),
        clock=lambda: dt.datetime(2026, 10, 12, 11, 0, tzinfo=ET),
    )
    try:
        broker.quote("NFLX")
    finally:
        broker.close()

    assert requests == ["iex"]
