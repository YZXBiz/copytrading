"""Opt-in: a coin copies on Alpaca paper as the fakes say it does (ADR-0014).

Runs only when COPYTRADING_TEST_ALPACA_KEY and COPYTRADING_TEST_ALPACA_SECRET are set. Each test
drives the real engine against the paper account, with no app, at any hour, and sells back every
coin it bought; it never touches a stock the account holds. About three minutes in all:

    uv run --directory engine pytest tests/execution/test_paper_crypto_live.py -p no:randomly
"""

import datetime as dt
import os
import time
import uuid
from collections.abc import Callable, Iterator
from dataclasses import dataclass, field
from decimal import Decimal

import pytest
from pydantic import SecretStr

from copytrading_engine.execution.adapters.alpaca.broker import AlpacaBroker, AlpacaCredentials
from copytrading_engine.execution.application.engine import CopyEngine
from copytrading_engine.execution.domain.events import CancelRequested
from copytrading_engine.execution.domain.orders import OrderRecord
from copytrading_engine.execution.domain.progress import Skipped
from copytrading_engine.execution.domain.signals import CopyConfig
from copytrading_engine.shared.signals import StockSignal

from .builders import event, receive
from .fakes import MemoryRepository

_KEY = os.environ.get("COPYTRADING_TEST_ALPACA_KEY", "")
_SECRET = os.environ.get("COPYTRADING_TEST_ALPACA_SECRET", "")

pytestmark = pytest.mark.skipif(
    not (_KEY and _SECRET),
    reason="set COPYTRADING_TEST_ALPACA_KEY and COPYTRADING_TEST_ALPACA_SECRET",
)

COINS = ("BTC/USD", "ETH/USD", "SOL/USD", "LTC/USD")
DUST = Decimal("0.000000010")
WAITING = {"new", "accepted", "partially_filled", "pending_new"}


def now() -> dt.datetime:
    return dt.datetime.now(dt.UTC)


@dataclass
class Paper:
    engine: CopyEngine
    broker: AlpacaBroker
    store: MemoryRepository
    run: str = field(default_factory=lambda: uuid.uuid4().hex[:8])

    def post(
        self,
        post: str,
        action: str,
        pair: str,
        guru: Decimal,
        bought_at: Decimal | None = None,
        full: str = "600",
    ):
        """Receive a guru's post for `pair` and act on it, as an account's cycle does."""
        price, entry = f"{guru:.2f}", bought_at and f"{bought_at:.2f}"
        message = event(f"{self.run}-{post}", action, price, entry, timestamp=now())
        [instruction] = message["instructions"]
        instruction["symbol"] = pair
        message["evidence"] = [
            instruction
            | {
                "action_evidence": "synthetic",
                "symbol_evidence": pair,
                "price_evidence": price,
                "entry_evidence": entry,
                "fraction_evidence": None,
            }
        ]
        receive(self.engine, StockSignal.model_validate(message), now(), full_position_usd=full)
        self.engine.process(now())

    def until(self, done: Callable[[], bool], seconds: float) -> None:
        """Sync with Alpaca every two seconds until `done`, or fail after `seconds`."""
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            self.engine.reconcile(now())
            self.engine.process(now())
            if done():
                return
            time.sleep(2)
        pytest.fail(f"not done after {seconds} s")

    def wait(self, seconds: float) -> None:
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            self.engine.reconcile(now())
            self.engine.process(now())
            time.sleep(2)

    def order(self, pair: str, side: str) -> OrderRecord:
        return [o for o in self.engine.ledger.orders() if o.symbol == pair and o.side == side][-1]

    def lot(self, pair: str) -> Decimal:
        held = (lot.remaining_qty for lot in self.engine.ledger.lots() if lot.symbol == pair)
        return sum(held, Decimal(0))

    def held(self, pair: str) -> Decimal:
        """Alpaca's coin, listed without the pair's slash."""
        spellings = {pair, pair.replace("/", "")}
        return sum((p.qty for p in self.broker.positions() if p.symbol in spellings), Decimal(0))

    def alpaca(self, order: OrderRecord) -> dict:
        return self.broker.http.get(
            "/v2/orders:by_client_order_id", params={"client_order_id": order.client_id}
        ).json()

    def cancel_reason(self, order: OrderRecord) -> str | None:
        reasons = [
            saved.payload.reason
            for saved in self.store.events
            if isinstance(saved.payload, CancelRequested)
            and saved.payload.client_id == order.client_id
        ]
        return reasons[-1] if reasons else None

    def parts(self, post: str) -> tuple:
        return self.engine.ledger.message(f"discord:demo:{self.run}-{post}").parts

    def quote(self, pair: str) -> tuple[Decimal, Decimal]:
        quote = self.broker.quote(pair)
        assert quote.bid, f"{pair} has no bid"
        assert quote.ask, f"{pair} has no ask"
        return quote.bid, quote.ask

    def sell_back(self) -> None:
        """Cancel this account's coin orders and sell every coin it holds; stocks stay."""
        for placed in self.broker.http.get("/v2/orders", params={"status": "open"}).json():
            if "/" in placed["symbol"]:
                self.broker.http.delete(f"/v2/orders/{placed['id']}")
        time.sleep(2)
        for pair in COINS:
            if self.held(pair) > 0:
                self.broker.http.delete(f"/v2/positions/{pair.replace('/', '')}")


