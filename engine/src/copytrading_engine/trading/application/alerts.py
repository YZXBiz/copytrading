"""Alerts leave the committed outboxes on their own task, so a slow or unreachable alert service
never holds up copying. A failed send waits longer before each new try, and an alert about
something long past is dropped instead of sent."""

import asyncio
import datetime as dt
import logging
from collections import deque
from collections.abc import Callable, Iterable, Mapping
from typing import Protocol

from copytrading_engine.parsing.relay import NotificationOutbox, deliver_notifications
from copytrading_engine.shared.notification_models import NotificationPayload

log = logging.getLogger(__name__)

# An alert says what just happened; one older than this is history, not news. It is marked
# delivered without being sent, so turning alerts on never replays weeks of them.
ALERT_MAX_AGE = dt.timedelta(hours=1)
# After a failed send the next try waits 5 seconds, then longer, up to 5 minutes.
ALERT_RETRY_SECONDS: tuple[float, ...] = (5, 15, 30, 60, 120, 300)
# Between passes while delivery works.
ALERT_IDLE_SECONDS = 1.0


class AlertSender(Protocol):
    async def send(self, payload: NotificationPayload) -> None: ...


class AccountAlerts(Protocol):
    async def pending_notifications(
        self,
    ) -> tuple[tuple[int, str, str, dict[str, object]], ...]: ...

    async def confirm_notification(self, notification_id: int) -> None: ...


class AlertRelay:
    """Deliver the parser's and every running account's alerts, oldest first."""

    def __init__(
        self,
        sender: AlertSender,
        parser: NotificationOutbox,
        accounts: Callable[[], Iterable[AccountAlerts]],
        *,
        announcements: deque[NotificationPayload] | None = None,
        clock: Callable[[], dt.datetime] = lambda: dt.datetime.now(dt.UTC),
        retry_seconds: tuple[float, ...] = ALERT_RETRY_SECONDS,
        idle_seconds: float = ALERT_IDLE_SECONDS,
    ) -> None:
        if not retry_seconds:
            raise ValueError("Alert retries need at least one wait")
        self._sender = sender
        self._parser = parser
        self._accounts = accounts
        # Alerts the runtime raises itself, such as an account that stopped. They are not in any
        # outbox: they stay here until sent, and a stopped account has no outbox left to read.
        self._announcements = announcements if announcements is not None else deque()
        self._clock = clock
        self._retry_seconds = retry_seconds
        self._idle_seconds = idle_seconds
        self._failures = 0

    @property
    def failing(self) -> bool:
        """The last pass could not send an alert."""
        return self._failures > 0

    async def run(self, stop: asyncio.Event) -> None:
        while not stop.is_set():
            await self.deliver()
            wait = (
                self._retry_seconds[min(self._failures, len(self._retry_seconds)) - 1]
                if self._failures
                else self._idle_seconds
            )
            try:
                await asyncio.wait_for(stop.wait(), timeout=wait)
            except TimeoutError:
                pass

    async def deliver(self) -> None:
        """One pass over every outbox. A failed send leaves its alert for the next pass."""
        try:
            while self._announcements:
                await self._send(self._announcements[0])
                self._announcements.popleft()
            await deliver_notifications(self._parser, lambda item: self._send(item.payload))
            for account in self._accounts():
                for notification_id, _, _, value in await account.pending_notifications():
                    await self._send(execution_alert(value))
                    await account.confirm_notification(notification_id)
        except Exception as exc:  # noqa: BLE001 - delivery failure is retried later
            self._failures += 1
            log.warning(
                "notification_delivery_failed type=%s failures=%d",
                type(exc).__name__,
                self._failures,
            )
            return
        self._failures = 0

    async def _send(self, payload: NotificationPayload) -> None:
        if self._clock() - payload.starts_at > ALERT_MAX_AGE:
            return
        await self._sender.send(payload)


def account_stopped_alert(account_id: str, at: dt.datetime) -> NotificationPayload:
    """Copying into an account stopped on its own and will not resume until the owner acts."""
    return NotificationPayload(
        labels={
            "alertname": "AccountStopped",
            "system": "copytrade",
            "job": "execution",
            "severity": "critical",
            "account_id": account_id,
        },
        annotations={
            "summary": f"Copying into {account_id} stopped",
            "evidence": "CopyTrading hit an error it could not recover from after several tries.",
            "impact": "No new orders are placed there. Orders already sent stay at Alpaca.",
            "action": "In CopyTrading, stop copying everywhere, then start again to reopen it.",
        },
        starts_at=at,
    )


def execution_alert(value: Mapping[str, object]) -> NotificationPayload:
    """An account outbox row's saved payload, validated."""
    labels = value.get("labels")
    annotations = value.get("annotations")
    starts_at = value.get("starts_at")
    if not isinstance(labels, dict) or not isinstance(annotations, dict):
        raise ValueError("Saved execution notification is invalid")
    if not isinstance(starts_at, str):
        raise ValueError("Saved execution notification timestamp is invalid")
    if not all(isinstance(k, str) and isinstance(v, str) for k, v in labels.items()):
        raise ValueError("Saved execution notification labels are invalid")
    if not all(isinstance(k, str) and isinstance(v, str) for k, v in annotations.items()):
        raise ValueError("Saved execution notification annotations are invalid")
    return NotificationPayload(labels, annotations, dt.datetime.fromisoformat(starts_at))
