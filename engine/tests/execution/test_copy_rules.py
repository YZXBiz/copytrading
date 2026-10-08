"""The copy rules of ADR-0007 at the account: a buy is bounded by its limit alone, a guru whose
sells refer to the whole position, and a trim the maximum per order makes."""

import datetime as dt
from decimal import Decimal

import pytest

from copytrading_engine.execution.application.engine import CopyEngine
from copytrading_engine.execution.domain.manual_commands import ManualCorrectionRecord
from copytrading_engine.execution.domain.market import Quote
from copytrading_engine.execution.domain.progress import Skipped
from copytrading_engine.execution.domain.signals import CopyConfig
from copytrading_engine.shared.signals import StockSignal

from .builders import NOW, deliver, event
from .fakes import FakeBroker, MemoryRepository


class QuotingBroker(FakeBroker):
    """A broker whose quote for every symbol is `ask`, as of `quoted_at`."""

    def __init__(self, ask: str, quoted_at: dt.datetime = NOW) -> None:
        super().__init__()
        self.ask = Decimal(ask)
        self.quoted_at = quoted_at

    def quote(self, symbol: str) -> Quote:
        return Quote(
            feed="iex", bid=self.ask - Decimal("0.01"), ask=self.ask, timestamp=self.quoted_at
        )


def _engine(broker: FakeBroker) -> CopyEngine:
    engine = CopyEngine(MemoryRepository(), broker, CopyConfig(sources=["discord:demo"]))
    engine.bind(NOW)
    return engine


def _outcome(engine: CopyEngine, message_id: str = "1") -> object:
    return engine.ledger.message(f"discord:demo:{message_id}").parts[0]


# --- A buy is bounded by its limit, not by how far the market has moved --------------------------


@pytest.mark.parametrize("ask", ["40", "10"], ids=["far-above", "far-below"])
def test_a_buy_goes_out_at_its_limit_however_far_the_market_has_moved(ask):
    broker = QuotingBroker(ask)
    engine = _engine(broker)

    deliver(engine, event())

    [order] = engine.ledger.orders()
    assert broker.calls == 1, "nothing holds a buy back because of the market's distance"
    assert order.limit_price == Decimal(25)


# --- A sell that names no buy sells from every buy (ADR-0010) ------------------------------------


def _whole(message: dict) -> dict:
    """A call that names no buy price: a sell then refers to every buy of the stock."""
    for item in (*message["instructions"], *message["evidence"]):
        if item["action"] != "buy":
            item["entry_price"] = None
    for item in message["evidence"]:
        item["entry_evidence"] = None
    return message


def test_buys_at_different_prices_join_one_position_that_a_sell_naming_no_buy_sells():
    broker = FakeBroker()
    engine = _engine(broker)

    deliver(engine, _whole(event("1", price="25")))
    deliver(engine, _whole(event("2", price="20", timestamp=NOW + dt.timedelta(seconds=1))))

    [lot] = [lot for lot in engine.ledger.lots() if lot.remaining_qty > 0]
    assert (lot.entry_price, lot.remaining_qty) == (Decimal(25), Decimal(9))

    deliver(engine, _whole(event("3", "close", "30", timestamp=NOW + dt.timedelta(seconds=2))))
    assert broker.holdings["ABC"] == 0
    assert all(lot.remaining_qty == 0 for lot in engine.ledger.lots())


def test_half_naming_no_buy_sells_half_of_everything_bought():
    broker = FakeBroker()
    engine = _engine(broker)
    deliver(engine, _whole(event("1", price="25")))
    deliver(engine, _whole(event("2", price="20", timestamp=NOW + dt.timedelta(seconds=1))))

    deliver(engine, _whole(event("3", "reduce", "30", timestamp=NOW + dt.timedelta(seconds=2))))

    assert broker.holdings["ABC"] == Decimal("4.5")


def test_a_sell_naming_no_buy_with_nothing_held_sells_nothing():
    broker = FakeBroker()
    engine = _engine(broker)

    deliver(engine, _whole(event("1", "close", "30")))

    assert _outcome(engine) == Skipped(reason="lot_unavailable")
    assert broker.calls == 0


