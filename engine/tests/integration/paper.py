"""A live paper rig: replayed guru posts travel the real pipeline to a real Alpaca paper account.

Only the Discord connection is replaced. Interpretation uses the real DeepSeek API, routing, risk,
the ledger, and lots are the engine's own, and orders go to Alpaca paper. A rig cancels every
order it placed and sells back what filled, so the account ends as it started.
"""

import asyncio
import datetime as dt
import os
import time
import uuid
from collections.abc import Callable, Mapping
from dataclasses import dataclass
from decimal import ROUND_UP, Decimal
from pathlib import Path

import httpx

from copytrading_engine.execution.adapters.alpaca.broker import quote_feed
from copytrading_engine.execution.application.ports import BrokerError
from copytrading_engine.execution.domain.lifecycle import AccountControlCommand
from copytrading_engine.execution.presentation.operator_views import (
    AccountOverview,
    DestinationView,
    OrderView,
)
from copytrading_engine.shared.raw_message import RawMessage
from copytrading_engine.trading.domain.config import TradingConfiguration, TradingSecrets
from copytrading_engine.trading.domain.profiles import ProfileBuilder, ProfileDraft
from copytrading_engine.trading.entrypoints.factories import TradingFactories
from copytrading_engine.trading.entrypoints.runtime import TradingRuntime

ALPACA_KEY = os.environ.get("COPYTRADING_TEST_ALPACA_KEY", "")
ALPACA_SECRET = os.environ.get("COPYTRADING_TEST_ALPACA_SECRET", "")
DEEPSEEK_KEY = os.environ.get("COPYTRADING_TEST_DEEPSEEK_KEY", "")
DEEPSEEK_MODEL = os.environ.get("COPYTRADING_TEST_DEEPSEEK_MODEL", "deepseek-flash")
LIVE = bool(ALPACA_KEY and ALPACA_SECRET and DEEPSEEK_KEY)
LIVE_REASON = (
    "set COPYTRADING_TEST_ALPACA_KEY, COPYTRADING_TEST_ALPACA_SECRET, "
    "and COPYTRADING_TEST_DEEPSEEK_KEY"
)

ACCOUNT = "paper-e2e"
CHANNEL = "900000000000000001"
PAPER = "https://paper-api.alpaca.markets/v2"
DATA = "https://data.alpaca.markets/v2"
HEADERS = {"APCA-API-KEY-ID": ALPACA_KEY, "APCA-API-SECRET-KEY": ALPACA_SECRET}
OPEN = {"new", "accepted", "partially_filled", "pending_new", "held"}
SETTLED = {"stale", "out_of_order", "ignored", "review_required"}
CENT = Decimal("0.01")

# Roomy limits, so a scenario meets only the limit it is about. Overnight is on, so a rig
# trades in every session the broker offers.
ROOMY: dict[str, object] = {
    "max_order_usd": "50",
    "max_symbol_usd": "40",
    "max_total_usd": "100000",
    "daily_loss_cap_usd": "100000",
    "max_above_signal_pct": "1",
    "extended_hours": True,
    "overnight": True,
}


@dataclass(frozen=True, slots=True)
class Post:
    """A guru's post; `age` backdates it, as a post the engine reads late."""

    text: str
    age: dt.timedelta = dt.timedelta(0)
    message_id: str | None = None
    # A fixed time, for a post delivered twice exactly as Discord sent it.
    at: dt.datetime | None = None

    def message(self) -> RawMessage:
        return RawMessage(
            schema_version=1,
            event_type="raw_message",
            source="discord",
            channel_id=CHANNEL,
            id=self.message_id or str(time.time_ns()),
            timestamp=self.at or dt.datetime.now(dt.UTC) - self.age,
            text=self.text,
        )


class _ReplaySession:
    """Stands in for the Discord session: captures each post once its gate opens."""

    def __init__(self, source, posts: tuple[tuple[asyncio.Event, Post], ...]) -> None:
        self.source = source
        self.posts = posts
        self.ready = True
        self.capture_task: asyncio.Task[None] | None = None

    def start(self, token: str) -> None:
        async def capture() -> None:
            for gate, post in self.posts:
                await gate.wait()
                # Stamped as it is released, so a post that waited on a fill is not read as late.
                await self.source.add(post.message())

        self.capture_task = asyncio.create_task(capture())

    async def ensure_running(self) -> None:
        if self.capture_task is not None and self.capture_task.done():
            await self.capture_task

    async def forward_if_ready(self, forwarder) -> None:
        await forwarder.flush()

    async def close(self) -> None:
        if self.capture_task is not None:
            self.capture_task.cancel()
            await asyncio.gather(self.capture_task, return_exceptions=True)


