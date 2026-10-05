"""Alpaca's live order stream wakes an account on every order change and survives outages."""

import asyncio
import json

import aiohttp
from aiohttp import web
from pydantic import SecretStr

from copytrading_engine.execution.adapters.alpaca.broker import AlpacaCredentials
from copytrading_engine.execution.adapters.alpaca.order_stream import alpaca_order_stream

CREDENTIALS = AlpacaCredentials(SecretStr("key-id"), SecretStr("secret-value"))


class _FakeAlpaca:
    """A local stand-in for Alpaca's trading stream, replying in binary frames like paper does."""

    def __init__(self, *, authorize: bool = True, updates: int = 1, drop: bool = False) -> None:
        self.authorize = authorize
        self.updates = updates
        self.drop = drop
        self.connections = 0
        self.received: list[dict] = []

    async def handle(self, request: web.Request) -> web.WebSocketResponse:
        socket = web.WebSocketResponse()
        await socket.prepare(request)
        self.connections += 1
        auth = json.loads((await socket.receive()).data)
        self.received.append(auth)
        status = "authorized" if self.authorize else "unauthorized"
        reply = {"stream": "authorization", "data": {"action": "authenticate", "status": status}}
        await socket.send_bytes(json.dumps(reply).encode())
        if not self.authorize:
            await socket.close()
            return socket
        self.received.append(json.loads((await socket.receive()).data))
        listening = {"stream": "listening", "data": {"streams": ["trade_updates"]}}
        await socket.send_bytes(json.dumps(listening).encode())
        for _ in range(self.updates):
            update = {"stream": "trade_updates", "data": {"event": "fill"}}
            await socket.send_bytes(json.dumps(update).encode())
        if self.drop and self.connections == 1:
            await socket.close()
            return socket
        async for _ in socket:
            pass
        return socket


async def _serve(fake: _FakeAlpaca):
    app = web.Application()
    app.router.add_get("/stream", fake.handle)
    runner = web.AppRunner(app)
    await runner.setup()
    site = web.TCPSite(runner, "127.0.0.1", 0)
    await site.start()
    port = site._server.sockets[0].getsockname()[1]
    session = aiohttp.ClientSession()

    async def connect(_url: str) -> aiohttp.ClientWebSocketResponse:
        return await session.ws_connect(f"http://127.0.0.1:{port}/stream")

    async def close() -> None:
        await session.close()
        await runner.cleanup()

    return connect, close


async def _watch_until(watch, stop: asyncio.Event, done, live: list[bool] | None = None):
    updates: list[None] = []

    def on_update() -> None:
        updates.append(None)
        if done(updates):
            stop.set()

    on_live = live.append if live is not None else lambda _value: None
    await asyncio.wait_for(watch(on_update, on_live, stop), timeout=5)
    return updates


async def test_each_order_change_wakes_the_account_after_authorizing():
    fake = _FakeAlpaca(updates=2)
    connect, close = await _serve(fake)
    stop = asyncio.Event()
    try:
        watch = alpaca_order_stream(CREDENTIALS, "paper", connect=connect)
        updates = await _watch_until(watch, stop, lambda seen: len(seen) >= 3)
    finally:
        await close()

    assert len(updates) == 3  # one catch-up on connect, then one per order change
    assert fake.received[0] == {"action": "auth", "key": "key-id", "secret": "secret-value"}
    assert fake.received[1] == {"action": "listen", "data": {"streams": ["trade_updates"]}}


async def test_a_dropped_connection_reconnects_and_catches_up():
    fake = _FakeAlpaca(updates=0, drop=True)
    connect, close = await _serve(fake)
    stop = asyncio.Event()
    try:
        watch = alpaca_order_stream(CREDENTIALS, "paper", connect=connect, retry_seconds=(0.01,))
        updates = await _watch_until(watch, stop, lambda seen: len(seen) >= 2)
    finally:
        await close()

    assert fake.connections == 2
    assert len(updates) == 2


async def test_refused_keys_never_wake_the_account_and_retry_with_backoff():
    fake = _FakeAlpaca(authorize=False)
    connect, close = await _serve(fake)
    stop = asyncio.Event()
    updates: list[None] = []
    try:
        watch = alpaca_order_stream(
            CREDENTIALS, "paper", connect=connect, retry_seconds=(0.01, 0.01, 10.0)
        )
        live: list[bool] = []
        task = asyncio.create_task(watch(lambda: updates.append(None), live.append, stop))
        await asyncio.sleep(0.3)
        stop.set()
        await asyncio.wait_for(task, timeout=2)
    finally:
        await close()

    assert updates == []
    assert True not in live, "a refused stream is never live"
    assert fake.connections == 3, "two quick retries, then the long backoff"


async def test_the_stream_is_live_once_alpaca_listens_and_down_when_it_drops():
    fake = _FakeAlpaca(updates=0, drop=True)
    connect, close = await _serve(fake)
    stop = asyncio.Event()
    live: list[bool] = []

    def on_live(value: bool) -> None:
        live.append(value)
        if live.count(True) == 2:
            stop.set()

    try:
        watch = alpaca_order_stream(CREDENTIALS, "paper", connect=connect, retry_seconds=(0.01,))
        await asyncio.wait_for(watch(lambda: None, on_live, stop), timeout=5)
    finally:
        await close()

    # Live on the first connection, down when it dropped, live again after reconnecting, and
    # down once stopped.
    assert live == [True, False, True, False]
