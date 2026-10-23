"""A coin copies like a stock: the same buys, sells, lots, floors, and waits, on paper accounts
only. Only the broker's terms differ: good-till-canceled orders at any hour, the fee kept out of
the coin bought, and Alpaca's two spellings of a pair (ADR-0014)."""

import datetime as dt
from dataclasses import dataclass
from decimal import ROUND_DOWN, Decimal

import pytest

from copytrading_engine.execution.application.engine import CopyEngine
from copytrading_engine.execution.domain.events import CryptoFeeCounted, JournalEvent, Skipped
from copytrading_engine.execution.domain.order_lifecycle import OrderStatus
from copytrading_engine.execution.domain.orders import OwnedLot
from copytrading_engine.execution.domain.progress import Pending
from copytrading_engine.execution.domain.progress import Skipped as SkippedPart
from copytrading_engine.execution.domain.sessions import Session
from copytrading_engine.execution.domain.signals import CopyConfig
from copytrading_engine.execution.presentation.notifications import execution_notification
from copytrading_engine.shared.signals import StockSignal

from .builders import destination_signal, event
from .fakes import FakeBroker, MemoryRepository

# Saturday 24 October 2026, 22:00 in New York: no stock trades, a coin does.
SATURDAY_NIGHT = dt.datetime(2026, 10, 25, 2, tzinfo=dt.UTC)
PAIR = "BTC/USD"
COIN = Decimal("0.000000001")


@dataclass
class Account:
    engine: CopyEngine
    broker: FakeBroker
    store: MemoryRepository
    environment: str

    def copy(self, message: dict, *, sync: bool = True) -> None:
        """Receive the post and act on it, then sync with the broker, as an account's cycle does."""
        at = dt.datetime.fromisoformat(message["timestamp"])
        self.engine.receive(
            destination_signal(StockSignal.model_validate(message), environment=self.environment),
            at,
        )
        self.engine.process(at)
        if sync:
            self.engine.reconcile(at)

    def lot(self) -> OwnedLot:
        [held] = [held for held in self.engine.ledger.lots() if held.symbol == PAIR]
        return held

    def parts(self, post: str = "1") -> tuple:
        return self.engine.ledger.message(f"discord:demo:{post}").parts

    def events(self, kind: type) -> list[JournalEvent]:
        return [saved for saved in self.store.events if isinstance(saved.payload, kind)]


def coin_event(
    id: str = "1",
    action: str = "buy",
    price: str = "81000",
    entry: str | None = None,
    *,
    at: dt.datetime = SATURDAY_NIGHT,
) -> dict:
    message = event(id, action, price, entry, timestamp=at)
    [instruction] = message["instructions"]
    instruction["symbol"] = PAIR
    message["evidence"] = [
        instruction
        | {
            "action_evidence": "synthetic",
            "symbol_evidence": "BTC",
            "price_evidence": price,
            "entry_evidence": entry,
            "fraction_evidence": None,
        }
    ]
    return message


def coin_account(*, environment: str = "paper", **limits: object) -> Account:
    broker = FakeBroker()
    store = MemoryRepository()
    engine = CopyEngine(store, broker, CopyConfig(sources=["discord:demo"], **limits))
    engine.bind(SATURDAY_NIGHT, environment=environment)
    return Account(engine, broker, store, environment)


def later(minutes: int) -> dt.datetime:
    return SATURDAY_NIGHT + dt.timedelta(minutes=minutes)


def test_a_coin_is_bought_on_a_saturday_night_good_till_canceled_and_without_hours():
    account = coin_account()

    account.copy(coin_event())

    [order] = account.engine.ledger.orders()
    assert (order.symbol, order.session) == (PAIR, Session.AROUND_THE_CLOCK)
    sent = account.broker.orders[order.client_id]
    assert sent["time_in_force"] == "gtc"
    assert "extended_hours" not in sent
    # A sixth of a $600 position is $100: 0.001234567 BTC at $81,000, to the billionth.
    assert (order.qty, order.limit_price) == (Decimal("0.001234567"), Decimal(81000))


