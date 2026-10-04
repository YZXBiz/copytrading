"""Optional plain-text alert delivery, to Telegram or a Discord webhook, for committed local
notification outboxes."""

import asyncio
import http.client
import json
from collections.abc import Mapping
from typing import Protocol
from urllib.parse import urlsplit

from copytrading_engine.shared.notification_models import NotificationPayload
from copytrading_engine.trading.domain.config import NotificationConfiguration

_DISCORD_HOSTS = frozenset(
    {"discord.com", "discordapp.com", "ptb.discord.com", "canary.discord.com"}
)
# Discord rejects a message longer than this.
_DISCORD_MESSAGE_LIMIT = 2000


class AlertSender(Protocol):
    async def send(self, payload: NotificationPayload) -> None: ...


def alert_sender(configuration: NotificationConfiguration, secret: str) -> AlertSender:
    """The sender for the configured service; the secret is a bot token or a webhook URL."""
    if configuration.service == "discord":
        return DiscordWebhookNotifier(secret)
    if configuration.chat_id is None:
        raise ValueError("Telegram alerts need a chat ID")
    return TelegramNotifier(secret, configuration.chat_id)


def discord_webhook(url: str) -> tuple[str, str]:
    """The host and path of a Discord webhook URL, or ValueError; never echoes the URL, which holds
    the webhook's secret."""
    parts = urlsplit(url.strip())
    if (
        parts.scheme != "https"
        or parts.hostname not in _DISCORD_HOSTS
        or parts.port is not None
        or parts.username
        or parts.password
        or parts.query
        or parts.fragment
        or not parts.path.startswith("/api/webhooks/")
        or len(parts.path.split("/")) != 5
    ):
        raise ValueError("Discord alerts need a channel webhook URL")
    return parts.hostname, parts.path


class DiscordWebhookNotifier:
    def __init__(self, url: str) -> None:
        self._host, self._path = discord_webhook(url)

    async def send(self, payload: NotificationPayload) -> None:
        await asyncio.to_thread(self._send, _render(payload.annotations))

    def _send(self, text: str) -> None:
        connection = http.client.HTTPSConnection(self._host, timeout=5)
        try:
            body = json.dumps(
                {
                    "content": text[:_DISCORD_MESSAGE_LIMIT],
                    # An alert never pings anyone, whatever its text says.
                    "allowed_mentions": {"parse": []},
                }
            ).encode()
            connection.request(
                "POST", self._path, body=body, headers={"Content-Type": "application/json"}
            )
            response = connection.getresponse()
            response.read(4096)
            if response.status not in {200, 204}:
                raise RuntimeError("Discord delivery was not accepted")
        except Exception:  # noqa: BLE001 - replace URL-bearing errors before re-raising
            # HTTP exception strings can contain the webhook path, which is its secret.
            raise RuntimeError("Discord delivery is unavailable") from None
        finally:
            connection.close()


class TelegramNotifier:
    def __init__(self, token: str, chat_id: str) -> None:
        if not token or not chat_id:
            raise ValueError("Telegram token and chat ID are required")
        self._token = token
        self._chat_id = chat_id

    async def send(self, payload: NotificationPayload) -> None:
        await asyncio.to_thread(self._send, _render(payload.annotations))

    def _send(self, text: str) -> None:
        connection = http.client.HTTPSConnection("api.telegram.org", timeout=5)
        try:
            body = json.dumps({"chat_id": self._chat_id, "text": text}).encode()
            connection.request(
                "POST",
                f"/bot{self._token}/sendMessage",
                body=body,
                headers={"Content-Type": "application/json"},
            )
            response = connection.getresponse()
            response.read(4096)
            if response.status != 200:
                raise RuntimeError("Telegram delivery was not accepted")
        except Exception:  # noqa: BLE001 - replace token-bearing errors before re-raising
            # HTTP exception strings and URLs can contain the bot token.
            raise RuntimeError("Telegram delivery is unavailable") from None
        finally:
            connection.close()


def _render(annotations: Mapping[str, str]) -> str:
    parts = [annotations.get("summary", "Trading update")]
    for field in ("evidence", "impact", "action"):
        value = annotations.get(field)
        if value:
            parts.append(value)
    return "\n\n".join(parts)[:3900]
