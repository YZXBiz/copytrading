"""Replay-safe boundaries between capture, parsing, and downstream owners."""

from collections.abc import Awaitable, Callable
from typing import Protocol

from copytrading_engine.parsing.contracts import PendingSignal
from copytrading_engine.shared.notification_models import NotificationIntent
from copytrading_engine.shared.raw_message import RawMessage
from copytrading_engine.shared.signals import StockSignal
from copytrading_engine.sources.application import Delivery


class CapturedSources(Protocol):
    async def claim_batch(self, limit: int) -> tuple[Delivery, ...]: ...

    async def confirm(self, key: str) -> None: ...


class ParserInbox(Protocol):
    async def add(self, event: RawMessage) -> None: ...


class SignalOutbox(Protocol):
    async def claim_pending_signals(self, limit: int) -> tuple[PendingSignal, ...]: ...

    async def confirm_signal(self, key: str) -> None: ...


class NotificationOutbox(Protocol):
    async def claim_pending_notifications(self, limit: int) -> tuple[NotificationIntent, ...]: ...

    async def confirm_notification(self, key: str) -> None: ...


async def accept_live_sources(
    source: CapturedSources, parser: ParserInbox, *, limit: int = 100
) -> int:
    """Acknowledge capture only after the parser has durably accepted its identity."""
    deliveries = await source.claim_batch(limit)
    for delivery in deliveries:
        if delivery.mode != "live":
            raise RuntimeError("Historical capture reached the live parser relay")
        event = RawMessage.model_validate_json(delivery.payload)
        if event.identity != delivery.key:
            raise ValueError("Source delivery identity does not match its payload")
        await parser.add(event)
        await source.confirm(delivery.key)
    return len(deliveries)


async def deliver_signals(
    parser: SignalOutbox,
    receive: Callable[[StockSignal], Awaitable[None]],
    *,
    limit: int = 100,
) -> int:
    """Confirm only after a downstream owner has durably accepted the result."""
    deliveries = await parser.claim_pending_signals(limit)
    for pending in deliveries:
        await receive(pending.signal)
        await parser.confirm_signal(pending.key)
    return len(deliveries)


async def deliver_notifications(
    parser: NotificationOutbox,
    send: Callable[[NotificationIntent], Awaitable[None]],
    *,
    limit: int = 100,
) -> int:
    """A transport may resend after a crash; the key remains stable for dedupe."""
    deliveries = await parser.claim_pending_notifications(limit)
    for notification in deliveries:
        await send(notification)
        await parser.confirm_notification(notification.key)
    return len(deliveries)
