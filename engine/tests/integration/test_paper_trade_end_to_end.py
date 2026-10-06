"""Opt-in end-to-end paper trade: a replayed signal travels the real pipeline to Alpaca paper.

Only the Discord connection is replaced: a replay session captures a signal written by the test.
Interpretation uses the real DeepSeek API, routing and risk checks are the engine's own, and the
order goes to a real Alpaca paper account. Runs only when COPYTRADING_TEST_ALPACA_KEY,
COPYTRADING_TEST_ALPACA_SECRET, and COPYTRADING_TEST_DEEPSEEK_KEY are set, cancels every
order it placed, and sells back whatever filled, so the paper account ends as it started.
"""

import asyncio
import datetime as dt
import os
import time
import uuid
from decimal import ROUND_UP, Decimal

import httpx
import pytest

from copytrading_engine.execution.domain.lifecycle import AccountControlCommand
from copytrading_engine.shared.raw_message import RawMessage
from copytrading_engine.trading.domain.config import TradingConfiguration, TradingSecrets
from copytrading_engine.trading.domain.profiles import ProfileBuilder, ProfileDraft
from copytrading_engine.trading.entrypoints.factories import TradingFactories
from copytrading_engine.trading.entrypoints.runtime import TradingRuntime

_ALPACA_KEY = os.environ.get("COPYTRADING_TEST_ALPACA_KEY", "")
_ALPACA_SECRET = os.environ.get("COPYTRADING_TEST_ALPACA_SECRET", "")
_DEEPSEEK_KEY = os.environ.get("COPYTRADING_TEST_DEEPSEEK_KEY", "")
_DEEPSEEK_MODEL = os.environ.get("COPYTRADING_TEST_DEEPSEEK_MODEL", "deepseek-flash")
_SYMBOL = os.environ.get("COPYTRADING_TEST_SYMBOL", "F")
_CHANNEL = "900000000000000001"

pytestmark = pytest.mark.skipif(
    not (_ALPACA_KEY and _ALPACA_SECRET and _DEEPSEEK_KEY),
    reason=(
        "set COPYTRADING_TEST_ALPACA_KEY, COPYTRADING_TEST_ALPACA_SECRET, "
        "and COPYTRADING_TEST_DEEPSEEK_KEY"
    ),
)

_ALPACA_HEADERS = {"APCA-API-KEY-ID": _ALPACA_KEY, "APCA-API-SECRET-KEY": _ALPACA_SECRET}


class _ReplaySession:
    """Stands in for the Discord session: captures each message once its gate opens."""

    def __init__(self, source, messages: tuple[tuple[asyncio.Event, RawMessage], ...]) -> None:
        self.source = source
        self.messages = messages
        self.ready = True
        self.capture_task: asyncio.Task[None] | None = None

    def start(self, token: str) -> None:
        async def capture() -> None:
            for gate, message in self.messages:
                await gate.wait()  # the guru posts only after entries are enabled
                await self.source.add(message)

        self.capture_task = asyncio.create_task(capture())

    async def ensure_running(self) -> None:
        # The engine's loop must keep running while the guru waits for a gate.
        if self.capture_task is not None and self.capture_task.done():
            await self.capture_task

    async def forward_if_ready(self, forwarder) -> None:
        await forwarder.flush()

    async def close(self) -> None:
        if self.capture_task is not None:
            self.capture_task.cancel()
            await asyncio.gather(self.capture_task, return_exceptions=True)


async def _latest_ask(symbol: str) -> Decimal:
    async with httpx.AsyncClient(headers=_ALPACA_HEADERS, timeout=10) as client:
        response = await client.get(
            f"https://data.alpaca.markets/v2/stocks/{symbol}/quotes/latest",
            params={"feed": "iex"},
        )
        response.raise_for_status()
        quote = response.json()["quote"]
    price = Decimal(str(quote.get("ap") or quote.get("bp")))
    assert price > 0, f"no usable quote for {symbol}"
    return price.quantize(Decimal("0.01"), rounding=ROUND_UP)