# --- The maximum per order trims, and the trim is kept ------------------------------------------


def test_a_trimmed_buy_keeps_what_the_call_asked_for():
    broker = FakeBroker()
    engine = _engine(broker)
    message = event()
    for item in (*message["instructions"], *message["evidence"]):
        item["fraction"] = "0.5"

    deliver(engine, message)

    [order] = engine.ledger.orders()
    assert order.requested_usd == Decimal("300.00")
    assert order.qty * order.limit_price == Decimal(100)


# --- A call held for the owner can be copied by hand, a traded one cannot ------------------------


def _correction(engine: CopyEngine, message_id: str = "1") -> ManualCorrectionRecord:
    message = engine.ledger.message(f"discord:demo:{message_id}")
    signal = StockSignal.model_validate(
        {name: getattr(message, name) for name in StockSignal.model_fields}
    )
    return ManualCorrectionRecord(
        correction_id="copy-1",
        source_id=message.key,
        selected_account_ids=("paper-demo",),
        revision=1,
        actor="owner",
        reason="Copied a waiting call",
        instructions=signal.instructions,
        source_revision=1,
        source_at=signal.timestamp,
        source_text=signal.text,
        accepted_interpretation=signal,
        recorded_at=NOW,
    )


def _approving(broker: FakeBroker) -> CopyEngine:
    engine = CopyEngine(
        MemoryRepository(), broker, CopyConfig(sources=["discord:demo"], approve_orders=True)
    )
    engine.bind(NOW)
    return engine


def test_a_buy_held_for_approval_can_be_copied_by_hand():
    engine = _approving(FakeBroker())
    deliver(engine, event())
    assert _outcome(engine) == Skipped(reason="approval_required")

    recorded = engine.ledger.record_manual_correction(_correction(engine))

    assert recorded.correction_id == "copy-1"


def test_a_call_the_account_already_traded_cannot_be_copied_again():
    engine = _engine(FakeBroker())
    deliver(engine, event())
    assert engine.ledger.orders()

    with pytest.raises(ValueError, match="reviewed source evidence"):
        engine.ledger.record_manual_correction(_correction(engine))


def test_a_held_buy_alerts_that_it_waits_for_the_owner():
    from copytrading_engine.execution.presentation.notifications import execution_notification

    store = MemoryRepository()
    engine = CopyEngine(
        store, FakeBroker(), CopyConfig(sources=["discord:demo"], approve_orders=True)
    )
    engine.bind(NOW)
    deliver(engine, event())
    held = next(
        alert
        for journal_event in store.events
        if (alert := execution_notification(engine.ledger.snapshot(), journal_event)) is not None
        and "waiting" in alert.payload.annotations["summary"]
    )

    assert held.payload.annotations["summary"] == "ABC — waiting for you"
    assert "approve or skip" in held.payload.annotations["evidence"]


def test_activity_shows_what_a_trimmed_buy_asked_for_and_which_limit_a_skip_hit():
    from copytrading_engine.execution.presentation.operator_views import destination_views

    engine = _engine(FakeBroker())
    trimmed = event("1")
    for item in (*trimmed["instructions"], *trimmed["evidence"]):
        item["fraction"] = "0.5"
    deliver(engine, trimmed)
    engine.config = CopyConfig.model_validate(
        engine.config.model_dump() | {"max_symbol_usd": "150", "max_order_usd": "150"}
    )
    later = NOW + dt.timedelta(minutes=11)
    deliver(engine, event("2", timestamp=later), later)

    views = destination_views(engine.ledger.snapshot(), {"discord:demo:1", "discord:demo:2"})

    [order] = views["discord:demo:1"].orders
    assert (order.instruction_index, order.requested_usd, order.budget_usd) == (0, 300, 100)
    [limit] = views["discord:demo:2"].limits_hit
    assert (limit.part, limit.scope, limit.limit) == (0, "symbol", 150)
