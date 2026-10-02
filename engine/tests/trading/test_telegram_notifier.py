"""Telegram delivery sends plain text and never lets the bot token escape in an error."""

import datetime as dt
import http.client
import json
from typing import ClassVar

import pytest

from copytrading_engine.shared.notification_models import NotificationPayload
from copytrading_engine.trading.adapters.notifications import TelegramNotifier

TOKEN = "123456:SECRET-BOT-TOKEN"


class FakeResponse:
    def __init__(self, status: int) -> None:
        self.status = status

    def read(self, amount: int) -> bytes:
        return b"{}"


class FakeConnection:
    sent: ClassVar[list[tuple[str, str, dict, dict]]] = []
    status = 200
    explode = False
    closed = 0

    def __init__(self, host: str, timeout: float) -> None:
        self.host = host

    def request(self, method: str, path: str, *, body: bytes, headers: dict) -> None:
        if FakeConnection.explode:
            raise OSError(f"cannot reach https://{self.host}{path}")
        FakeConnection.sent.append((method, path, json.loads(body), headers))

    def getresponse(self) -> FakeResponse:
        return FakeResponse(FakeConnection.status)

    def close(self) -> None:
        FakeConnection.closed += 1


@pytest.fixture(autouse=True)
def fake_connection(monkeypatch):
    FakeConnection.sent, FakeConnection.status, FakeConnection.explode = [], 200, False
    FakeConnection.closed = 0
    monkeypatch.setattr(http.client, "HTTPSConnection", FakeConnection)


def payload(**annotations: str) -> NotificationPayload:
    return NotificationPayload(
        labels={}, annotations=annotations, starts_at=dt.datetime(2026, 1, 5, tzinfo=dt.UTC)
    )


def test_a_notifier_needs_both_a_token_and_a_chat():
    for token, chat in (("", "42"), (TOKEN, "")):
        with pytest.raises(ValueError, match="required"):
            TelegramNotifier(token, chat)


async def test_a_notification_is_posted_as_plain_text_to_the_chat():
    await TelegramNotifier(TOKEN, "42").send(
        payload(summary="Bought NVDA", action="Check Activity")
    )

    [(method, path, body, headers)] = FakeConnection.sent
    assert (method, path) == ("POST", f"/bot{TOKEN}/sendMessage")
    assert body == {"chat_id": "42", "text": "Bought NVDA\n\nCheck Activity"}
    assert headers == {"Content-Type": "application/json"}
    assert FakeConnection.closed == 1


async def test_a_refused_delivery_fails_without_the_token():
    FakeConnection.status = 401

    with pytest.raises(RuntimeError) as failure:
        await TelegramNotifier(TOKEN, "42").send(payload(summary="x"))

    assert TOKEN not in str(failure.value)
    assert TOKEN not in repr(failure.value.__cause__)
    assert FakeConnection.closed == 1


async def test_a_network_error_is_replaced_before_it_can_carry_the_token():
    FakeConnection.explode = True

    with pytest.raises(RuntimeError, match="unavailable") as failure:
        await TelegramNotifier(TOKEN, "42").send(payload(summary="x"))

    assert failure.value.__cause__ is None
    assert TOKEN not in str(failure.value)


async def test_a_message_orders_its_fields_and_stays_under_the_telegram_limit():
    notifier = TelegramNotifier(TOKEN, "42")

    await notifier.send(payload(action="A", summary="S", impact="I", evidence="E"))
    await notifier.send(payload())
    await notifier.send(payload(summary="x" * 5000))

    texts = [body["text"] for _, _, body, _ in FakeConnection.sent]
    assert texts[0] == "S\n\nE\n\nI\n\nA"
    assert texts[1] == "Trading update"
    assert len(texts[2]) == 3900