def configuration(policy: Mapping[str, object]) -> TradingConfiguration:
    """One account copying one guru; the guru's full position is its maximum per stock."""
    profile = ProfileBuilder().build(
        ProfileDraft(
            guru_id="replay-guru",
            display_name="Replay Guru",
            playbook="",
            examples=(),
            exit_basis="original_position",
            sells_refer_to="whole_position",
        )
    )
    return TradingConfiguration.model_validate(
        {
            "version": 7,
            "source": {"channel_ids": [CHANNEL]},
            "provider": {"name": "deepseek", "model": DEEPSEEK_MODEL},
            "accounts": [{"id": ACCOUNT, "environment": "paper", "policy": dict(policy)}],
            "profiles": [profile.model_dump(mode="json")],
            "routes": [
                {
                    "channel_id": CHANNEL,
                    "author_id": None,
                    "guru_id": profile.guru_id,
                    "profile_revision": profile.profile_revision,
                    "connections": [
                        {"account_id": ACCOUNT, "full_position_usd": policy["max_symbol_usd"]}
                    ],
                }
            ],
        }
    )


def orders_of(activity) -> list[OrderView]:
    return [
        order
        for destination in (activity.destinations if activity else ())
        for order in destination.orders
    ]


def destination_of(activity) -> DestinationView:
    assert activity is not None, "the post was never captured"
    [destination] = activity.destinations
    return destination


def decided(activity, _orders=None) -> bool:
    """The engine has finished with the post: an outcome, a placed order, or nothing to route."""
    if activity is None or activity.decision is None:
        return False
    if activity.decision != "trade":
        return True
    return any(
        destination.instruction_outcomes
        or destination.status in SETTLED
        or any(order.broker_id for order in destination.orders)
        for destination in activity.destinations
    )


def placed(_activity, orders) -> bool:
    return any(order.broker_id for order in orders)


def filled(_activity, orders) -> bool:
    return any(order.filled_quantity > 0 and order.status == "filled" for order in orders)


def settled(_activity, orders) -> bool:
    return bool(orders) and all(order.broker_id and order.status not in OPEN for order in orders)


class Rig:
    """One replayed conversation against one paper account."""

    def __init__(
        self,
        state: Path,
        posts: tuple[Post, ...],
        *,
        policy: Mapping[str, object] | None = None,
        resume: bool = True,
    ) -> None:
        self.state = state
        self.posts = posts
        self.policy = {**ROOMY, **(policy or {})}
        self.resume = resume
        self.gates = tuple(asyncio.Event() for _ in posts)
        self.placed: set[str] = set()
        self.secrets = TradingSecrets.model_validate(
            {
                "discord_token": "replay-session-needs-no-token",
                "provider_api_key": DEEPSEEK_KEY,
                "brokers": [{"account_id": ACCOUNT, "key": ALPACA_KEY, "secret": ALPACA_SECRET}],
            }
        )
        defaults = TradingFactories()
        self.runtime = TradingRuntime(
            state,
            factories=TradingFactories(
                owner=defaults.owner,
                decoder=defaults.decoder,
                session=lambda source, channels, authors, stop, report: _ReplaySession(
                    source, tuple(zip(self.gates, posts, strict=True))
                ),
                notifier=defaults.notifier,
            ),
        )

    async def __aenter__(self) -> Rig:
        await self.runtime.start(configuration(self.policy), self.secrets)
        try:
            for _ in range(60):
                if self.runtime.status().accounts:
                    break
                await asyncio.sleep(1)
            if self.resume:
                await self.control("resume")
        except BaseException:
            # A rig that never opened still shuts its runtime down, or the account stays locked.
            await self.runtime.shutdown()
            raise
        return self

    async def __aexit__(self, *exc) -> None:
        try:
            await self.runtime.pause()
        finally:
            try:
                await self.runtime.shutdown()
            finally:
                await unwind(self.placed)

    async def control(self, action: str) -> None:
        """As the owner pressing the button, who presses it again when Alpaca is briefly busy."""
        for attempt in range(5):
            try:
                await self.runtime.manual.control_account(
                    AccountControlCommand(
                        command_id=str(uuid.uuid4()), account_id=ACCOUNT, action=action
                    )
                )
                return
            except BrokerError as exc:
                if not exc.transient or attempt == 4:
                    raise
                await asyncio.sleep(3)

    async def activity(self, index: int):
        page = await self.runtime.operator.source_activity(None, 50)
        return next((item for item in page.items if item.text == self.posts[index].text), None)

    async def post(
        self, index: int, *, until: Callable[..., bool] = decided, seconds: int = 180
    ) -> tuple[object, list[OrderView]]:
        """Release post number `index`, then wait until `until(activity, orders)` holds."""
        self.gates[index].set()
        return await self.wait(index, until=until, seconds=seconds)

    async def wait(
        self, index: int, *, until: Callable[..., bool], seconds: int = 180
    ) -> tuple[object, list[OrderView]]:
        activity, orders = None, []
        for _ in range(seconds):
            activity = await self.activity(index)
            orders = orders_of(activity)
            self.placed |= {order.client_id for order in orders}
            if until(activity, orders):
                break
            await asyncio.sleep(1)
        return activity, orders

    async def account(self) -> AccountOverview:
        page = await self.runtime.operator.account_overviews(None, 10)
        [account] = [item for item in page.items if item.account_id == ACCOUNT]
        return account

    async def owned(self, symbol: str) -> Decimal:
        account = await self.account()
        return sum(
            (position.owned_qty for position in account.positions if position.symbol == symbol),
            Decimal(0),
        )


