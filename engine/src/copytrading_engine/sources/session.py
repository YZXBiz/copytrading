"""Own one Discord connection, its callbacks, recovery barrier, and shutdown."""

import asyncio
import datetime as dt
import logging
import sys
from collections.abc import Awaitable, Callable, Set
from functools import wraps

import discord
from pydantic import JsonValue

from copytrading_engine.sources.application import (
    AttachmentReference,
    ForwardBatch,
    RecoveryCapture,
    SourceCapture,
)
from copytrading_engine.sources.recovery import RejectedCapture
from copytrading_engine.sources.source import (
    InvalidSourceMessage,
    adapter_event,
    attachment_references,
    envelope,
    require_history_channel,
)

log = logging.getLogger(__name__)


def _allowed_author(message: discord.Message, authors: Set[int] | None) -> bool:
    return authors is None or getattr(getattr(message, "author", None), "id", None) in authors


async def capture_message(
    message: discord.Message, box: SourceCapture, *, authors: Set[int] | None = None
) -> None:
    original_event = adapter_event(message)
    references = attachment_references(message)
    try:
        event = envelope(message)
    except InvalidSourceMessage as error:
        await box.reject(
            error.event, error.reason, source_event=original_event, attachments=references
        )
        log.error(
            "source_message_rejected channel=%s id=%s reason=%s",
            message.channel.id,
            message.id,
            error.reason,
        )
        return
    if _allowed_author(message, authors):
        await box.add(event, source_event=original_event, attachments=references)
    else:
        payload = event.model_dump(mode="json")
        await box.reject(
            payload, "author_not_configured", source_event=original_event, attachments=references
        )


async def recover_recent_messages(
    client: discord.Client,
    channels: Set[int],
    box: RecoveryCapture,
    *,
    now: dt.datetime | None = None,
    authors: Set[int] | None = None,
) -> None:
    """Page every accessible message after each durable channel cursor."""
    observed_at = now if now is not None else dt.datetime.now(dt.UTC)
    # Bound this pass, but commit only IDs returned by Discord. A clock-derived
    # fence is not proof that messages up to that ID have been captured.
    fence_id = discord.utils.time_snowflake(observed_at)
    fallback_id = discord.utils.time_snowflake(observed_at - dt.timedelta(seconds=120))
    for channel_id in sorted(channels):
        channel = client.get_channel(channel_id)
        if channel is None:
            channel = await client.fetch_channel(channel_id)
        source = require_history_channel(channel)
        start = await box.recovery_start(channel_id, fallback_id)
        last_id, bootstrap = start.last_id, start.bootstrap
        if last_id > fence_id:
            raise RuntimeError("Recovery cursor is ahead of the source clock")
        log.info("source_recovery_started channel=%s bootstrap=%s", channel_id, bootstrap)
        while last_id < fence_id:
            events = []
            rejected: list[RejectedCapture] = []
            source_events: dict[str, JsonValue] = {}
            attachments: dict[str, tuple[AttachmentReference, ...]] = {}
            page_last = last_id
            async for message in source.history(
                after=discord.Object(id=last_id),
                before=discord.Object(id=fence_id),
                oldest_first=True,
                limit=100,
            ):
                if not last_id < message.id < fence_id or message.id <= page_last:
                    raise RuntimeError("Discord history page is unordered or outside its cursor")
                page_last = message.id
                original_event = adapter_event(message)
                references = attachment_references(message)
                try:
                    event = envelope(message)
                    source_events[event.identity] = original_event
                    if _allowed_author(message, authors):
                        events.append(event)
                        attachments[event.identity] = references
                    else:
                        attachments[event.identity] = references
                        rejected.append(
                            RejectedCapture(event.model_dump(mode="json"), "author_not_configured")
                        )
                except InvalidSourceMessage as error:
                    identity = (
                        f"{error.event['source']}:{error.event['channel_id']}:{error.event['id']}"
                    )
                    source_events[identity] = original_event
                    attachments[identity] = references
                    rejected.append(RejectedCapture(error.event, error.reason))
                    log.error(
                        "source_message_rejected channel=%s id=%s reason=%s",
                        channel_id,
                        message.id,
                        error.reason,
                    )
            if page_last == last_id:
                break
            await box.capture_recovery_page(
                channel_id,
                events,
                rejected,
                page_last,
                source_events=source_events,
                attachments=attachments,
            )
            last_id = page_last
        log.info("source_recovery_complete channel=%s cursor=%s", channel_id, last_id)


