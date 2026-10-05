"""The copy rules of ADR-0007 at the account: how far the market may have moved, a guru whose
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

# 08:00 in New York: before the open, when extended hours apply.
PREMARKET = dt.datetime(2026, 1, 5, 13, tzinfo=dt.UTC)


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


# --- How far the market may have moved from the guru's $25 --------------------------------------


@pytest.mark.parametrize(
    ("ask", "at", "moved"),
    [
        pytest.param("26.24", NOW, False, id="regular-4.96%-above"),
        pytest.param("26.26", NOW, True, id="regular-5.04%-above"),
        pytest.param("23.74", NOW, True, id="regular-5.04%-below"),
        pytest.param("27.49", PREMARKET, False, id="extended-9.96%-above"),
        pytest.param("27.51", PREMARKET, True, id="extended-10.04%-above"),
        pytest.param("22.49", PREMARKET, True, id="extended-10.04%-below"),
    ],
)
def test_a_buy_waits_when_the_market_is_too_far_from_the_gurus_price(ask, at, moved):
    broker = QuotingBroker(ask, quoted_at=at)
    engine = _engine(broker)

    deliver(engine, event(timestamp=at), at)

    if moved:
        assert _outcome(engine) == Skipped(reason="price_moved")
        assert broker.calls == 0
    else:
        assert broker.calls == 1


def test_without_a_fresh_quote_the_limit_alone_bounds_the_buy():
    broker = QuotingBroker("40", quoted_at=NOW - dt.timedelta(minutes=5))
    engine = _engine(broker)

    deliver(engine, event())

    [order] = engine.ledger.orders()
    assert order.limit_price == Decimal(25)


def test_the_owner_copying_a_call_by_hand_is_not_held_by_the_market_check():
    broker = QuotingBroker("40")
    engine = _engine(broker)
    deliver(engine, event())

    decision = engine.decide(
        engine.ledger.message("discord:demo:1").instructions[0],
        "discord:demo:1",
        "discord:demo",
        NOW,
        halted=False,
        manual=True,
    )

    assert decision.reason != "price_moved"


# --- A guru whose sells refer to the whole position ---------------------------------------------


def _whole(message: dict) -> dict:
    """A call from a guru whose every buy of a stock is one position."""
    for item in (*message["instructions"], *message["evidence"]):
        item["whole_position"] = True
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


def test_half_of_the_whole_position_sells_half_of_everything_bought():
    broker = FakeBroker()
    engine = _engine(broker)
    deliver(engine, _whole(event("1", price="25")))
    deliver(engine, _whole(event("2", price="20", timestamp=NOW + dt.timedelta(seconds=1))))

    deliver(engine, _whole(event("3", "reduce", "30", timestamp=NOW + dt.timedelta(seconds=2))))

    assert broker.holdings["ABC"] == Decimal("4.5")


def test_a_whole_position_sell_with_nothing_held_sells_nothing():
    broker = FakeBroker()
    engine = _engine(broker)

    deliver(engine, _whole(event("1", "close", "30")))

    assert _outcome(engine) == Skipped(reason="missing_or_ambiguous_lot")
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


def test_a_buy_held_because_the_market_moved_can_be_copied_by_hand():
    engine = _engine(QuotingBroker("40"))
    deliver(engine, event())
    assert _outcome(engine) == Skipped(reason="price_moved")

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
    engine = CopyEngine(store, QuotingBroker("40"), CopyConfig(sources=["discord:demo"]))
    engine.bind(NOW)
    deliver(engine, event())
    held = next(
        alert
        for journal_event in store.events
        if (alert := execution_notification(engine.ledger.snapshot(), journal_event)) is not None
        and "waiting" in alert.payload.annotations["summary"]
    )

    assert held.payload.annotations["summary"] == "ABC — waiting for you"
    assert "copy or skip" in held.payload.annotations["evidence"]