async def quote(symbol: str) -> tuple[Decimal, Decimal]:
    """The live bid and ask from the feed the engine reads at this hour."""
    async with httpx.AsyncClient(headers=HEADERS, timeout=10) as client:
        response = await client.get(
            f"{DATA}/stocks/{symbol}/quotes/latest",
            params={"feed": quote_feed(dt.datetime.now(dt.UTC))},
        )
        response.raise_for_status()
        latest = response.json()["quote"]
    bid, ask = Decimal(str(latest.get("bp") or 0)), Decimal(str(latest.get("ap") or 0))
    assert bid > 0, f"no usable bid for {symbol}"
    assert ask > 0, f"no usable ask for {symbol}"
    return bid, ask


async def guru_price(symbol: str) -> Decimal:
    """A price the guru could have paid: the ask, so a 1% allowance fills."""
    _, ask = await quote(symbol)
    return ask.quantize(CENT, rounding=ROUND_UP)


async def broker(method: str, path: str, **kwargs) -> httpx.Response:
    """One paper API call, waiting out Alpaca's rate limit as the engine does."""
    async with httpx.AsyncClient(headers=HEADERS, timeout=10) as client:
        for _ in range(10):
            response = await client.request(method, f"{PAPER}{path}", **kwargs)
            if response.status_code != 429:
                return response
            await asyncio.sleep(3)
        return response


async def positions() -> dict[str, Decimal]:
    response = await broker("GET", "/positions")
    response.raise_for_status()
    return {item["symbol"]: Decimal(item["qty"]) for item in response.json()}


async def flatten(symbols: tuple[str, ...]) -> None:
    """Cancel every open order, then sell what the account holds of `symbols`: each scenario
    starts from the same account."""
    for order in (await broker("GET", "/orders", params={"status": "open"})).json():
        await broker("DELETE", f"/orders/{order['id']}")
    for _ in range(20):
        if not (await broker("GET", "/orders", params={"status": "open"})).json():
            break
        await asyncio.sleep(1)
    held = await positions()
    for symbol in symbols:
        if held.get(symbol, Decimal(0)) <= 0:
            continue
        bid, _ = await quote(symbol)
        sold = await broker(
            "POST",
            "/orders",
            json={
                "symbol": symbol,
                "qty": str(held[symbol]),
                "side": "sell",
                "type": "limit",
                "limit_price": str((bid * Decimal("0.98")).quantize(CENT)),
                "time_in_force": "day",
                "extended_hours": True,
            },
        )
        assert sold.status_code == 200, f"could not flatten {symbol}: {sold.text}"
        for _ in range(30):
            if (await broker("GET", f"/orders/{sold.json()['id']}")).json()["status"] not in OPEN:
                break
            await asyncio.sleep(1)


async def open_orders(symbol: str | None = None) -> list[dict]:
    params = {"status": "open"} | ({"symbols": symbol} if symbol else {})
    return (await broker("GET", "/orders", params=params)).json()


async def total_exposure() -> Decimal:
    positions = (await broker("GET", "/positions")).json()
    return sum((Decimal(p["market_value"]) for p in positions), Decimal(0))


async def unwind(client_ids: set[str]) -> None:
    """Cancel what is still open, then sell back what the rig still holds."""
    held: dict[str, Decimal] = {}
    paid: dict[str, Decimal] = {}
    for client_id in client_ids:
        found = await broker(
            "GET", "/orders:by_client_order_id", params={"client_order_id": client_id}
        )
        if found.status_code != 200:
            continue
        order = found.json()
        if order.get("status") in OPEN:
            await broker("DELETE", f"/orders/{order['id']}")
            for _ in range(10):
                await asyncio.sleep(1)
                order = (await broker("GET", f"/orders/{order['id']}")).json()
                if order.get("status") not in OPEN | {"pending_cancel"}:
                    break
        quantity = Decimal(str(order.get("filled_qty") or "0"))
        sign = 1 if order.get("side") == "buy" else -1
        held[order["symbol"]] = held.get(order["symbol"], Decimal(0)) + sign * quantity
        if sign > 0 and quantity > 0:
            paid[order["symbol"]] = Decimal(
                str(order.get("filled_avg_price") or order["limit_price"])
            )
    holdings = await positions()
    for symbol, quantity in held.items():
        # Never more than the account holds: a sell the engine sent may have filled meanwhile.
        quantity = min(quantity, holdings.get(symbol, Decimal(0)))
        if quantity <= 0:
            continue
        # Extended and overnight sessions take only limit orders; 2% under the fill clears.
        sold = await broker(
            "POST",
            "/orders",
            json={
                "symbol": symbol,
                "qty": str(quantity),
                "side": "sell",
                "type": "limit",
                "limit_price": str((paid[symbol] * Decimal("0.98")).quantize(CENT)),
                "time_in_force": "day",
                "extended_hours": True,
            },
        )
        assert sold.status_code == 200, f"could not sell back {symbol}: {sold.text}"
        for _ in range(30):
            status = (await broker("GET", f"/orders/{sold.json()['id']}")).json()["status"]
            if status not in OPEN:
                break
            await asyncio.sleep(1)