def test_the_lot_holds_what_alpaca_delivered_after_its_fee():
    account = coin_account()

    account.copy(coin_event())

    [order] = account.engine.ledger.orders()
    fee = Decimal("0.000003086")  # 0.25% of 0.001234567, to the billionth
    assert order.filled_qty == Decimal("0.001234567")
    assert (order.fee_qty, order.received_qty) == (fee, Decimal("0.001231481"))
    assert account.broker.holdings[PAIR] == order.received_qty
    held = account.lot()
    assert held.remaining_qty == held.original_qty == order.received_qty
    assert held.entry_remaining == {order.client_id: order.received_qty}
    assert account.engine.audit_positions().matched
    [counted] = account.events(CryptoFeeCounted)
    assert counted.payload.fees == {order.client_id: fee}
    assert counted.payload.filled_qty == order.filled_qty


def test_alpacas_btcusd_holding_is_the_btc_usd_lot():
    account = coin_account()
    account.copy(coin_event())

    [position] = account.broker.positions()

    assert position.symbol == PAIR
    assert account.engine.ledger.expected_position(PAIR) == position.qty
    assert [p.symbol for p in account.engine.audit_positions().positions] == [PAIR]


def test_half_then_all_sells_exactly_what_was_received():
    account = coin_account()
    account.copy(coin_event())
    received = account.broker.holdings[PAIR]

    account.copy(coin_event("2", "reduce", "82000", at=later(1)))
    half = next(o for o in account.engine.ledger.orders() if o.side == "sell")
    assert half.qty == (received / 2).quantize(COIN, rounding=ROUND_DOWN)
    assert account.broker.orders[half.client_id]["time_in_force"] == "gtc"
    assert account.lot().remaining_qty == account.broker.holdings[PAIR] == received - half.qty

    account.copy(coin_event("3", "close", "83000", at=later(2)))
    assert account.broker.holdings[PAIR] == 0
    assert account.lot().remaining_qty == 0
    assert account.engine.audit_positions().matched


def test_a_sell_naming_a_buy_price_sells_only_that_buy():
    account = coin_account(max_symbol_usd=Decimal(1000))
    account.copy(coin_event("1", price="81000"))
    account.copy(coin_event("2", price="80000", at=later(1)))
    first, second = account.engine.ledger.orders()

    account.copy(coin_event("3", "close", "82000", "81000", at=later(2)))

    assert account.lot().entry_remaining == {
        first.client_id: 0,
        second.client_id: second.received_qty,
    }
    assert account.broker.holdings[PAIR] == second.received_qty
    assert account.engine.audit_positions().matched


def test_a_sell_waits_at_its_floor_and_is_never_cancelled_for_waiting():
    account = coin_account(order_timeout_seconds=60)
    account.copy(coin_event())
    account.broker.auto_fill = False

    account.copy(coin_event("2", "close", "90000", at=later(1)))
    sell = next(o for o in account.engine.ledger.orders() if o.side == "sell")
    # The floor is the guru's price less the account's 1% allowance.
    assert sell.limit_price == Decimal(89100)
    assert account.broker.orders[sell.client_id]["time_in_force"] == "gtc"

    account.engine.reconcile(later(60 * 48))

    assert account.engine.ledger.order(sell.client_id).status == OrderStatus.NEW
    assert account.broker.orders[sell.client_id]["status"] == "new"


def test_a_coin_buy_still_times_out():
    account = coin_account(order_timeout_seconds=60)
    account.broker.auto_fill = False
    account.copy(coin_event())

    account.engine.reconcile(later(2))

    [buy] = account.engine.ledger.orders()
    assert account.broker.orders[buy.client_id]["status"] == "canceled"


def test_a_live_account_never_sends_a_coin_and_says_so():
    account = coin_account(environment="live")

    account.copy(coin_event())

    assert account.broker.calls == 0
    assert account.parts() == (SkippedPart(reason="crypto_paper_only"),)
    [skipped] = account.events(Skipped)
    notice = execution_notification(account.engine.ledger.state, skipped)
    assert notice is not None
    assert notice.payload.annotations["evidence"] == (
        "paper-demo is a live account, and crypto is copied on paper accounts only"
    )


def test_a_live_account_skips_a_coin_sell_too():
    account = coin_account(environment="live")

    account.copy(coin_event("1", "close", "81000"))

    assert account.broker.calls == 0
    assert account.parts() == (SkippedPart(reason="crypto_paper_only"),)