async def _unwind_orders(client_ids: set[str]) -> None:
    """Cancel what is still open, then sell back what the test still holds."""
    held: dict[str, Decimal] = {}
    async with httpx.AsyncClient(headers=_ALPACA_HEADERS, timeout=10) as client:
        for client_id in client_ids:
            found = await client.get(
                "https://paper-api.alpaca.markets/v2/orders:by_client_order_id",
                params={"client_order_id": client_id},
            )
            if found.status_code != 200:
                continue
            order = found.json()
            if order.get("status") in {"new", "accepted", "partially_filled", "pending_new"}:
                await client.delete(f"https://paper-api.alpaca.markets/v2/orders/{order['id']}")
                await asyncio.sleep(2)
                order = (
                    await client.get(f"https://paper-api.alpaca.markets/v2/orders/{order['id']}")
                ).json()
            filled = Decimal(str(order.get("filled_qty") or "0"))
            sign = 1 if order.get("side") == "buy" else -1
            held[order["symbol"]] = held.get(order["symbol"], Decimal(0)) + sign * filled
            if sign > 0 and filled > 0:
                held[f"{order['symbol']}@paid"] = Decimal(
                    str(order.get("filled_avg_price") or order["limit_price"])
                )
        for symbol, quantity in held.items():
            if "@" in symbol or quantity <= 0:
                continue
            # Extended and overnight sessions accept only limit orders; 2% under the fill clears.
            paid = held[f"{symbol}@paid"]
            sold = await client.post(
                "https://paper-api.alpaca.markets/v2/orders",
                json={
                    "symbol": symbol,
                    "qty": str(quantity),
                    "side": "sell",
                    "type": "limit",
                    "limit_price": str((paid * Decimal("0.98")).quantize(Decimal("0.01"))),
                    "time_in_force": "day",
                    "extended_hours": True,
                },
            )
            assert sold.status_code == 200, f"could not sell back the test fill: {sold.status_code}"
            # Leave nothing open, so the next test's account opens on a quiet broker.
            for _ in range(30):
                status = (
                    await client.get(
                        f"https://paper-api.alpaca.markets/v2/orders/{sold.json()['id']}"
                    )
                ).json()["status"]
                if status not in {"new", "accepted", "partially_filled", "pending_new"}:
                    break
                await asyncio.sleep(1)


def _configuration(*, approve_orders: bool = False) -> TradingConfiguration:
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
            "source": {"channel_ids": [_CHANNEL]},
            "provider": {"name": "deepseek", "model": _DEEPSEEK_MODEL},
            "accounts": [
                {
                    "id": "paper-e2e",
                    "environment": "paper",
                    # Its maximum per stock, $40, is the guru's full position (ADR-0007).
                    "policy": {
                        "max_order_usd": "50",
                        "max_symbol_usd": "40",
                        "max_above_signal_pct": "1",
                        "approve_orders": approve_orders,
                    },
                }
            ],
            "profiles": [profile.model_dump(mode="json")],
            "routes": [
                {
                    "channel_id": _CHANNEL,
                    "author_id": None,
                    "guru_id": profile.guru_id,
                    "profile_revision": profile.profile_revision,
                    "connections": [{"account_id": "paper-e2e", "full_position_usd": "40"}],
                }
            ],
        }
    )


def _post(text: str) -> RawMessage:
    return RawMessage(
        schema_version=1,
        event_type="raw_message",
        source="discord",
        channel_id=_CHANNEL,
        id=str(time.time_ns()),
        timestamp=dt.datetime.now(dt.UTC),
        text=text,
    )


class _Run:
    """One replayed conversation: the guru's posts go in, the orders sent to Alpaca come out."""

    def __init__(
        self, tmp_path, posts: tuple[RawMessage, ...], *, approve_orders: bool = False
    ) -> None:
        self.approve_orders = approve_orders
        self.gates = tuple(asyncio.Event() for _ in posts)
        self.posts = posts
        self.placed: set[str] = set()
        secrets = TradingSecrets.model_validate(
            {
                "discord_token": "replay-session-needs-no-token",
                "provider_api_key": _DEEPSEEK_KEY,
                "brokers": [
                    {"account_id": "paper-e2e", "key": _ALPACA_KEY, "secret": _ALPACA_SECRET}
                ],
            }
        )
        defaults = TradingFactories()
        factories = TradingFactories(
            owner=defaults.owner,
            decoder=defaults.decoder,
            session=lambda source, channels, authors, stop, report: _ReplaySession(
                source, tuple(zip(self.gates, posts, strict=True))
            ),
            notifier=defaults.notifier,
        )
        self.runtime = TradingRuntime(tmp_path, factories=factories)
        self.secrets = secrets

    async def __aenter__(self) -> _Run:
        await self.runtime.start(_configuration(approve_orders=self.approve_orders), self.secrets)
        for _ in range(60):
            if self.runtime.status().accounts:
                break
            await asyncio.sleep(1)
        # New accounts start with entries disabled; enable them as the Accounts screen does.
        await self.runtime.manual.control_account(
            AccountControlCommand(
                command_id=str(uuid.uuid4()), account_id="paper-e2e", action="resume"
            )
        )
        return self

    async def __aexit__(self, *exc) -> None:
        await self.runtime.pause()
        await self.runtime.shutdown()
        await _unwind_orders(self.placed)

    async def post(self, index: int, *, wait_for, seconds: int = 90):
        """Let the guru post number `index`, then wait until `wait_for(activity, orders)` holds."""
        self.gates[index].set()
        activity, orders = None, []
        for _ in range(seconds):
            page = await self.runtime.operator.source_activity(None, 25)
            activity = next(
                (item for item in page.items if item.text == self.posts[index].text), None
            )
            orders = [
                order
                for destination in (activity.destinations if activity else ())
                for order in destination.orders
            ]
            self.placed |= {order.client_id for order in orders}
            if wait_for(activity, orders):
                break
            await asyncio.sleep(1)
        return activity, orders


