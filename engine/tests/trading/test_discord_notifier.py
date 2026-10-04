"""Discord alerts post plain text to a channel webhook and never let its URL escape in an error."""

import datetime as dt
import http.client
import json
from typing import ClassVar

import pytest

from copytrading_engine.shared.notification_models import NotificationPayload
from copytrading_engine.trading.adapters.notifications import (
    DiscordWebhookNotifier,
    TelegramNotifier,
    alert_sender,
    discord_webhook,
)
from copytrading_engine.trading.domain.config import NotificationConfiguration

URL = "https://discord.com/api/webhooks/1234567890/SECRET-WEBHOOK-TOKEN"


class FakeResponse:
    def __init__(self, status: int) -> None:
        self.status = status

    def read(self, amount: int) -> bytes:
        return b""


class FakeConnection:
    sent: ClassVar[list[tuple[str, str, str, dict]]] = []
    status = 204
    explode = False

    def __init__(self, host: str, timeout: float) -> None:
        self.host = host

    def request(self, method: str, path: str, *, body: bytes, headers: dict) -> None:
        if FakeConnection.explode:
            raise OSError(f"cannot reach https://{self.host}{path}")
        FakeConnection.sent.append((method, self.host, path, json.loads(body)))

    def getresponse(self) -> FakeResponse:
        return FakeResponse(FakeConnection.status)

    def close(self) -> None:
        pass


@pytest.fixture(autouse=True)
def fake_connection(monkeypatch):
    FakeConnection.sent, FakeConnection.status, FakeConnection.explode = [], 204, False
    monkeypatch.setattr(http.client, "HTTPSConnection", FakeConnection)


def payload(**annotations: str) -> NotificationPayload:
    return NotificationPayload(
        labels={}, annotations=annotations, starts_at=dt.datetime(2026, 1, 5, tzinfo=dt.UTC)
    )


async def test_an_alert_is_posted_to_the_webhook_without_mentions():
    await DiscordWebhookNotifier(URL).send(payload(summary="Bought NVDA", impact="@everyone 5 sh"))

    [(method, host, path, body)] = FakeConnection.sent
    assert (method, host, path) == (
        "POST",
        "discord.com",
        "/api/webhooks/1234567890/SECRET-WEBHOOK-TOKEN",
    )
    assert body["content"].startswith("Bought NVDA")
    assert body["allowed_mentions"] == {"parse": []}


async def test_a_long_alert_is_cut_to_discords_limit():
    await DiscordWebhookNotifier(URL).send(payload(summary="x" * 5000))

    assert len(FakeConnection.sent[0][3]["content"]) == 2000


@pytest.mark.parametrize("status", [400, 401, 404, 429, 500])
async def test_a_refused_or_failed_post_never_shows_the_url(status):
    FakeConnection.status = status
    with pytest.raises(RuntimeError) as refused:
        await DiscordWebhookNotifier(URL).send(payload(summary="hi"))
    assert "SECRET" not in str(refused.value)

    FakeConnection.explode = True
    with pytest.raises(RuntimeError) as failed:
        await DiscordWebhookNotifier(URL).send(payload(summary="hi"))
    assert "SECRET" not in str(failed.value)
    assert failed.value.__cause__ is None


@pytest.mark.parametrize(
    "url",
    [
        "http://discord.com/api/webhooks/1/abc",
        "https://evil.example/api/webhooks/1/abc",
        "https://discord.com/channels/1/2",
        "https://discord.com/api/webhooks/1/abc?wait=true",
        "https://user:pass@discord.com/api/webhooks/1/abc",
        "https://discord.com:8443/api/webhooks/1/abc",
        "not a url",
    ],
)
def test_only_a_discord_channel_webhook_is_accepted(url):
    with pytest.raises(ValueError, match="webhook URL") as rejected:
        discord_webhook(url)
    assert url not in str(rejected.value)


def test_canary_and_legacy_hosts_are_discord_too():
    for host in ("discordapp.com", "canary.discord.com", "ptb.discord.com"):
        assert discord_webhook(f"https://{host}/api/webhooks/1/abc") == (
            host,
            "/api/webhooks/1/abc",
        )


def test_the_configured_service_picks_the_sender():
    discord = alert_sender(NotificationConfiguration(service="discord"), URL)
    telegram = alert_sender(NotificationConfiguration(chat_id="42"), "123:TOKEN")

    assert isinstance(discord, DiscordWebhookNotifier)
    assert isinstance(telegram, TelegramNotifier)


def test_telegram_needs_a_chat_and_discord_takes_none():
    with pytest.raises(ValueError, match="chat ID"):
        NotificationConfiguration()
    with pytest.raises(ValueError, match="no chat ID"):
        NotificationConfiguration(service="discord", chat_id="42")