def test_a_coin_buy_under_alpacas_ten_dollar_minimum_is_skipped():
    account = coin_account(max_order_usd=Decimal(9))

    account.copy(coin_event())

    assert account.broker.calls == 0
    assert account.parts() == (SkippedPart(reason="below_minimum_budget"),)


def test_ten_dollars_that_round_under_ten_at_the_coins_step_is_skipped():
    account = coin_account(max_order_usd=Decimal(10))

    account.copy(coin_event(price="81497.61"))

    assert account.broker.calls == 0
    assert account.parts() == (SkippedPart(reason="below_minimum_budget"),)


def test_the_fee_waits_while_an_order_of_the_coin_is_still_filling():
    account = coin_account()
    broker = account.broker
    broker.auto_fill = False
    account.copy(coin_event())
    [buy] = account.engine.ledger.orders()
    broker.fill(buy.client_id, "0.0006")
    read = broker.positions

    def filled_while_read():
        held = read()
        broker.fill(buy.client_id, "0.0007")
        return held

    broker.positions = filled_while_read
    account.engine.reconcile(SATURDAY_NIGHT)
    order = account.engine.ledger.order(buy.client_id)
    assert (order.filled_qty, order.fee_settled_qty, order.fee_qty) == (Decimal("0.0006"), 0, 0)
    assert not account.engine.ledger.unresolved_ownership(PAIR)

    broker.positions = read
    account.engine.reconcile(SATURDAY_NIGHT)

    order = account.engine.ledger.order(buy.client_id)
    assert order.fee_settled_qty == Decimal("0.0007")
    assert order.fee_qty == Decimal("0.00000175")
    assert account.lot().remaining_qty == broker.holdings[PAIR]
    assert account.engine.audit_positions().matched


def test_a_shortfall_no_fee_can_be_is_left_to_the_holdings_check():
    account = coin_account()
    account.broker.auto_fill = False
    account.copy(coin_event())
    [buy] = account.engine.ledger.orders()
    account.broker.fill(buy.client_id, str(buy.qty))
    # The owner sold most of it in Alpaca before CopyTrading synced.
    account.broker.holdings[PAIR] -= Decimal("0.001")

    account.engine.reconcile(SATURDAY_NIGHT)

    assert account.engine.ledger.order(buy.client_id).fee_qty == 0
    assert account.engine.audit_positions().positions[0].mismatched
    assert account.engine.ledger.unresolved_ownership(PAIR)


def test_a_new_buy_waits_until_the_last_buys_fee_is_counted():
    account = coin_account(max_symbol_usd=Decimal(1000))
    account.copy(coin_event(), sync=False)

    account.copy(coin_event("2", price="80000", at=SATURDAY_NIGHT), sync=False)
    assert account.broker.calls == 1
    assert account.parts("2") == (Pending(),)

    account.engine.reconcile(SATURDAY_NIGHT)
    account.engine.process(SATURDAY_NIGHT)
    assert account.broker.calls == 2
    assert account.engine.ledger.order(
        account.engine.ledger.orders()[0].client_id
    ).fee_qty == Decimal("0.000003086")


@pytest.mark.parametrize("environment", ["paper", "live"])
def test_a_stock_order_is_still_a_day_order_on_either_account(environment):
    account = coin_account(environment=environment)

    account.copy(event(timestamp=dt.datetime(2026, 10, 26, 15, tzinfo=dt.UTC)))

    [order] = account.engine.ledger.orders()
    assert order.session == Session.REGULAR
    assert account.broker.orders[order.client_id]["time_in_force"] == "day"
    assert account.broker.orders[order.client_id]["extended_hours"] is False


def test_a_fee_event_reads_back_from_its_json():
    account = coin_account()
    account.copy(coin_event())

    for saved in account.store.events:
        assert JournalEvent.model_validate_json(saved.model_dump_json()) == saved


def test_a_stock_buy_counts_the_coin_held_beside_it():
    account = coin_account(max_total_usd=Decimal(150))
    account.copy(coin_event())

    account.copy(event("2", timestamp=dt.datetime(2026, 10, 26, 15, tzinfo=dt.UTC)))

    stock = next(o for o in account.engine.ledger.orders() if o.symbol == "ABC")
    # $100 bought $99.75 of coin after the fee, which leaves $50.25 of the $150 for the stock.
    assert (stock.budget_usd, stock.limited_by) == (Decimal("50.25"), "total_exposure_cap")
