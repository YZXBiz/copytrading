"""Alerts go out on their own: news only, and a failed send waits before it tries again."""

import asyncio
import datetime as dt

from copytrading_engine.shared.notification_models import NotificationIntent, NotificationPayload
from copytrading_engine.trading.application.alerts import AlertRelay

NOW = dt.datetime(2026, 10, 15, 15, tzinfo=dt.UTC)


def _payload(at: dt.datetime, summary: str) -> NotificationPayload:
    return NotificationPayload({"alertname": "test"}, {"summary": summary}, at)


class Outbox:
    def __init__(self, *intents: NotificationIntent) -> None:
        self.pending = list(intents)
        self.confirmed: list[str] = []

    async def claim_pending_notifications(self, limit: int = 100):
        return tuple(self.pending[:limit])

    async def confirm_notification(self, key: str) -> None:
        self.confirmed.append(key)
        self.pending = [item for item in self.pending if item.key != key]


class Account:
    def __init__(self, *rows: tuple[int, dt.datetime, str]) -> None:
        self.rows = {
            notification_id: {
                "labels": {"alertname": "fill"},
                "annotations": {"summary": summary},
                "starts_at": at.isoformat(),
            }
            for notification_id, at, summary in rows
        }
        self.confirmed: list[int] = []

    async def pending_notifications(self):
        return tuple((key, f"key-{key}", "stream", value) for key, value in self.rows.items())

    async def confirm_notification(self, notification_id: int) -> None:
        self.confirmed.append(notification_id)
        self.rows.pop(notification_id)


class Sender:
    def __init__(self, *, fail: bool = False) -> None:
        self.sent: list[str] = []
        self.attempts = 0
        self.fail = fail

    async def send(self, payload: NotificationPayload) -> None:
        self.attempts += 1
        if self.fail:
            raise RuntimeError("Telegram delivery is unavailable")
        self.sent.append(payload.annotations["summary"])


async def test_turning_alerts_on_sends_only_what_just_happened():
    """2,925 alerts waited undelivered in the paper ledgers, weeks of them, because alerts were
    off; turning alerts on would have sent every one. An alert older than an hour is dropped."""
    outbox = Outbox(
        NotificationIntent(
            key="old-post", stream_id="s", payload=_payload(NOW - dt.timedelta(days=9), "old post")
        ),
        NotificationIntent(
            key="new-post",
            stream_id="s",
            payload=_payload(NOW - dt.timedelta(minutes=2), "new post"),
        ),
    )
    account = Account((1, NOW - dt.timedelta(hours=3), "old fill"), (2, NOW, "new fill"))
    sender = Sender()
    relay = AlertRelay(sender, outbox, lambda: (account,), clock=lambda: NOW)

    await relay.deliver()

    assert sender.sent == ["new post", "new fill"]
    assert outbox.confirmed == ["old-post", "new-post"]
    assert account.confirmed == [1, 2]
    assert not relay.failing


async def test_a_failed_send_waits_before_the_next_try_and_keeps_its_alert():
    """A failed send was tried again every half second, inside the loop that copies posts."""
    outbox = Outbox(NotificationIntent(key="post", stream_id="s", payload=_payload(NOW, "post")))
    sender = Sender(fail=True)
    relay = AlertRelay(sender, outbox, tuple, clock=lambda: NOW, retry_seconds=(30,))
    stop = asyncio.Event()

    running = asyncio.create_task(relay.run(stop))
    await asyncio.sleep(0.2)
    stop.set()
    await asyncio.wait_for(running, timeout=1)

    assert sender.attempts == 1
    assert relay.failing
    assert outbox.confirmed == []

    sender.fail = False
    await relay.deliver()
    assert sender.sent == ["post"]
    assert not relay.failing
