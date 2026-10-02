"""Alpaca's live order updates: wake an account the moment one of its orders changes.

The stream only says *that* something changed. The account's own reconciliation reads the
broker and decides what it means, so a dropped or duplicated update can never corrupt state:
the periodic check still runs as a backup.
"""

import asyncio
import json
import logging
from collections.abc import Awaitable, Callable

import aiohttp

from copytrading_engine.execution.adapters.alpaca.broker import AlpacaCredentials

log = logging.getLogger(__name__)

STREAM_URLS = {
    "paper": "wss://paper-api.alpaca.markets/stream",
    "live": "wss://api.alpaca.markets/stream",
}
RETRY_SECONDS = (1.0, 2.0, 5.0, 10.0, 30.0)

type OrderStream = Callable[[Callable[[], None], asyncio.Event], Awaitable[None]]
type Connect = Callable[[str], Awaitable[aiohttp.ClientWebSocketResponse]]


class StreamRefused(Exception):
    """Alpaca did not authorize the stream."""


def alpaca_order_stream(
    credentials: AlpacaCredentials,
    environment: str,
    *,
    connect: Connect | None = None,
    retry_seconds: tuple[float, ...] = RETRY_SECONDS,
) -> OrderStream:
    """Watch one account's `trade_updates` until `stop`, reconnecting with backoff."""
    url = STREAM_URLS[environment]

    async def watch(on_update: Callable[[], None], stop: asyncio.Event) -> None:
        failures = 0
        while not stop.is_set():
            try:
                async with _Socket(url, connect) as socket:
                    await _authorize(socket, credentials)
                    await socket.send_json(
                        {"action": "listen", "data": {"streams": ["trade_updates"]}}
                    )
                    failures = 0
                    # Anything that changed while disconnected is caught up right away.
                    on_update()
                    # Stop closes the socket, ending a wait for a frame that may never come.
                    closer = asyncio.create_task(_close_on(stop, socket))
                    try:
                        async for frame in socket:
                            message = _message(frame)
                            if message is None:
                                break
                            if message.get("stream") == "trade_updates":
                                on_update()
                    finally:
                        closer.cancel()
                if stop.is_set():
                    return
            except asyncio.CancelledError:
                raise
            except Exception as exc:  # noqa: BLE001 - the periodic check covers any outage
                log.warning("order_stream_interrupted type=%s", type(exc).__name__)
            delay = retry_seconds[min(failures, len(retry_seconds) - 1)]
            failures += 1
            try:
                await asyncio.wait_for(stop.wait(), timeout=delay)
            except TimeoutError:
                pass

    return watch


async def _close_on(stop: asyncio.Event, socket: aiohttp.ClientWebSocketResponse) -> None:
    await stop.wait()
    await socket.close()


class _Socket:
    """One websocket connection, closed with its HTTP session on exit."""

    def __init__(self, url: str, connect: Connect | None) -> None:
        self._url = url
        self._connect = connect
        self._session: aiohttp.ClientSession | None = None
        self._socket: aiohttp.ClientWebSocketResponse | None = None

    async def __aenter__(self) -> aiohttp.ClientWebSocketResponse:
        if self._connect is not None:
            self._socket = await self._connect(self._url)
        else:
            self._session = aiohttp.ClientSession()
            self._socket = await self._session.ws_connect(self._url, heartbeat=20)
        return self._socket

    async def __aexit__(self, *_exc: object) -> None:
        if self._socket is not None:
            await self._socket.close()
        if self._session is not None:
            await self._session.close()


async def _authorize(
    socket: aiohttp.ClientWebSocketResponse, credentials: AlpacaCredentials
) -> None:
    await socket.send_json(
        {
            "action": "auth",
            "key": credentials.key.get_secret_value(),
            "secret": credentials.secret.get_secret_value(),
        }
    )
    reply = _message(await socket.receive(timeout=10))
    data = reply.get("data") if reply is not None else None
    if not isinstance(data, dict) or data.get("status") != "authorized":
        raise StreamRefused


def _message(frame: aiohttp.WSMessage) -> dict[str, object] | None:
    """A decoded JSON object, or None when the connection is closing or failed."""
    if frame.type == aiohttp.WSMsgType.TEXT:
        raw = frame.data
    elif frame.type == aiohttp.WSMsgType.BINARY:
        raw = frame.data.decode("utf-8", errors="replace")
    else:
        return None
    try:
        message = json.loads(raw)
    except ValueError:
        return {}
    return message if isinstance(message, dict) else {}