async def test_replayed_signal_places_a_paper_order(tmp_path):
    price = await _latest_ask(_SYMBOL)
    signal = _post(f"ALERT: Bought {_SYMBOL} at {price}")
    async with _Run(tmp_path, (signal,)) as run:
        activity, _ = await run.post(
            0, wait_for=lambda _, orders: any(order.broker_id for order in orders)
        )
        assert activity is not None, (
            f"the replayed signal was never captured: {run.runtime.status()}"
        )
        assert activity.decision == "trade", (activity.decision, activity.parser_reason)
        assert activity.destinations, f"no destination received the signal: {activity}"
        destination = activity.destinations[0]
        order = next((order for order in destination.orders if order.broker_id), None)
        assert order is not None, (
            f"no order reached Alpaca: status={destination.status} "
            f"outcomes={destination.instruction_outcomes} orders={destination.orders} "
            f"runtime={run.runtime.status()}"
        )
        assert order.symbol == _SYMBOL
        assert order.side == "buy"
        assert order.quantity > 0


async def test_replayed_sell_reaches_alpaca_as_a_limit_order_under_the_guru_price(tmp_path):
    price = await _latest_ask(_SYMBOL)
    buy = _post(f"ALERT: Bought {_SYMBOL} at {price}")
    sell = _post(f"ALERT: Sold all {_SYMBOL} at {price}")
    async with _Run(tmp_path, (buy, sell)) as run:
        _, bought = await run.post(
            0, wait_for=lambda _, orders: any(order.filled_quantity > 0 for order in orders)
        )
        if not any(order.filled_quantity > 0 for order in bought):
            pytest.skip("the paper buy did not fill in time, so there is nothing to sell")
        activity, orders = await run.post(
            1, wait_for=lambda _, orders: any(order.broker_id for order in orders)
        )
        assert activity is not None, "the sell post was never captured"
        assert activity.decision == "trade", activity
        order = next((order for order in orders if order.broker_id), None)
        assert order is not None, f"no sell reached Alpaca: {activity.destinations}"
        assert order.side == "sell"
        # Every sell is a limit order: the guru's price less the 1% allowance, rounded up a cent.
        assert order.limit_price == (price * Decimal("0.99")).quantize(
            Decimal("0.01"), rounding=ROUND_UP
        )


async def test_an_account_that_approves_orders_holds_the_buy_and_sends_nothing(tmp_path):
    price = await _latest_ask(_SYMBOL)
    buy = _post(f"ALERT: Bought {_SYMBOL} at {price}")
    async with _Run(tmp_path, (buy,), approve_orders=True) as run:
        activity, orders = await run.post(
            0,
            wait_for=lambda activity, _: bool(
                activity and activity.destinations and activity.destinations[0].instruction_outcomes
            ),
            seconds=45,
        )
        assert activity is not None, "the post was never captured"
        assert activity.decision == "trade", activity.decision
        [destination] = activity.destinations
        assert destination.instruction_outcomes == ("approval_required",), destination
        assert orders == [], "a held call must never reach the broker"
        # Give the engine a few more cycles to prove nothing slips out later.
        await asyncio.sleep(8)
        async with httpx.AsyncClient(headers=_ALPACA_HEADERS, timeout=10) as client:
            open_orders = (
                await client.get(
                    "https://paper-api.alpaca.markets/v2/orders",
                    params={"status": "open", "symbols": _SYMBOL},
                )
            ).json()
        assert open_orders == [], (
            f"an order reached Alpaca although it needed approval: {open_orders}"
        )
