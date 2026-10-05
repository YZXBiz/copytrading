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
    """Stands in for the Discord session: captures the given messages instead of listening."""

    def __init__(self, source, messages: tuple[RawMessage, ...], gate: asyncio.Event) -> None:
        self.source = source
        self.messages = messages
        self.gate = gate
        self.ready = True
        self.capture_task: asyncio.Task[None] | None = None

    def start(self, token: str) -> None:
        async def capture() -> None:
            await self.gate.wait()  # the guru posts only after entries are enabled
            for message in self.messages:
                await self.source.add(message)

        self.capture_task = asyncio.create_task(capture())

    async def ensure_running(self) -> None:
        if self.capture_task is not None:
            await self.capture_task

    async def forward_if_ready(self, forwarder) -> None:
        await forwarder.flush()

    async def close(self) -> None:
        if self.capture_task is not None:
            await self.capture_task


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
    """Cancel what is still open, then sell back any filled buy quantity at a marketable limit."""
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
            if order.get("side") != "buy" or filled <= 0:
                continue
            # Extended and overnight sessions accept only limit orders; 2% under the fill clears.
            paid = Decimal(str(order.get("filled_avg_price") or order["limit_price"]))
            sold = await client.post(
                "https://paper-api.alpaca.markets/v2/orders",
                json={
                    "symbol": order["symbol"],
                    "qty": str(filled),
                    "side": "sell",
                    "type": "limit",
                    "limit_price": str((paid * Decimal("0.98")).quantize(Decimal("0.01"))),
                    "time_in_force": "day",
                    "extended_hours": True,
                },
            )
            assert sold.status_code == 200, f"could not sell back the test fill: {sold.status_code}"


def _configuration() -> TradingConfiguration:
    profile = ProfileBuilder().build(
        ProfileDraft(
            guru_id="replay-guru",
            display_name="Replay Guru",
            prefix="ALERT:",
            playbook="",
            examples=(),
            exit_basis="original_position",
        )
    )
    return TradingConfiguration.model_validate(
        {
            "version": 5,
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


async def test_replayed_signal_places_a_paper_order(tmp_path):
    price = await _latest_ask(_SYMBOL)
    signal = RawMessage(
        schema_version=1,
        event_type="raw_message",
        source="discord",
        channel_id=_CHANNEL,
        id=str(int(dt.datetime.now(dt.UTC).timestamp() * 1000)),
        timestamp=dt.datetime.now(dt.UTC),
        text=f"ALERT: Bought {_SYMBOL} at {price}",
    )
    secrets = TradingSecrets.model_validate(
        {
            "discord_token": "replay-session-needs-no-token",
            "provider_api_key": _DEEPSEEK_KEY,
            "brokers": [{"account_id": "paper-e2e", "key": _ALPACA_KEY, "secret": _ALPACA_SECRET}],
        }
    )
    posted = asyncio.Event()
    defaults = TradingFactories()
    factories = TradingFactories(
        owner=defaults.owner,
        decoder=defaults.decoder,
        session=lambda source, channels, authors, stop, report: _ReplaySession(
            source, (signal,), posted
        ),
        notifier=defaults.notifier,
    )
    runtime = TradingRuntime(tmp_path, factories=factories)
    placed: set[str] = set()
    try:
        await runtime.start(_configuration(), secrets)
        for _ in range(60):
            if runtime.status().accounts:
                break
            await asyncio.sleep(1)
        # New accounts start with entries disabled; enable them as the Accounts screen does.
        await runtime.manual.control_account(
            AccountControlCommand(
                command_id=str(uuid.uuid4()), account_id="paper-e2e", action="resume"
            )
        )
        posted.set()
        activity = None
        for _ in range(90):
            page = await runtime.operator.source_activity(None, 25)
            activity = next((item for item in page.items if item.text == signal.text), None)
            orders = [
                order
                for destination in (activity.destinations if activity else ())
                for order in destination.orders
            ]
            placed |= {order.client_id for order in orders}
            if any(order.broker_id for order in orders):
                break
            await asyncio.sleep(1)

        assert activity is not None, f"the replayed signal was never captured: {runtime.status()}"
        assert activity.decision == "trade", (activity.decision, activity.parser_reason)
        assert activity.destinations, f"no destination received the signal: {activity}"
        destination = activity.destinations[0]
        order = next((order for order in destination.orders if order.broker_id), None)
        assert order is not None, (
            f"no order reached Alpaca: status={destination.status} "
            f"outcomes={destination.instruction_outcomes} orders={destination.orders} "
            f"runtime={runtime.status()}"
        )
        assert order.symbol == _SYMBOL
        assert order.side == "buy"
        assert order.quantity > 0
    finally:
        await runtime.pause()
        await runtime.shutdown()
        await _unwind_orders(placed)