@pytest.fixture
def paper() -> Iterator[Paper]:
    broker = AlpacaBroker(AlpacaCredentials(SecretStr(_KEY), SecretStr(_SECRET)), "paper")
    store = MemoryRepository()
    engine = CopyEngine(
        store,
        broker,
        CopyConfig(
            sources=["discord:demo"],
            order_timeout_seconds=15,
            max_symbol_usd=Decimal(1000),
            max_total_usd=Decimal(100000),
            pricing={"max_above_signal_pct": "1", "max_below_signal_pct": "1"},
        ),
    )
    engine.bind(now(), environment="paper")
    account = Paper(engine, broker, store)
    account.sell_back()
    assert all(account.held(pair) == 0 for pair in COINS), "the paper account already holds coins"
    try:
        yield account
    finally:
        account.sell_back()
        broker.close()


def test_a_coin_buy_fills_good_till_canceled_and_the_lot_is_what_alpaca_delivered(paper):
    _, ask = paper.quote("BTC/USD")

    paper.post("buy", "buy", "BTC/USD", ask)
    paper.until(lambda: paper.order("BTC/USD", "buy").fee_qty is not None, 60)

    buy = paper.order("BTC/USD", "buy")
    sent = paper.alpaca(buy)
    assert (sent["time_in_force"], sent["extended_hours"]) == ("gtc", False)
    # A sixth of a $600 position is $100.
    assert Decimal(95) <= buy.qty * buy.limit_price <= Decimal(100)
    assert Decimal(0) < buy.fee_qty <= buy.filled_qty * Decimal("0.01")
    assert buy.received_qty == buy.filled_qty - buy.fee_qty
    assert paper.lot("BTC/USD") == paper.held("BTC/USD") == buy.received_qty


def test_a_half_then_a_full_sale_follow_the_lot_and_sell_at_the_floor(paper):
    _, entry = paper.quote("BTC/USD")
    paper.post("buy", "buy", "BTC/USD", entry)
    paper.until(lambda: paper.order("BTC/USD", "buy").fee_qty is not None, 60)
    bought = paper.lot("BTC/USD")

    guru, _ = paper.quote("BTC/USD")
    paper.post("half", "reduce", "BTC/USD", guru, entry)
    paper.until(lambda: paper.order("BTC/USD", "sell").status.value == "filled", 60)

    half = paper.order("BTC/USD", "sell")
    assert abs(half.qty - bought / 2) <= Decimal("0.000000002")
    assert half.limit_price <= guru.quantize(Decimal("0.01")) * Decimal("0.99")
    assert paper.lot("BTC/USD") == paper.held("BTC/USD") == bought - half.qty

    guru, _ = paper.quote("BTC/USD")
    paper.post("rest", "close", "BTC/USD", guru, entry)
    paper.until(lambda: paper.lot("BTC/USD") == 0, 60)

    assert paper.held("BTC/USD") < DUST


def test_a_sale_resting_at_its_floor_outlives_the_timeout(paper):
    _, entry = paper.quote("ETH/USD")
    paper.post("buy", "buy", "ETH/USD", entry)
    paper.until(lambda: paper.order("ETH/USD", "buy").fee_qty is not None, 60)
    bid, _ = paper.quote("ETH/USD")

    # The guru sold 5% above the market: the floor rests above it.
    paper.post("sell", "close", "ETH/USD", bid * Decimal("1.05"), entry)
    paper.wait(45)

    sale = paper.order("ETH/USD", "sell")
    assert paper.alpaca(sale)["status"] in WAITING
    assert paper.cancel_reason(sale) is None


def test_a_buy_resting_below_the_market_is_cancelled_for_time(paper):
    bid, _ = paper.quote("SOL/USD")

    paper.post("buy", "buy", "SOL/USD", bid * Decimal("0.95"))
    paper.until(lambda: paper.alpaca(paper.order("SOL/USD", "buy"))["status"] == "canceled", 60)

    assert paper.cancel_reason(paper.order("SOL/USD", "buy")) == "timeout"
    assert paper.lot("SOL/USD") == paper.held("SOL/USD") == 0


def test_a_coin_buy_under_ten_dollars_is_skipped(paper):
    _, ask = paper.quote("SOL/USD")

    # A sixth of a $30 position is $5.
    paper.post("small", "buy", "SOL/USD", ask, full="30")

    assert paper.parts("small") == (Skipped(reason="below_minimum_budget"),)
    assert not paper.engine.ledger.orders()


def test_a_coin_never_bought_is_never_sold(paper):
    bid, ask = paper.quote("LTC/USD")

    paper.post("sell", "close", "LTC/USD", bid, ask)

    assert paper.parts("sell") == (Skipped(reason="lot_unavailable"),)
    assert not paper.engine.ledger.orders()