class DiscordSession:
    """Expose lifecycle operations while keeping recovery and task state private."""

    def __init__(
        self,
        client: discord.Client,
        channels: Set[int],
        box: RecoveryCapture,
        stop: asyncio.Event,
        *,
        report_failure: Callable[[str, BaseException | None], None],
        authors: Set[int] | None = None,
    ) -> None:
        self._client = client
        self._channels = frozenset(channels)
        self._authors = frozenset(authors) if authors is not None else None
        self._box = box
        self._stop = stop
        self._report_failure = report_failure
        self._ready = asyncio.Event()
        self._publication_lock = asyncio.Lock()
        self._generation = 0
        self._closing = False
        self._callbacks: set[asyncio.Task] = set()
        self._connection: asyncio.Task[None] | None = None
        self._register("on_message", self._on_message)
        self._register("on_error", self._on_error)
        self._register("on_ready", self._recover)
        self._register("on_resumed", self._recover)
        self._register("on_disconnect", self._on_disconnect)

    @property
    def ready(self) -> bool:
        return not self._closing and self._client.is_ready() and self._ready.is_set()

    def start(self, token: str) -> None:
        """Start once; the caller must register close() before invoking this."""
        if self._connection is not None or self._closing:
            raise RuntimeError("Discord session cannot be started again")
        self._connection = asyncio.create_task(self._client.start(token))

    async def ensure_running(self) -> None:
        if self._connection is None:
            raise RuntimeError("Discord session has not started")
        if self._connection.done():
            await self._connection
            raise RuntimeError("Discord connection stopped")

    async def forward_if_ready(self, forwarder: ForwardBatch) -> None:
        """Hold the recovery barrier for the complete assigned delivery batch."""
        if not self.ready or self._stop.is_set():
            return
        async with self._publication_lock:
            if self.ready and not self._stop.is_set():
                await forwarder.flush()

    async def close(self) -> None:
        self._closing = True
        self._pause()
        try:
            await self._client.close()
        finally:
            tasks = list(self._callbacks)
            if self._connection is not None:
                tasks.append(self._connection)
            for task in tasks:
                task.cancel()
            await asyncio.gather(*tasks, return_exceptions=True)

    def _pause(self) -> int:
        self._generation += 1
        self._ready.clear()
        return self._generation

    def _register[**P](self, name: str, callback: Callable[P, Awaitable[None]]) -> None:
        @wraps(callback)
        async def tracked(*args: P.args, **kwargs: P.kwargs) -> None:
            if self._closing:
                return
            task = asyncio.current_task()
            if task is None:
                raise RuntimeError("Source callback has no owning task")
            self._callbacks.add(task)
            try:
                await callback(*args, **kwargs)
            finally:
                self._callbacks.discard(task)

        # Discord dispatches by the callback's name; methods remain private to this owner.
        tracked.__name__ = name
        self._client.event(tracked)

    async def _on_message(self, message: discord.Message) -> None:
        if message.channel.id in self._channels:
            await capture_message(message, self._box, authors=self._authors)

    async def _on_error(self, event: str, *args: object, **kwargs: object) -> None:
        del args, kwargs  # Discord callback values may contain private source data.
        self._report_failure(f"source_callback_failed callback={event}", sys.exception())
        self._stop.set()

    async def _recover(self) -> None:
        generation = self._pause()
        async with self._publication_lock:
            log.info("Discord connected; subscribed channels=%d", len(self._channels))
            await recover_recent_messages(
                self._client, self._channels, self._box, authors=self._authors
            )
            if (
                generation == self._generation
                and self._client.is_ready()
                and not self._stop.is_set()
                and not self._closing
            ):
                self._ready.set()

    async def _on_disconnect(self) -> None:
        self._pause()
