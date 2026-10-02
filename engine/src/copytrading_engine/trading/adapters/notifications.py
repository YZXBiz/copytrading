"""Optional plain-text Telegram delivery for committed local notification outboxes."""

import asyncio
import http.client
import json
from collections.abc import Mapping

from copytrading_engine.shared.notification_models import NotificationPayload


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
