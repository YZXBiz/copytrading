"""Portfolio checks must run without signals and must never invent broker fills."""

import datetime as dt
from decimal import Decimal

import pytest

from copytrading_engine.execution.application.engine import CopyEngine
from copytrading_engine.execution.application.ports import BrokerError
from copytrading_engine.execution.domain.progress import Skipped
from copytrading_engine.execution.domain.signals import CopyConfig

from .builders import NOW, deliver, event
from .fakes import FakeBroker, MemoryRepository


@pytest.fixture
def copier():
    store = MemoryRepository()
    broker = FakeBroker()
    engine = CopyEngine(store, broker, CopyConfig(sources=["discord:demo"]))
    engine.bind(NOW)
    return engine, broker, store


def cycle(engine, now=NOW, *, halted=False):
    engine.reconcile(now)
    engine.process(now, halted=halted)
    return engine.audit_positions()


@pytest.mark.parametrize("actual", ["0", "3.999999", "5", "-4"])
def test_idle_cycle_detects_missing_partial_extra_and_short_positions(copier, actual):
    engine, broker, store = copier
    deliver(engine, event())
    snapshot = store.load()
    broker.holdings["ABC"] = Decimal(actual)
    audit = cycle(engine, NOW, halted=False)
    assert not audit.matched
    assert audit.health()["status"] == "mismatch"
    assert audit.positions[0].expected == 4
    assert audit.positions[0].actual == Decimal(actual)
    incidents = tuple(store.load().ownership_incidents.values())
    assert len(incidents) == 1
    assert incidents[0].expected_qty == 4
    assert incidents[0].actual_qty == Decimal(actual)
    assert snapshot.ownership_incidents == {}
    assert broker.calls == 1
    broker.holdings["ABC"] = Decimal(4)
    recovered = cycle(engine, NOW, halted=False)
    assert recovered.matched
    assert recovered.health()["differences"] == []
    assert not next(iter(store.load().ownership_incidents.values())).resolved


def test_multiple_lots_are_summed_and_unowned_broker_positions_are_detected(copier):
    engine, broker, _ = copier
    deliver(engine, event())
    deliver(
        engine,
        event("second", price="20", timestamp=NOW + dt.timedelta(minutes=11)),
        NOW + dt.timedelta(minutes=11),
    )
    assert engine.audit_positions().positions[0].expected == 9
    broker.holdings["XYZ"] = Decimal("1.25")
    audit = engine.audit_positions()
    assert audit.health()["differences"] == [
        {"symbol": "XYZ", "expected_qty": "0", "broker_qty": "1.25", "pending_fill_possible": False}
    ]


@pytest.mark.parametrize("side", ["buy", "sell"])
def test_fill_between_order_and_position_reads_is_reconciling_not_mismatch(copier, side):
    engine, broker, _ = copier
    if side == "sell":
        deliver(engine, event())
    broker.auto_fill = False
    deliver(
        engine,
        event(
            "pending",
            action="buy" if side == "buy" else "close",
            price="26",
            entry=None if side == "buy" else "25",
        ),
    )
    pending = engine.pending()[0]
    broker.fill(pending.client_id, "1")
    audit = engine.audit_positions()
    assert audit.health()["status"] == "reconciling"
    assert not audit.positions[0].mismatched
    engine.reconcile(NOW)
    assert engine.audit_positions().matched
    # A known pending fill must not hide an impossible holding outside its bounds.
    broker.holdings["ABC"] = Decimal(100)
    assert engine.audit_positions().positions[0].mismatched


def test_other_symbol_mismatch_allows_valued_entry_and_matching_lot_exit(copier):
    engine, broker, _ = copier
    deliver(engine, event())
    broker.holdings["XYZ"] = Decimal(1)
    later = NOW + dt.timedelta(minutes=11)
    deliver(engine, event("second", price="20", timestamp=later), later)
    assert broker.calls == 2
    deliver(engine, event("exit", action="close", price="27", entry="25", timestamp=later), later)
    assert broker.holdings["ABC"] == 5
    assert broker.calls == 3


def test_missing_lot_cannot_be_sold_or_recreated(copier):
    engine, broker, _ = copier
    deliver(engine, event())
    broker.holdings.clear()
    deliver(engine, event("exit", action="close", price="27", entry="25"))
    assert engine.ledger.message("discord:demo:exit").parts == (
        Skipped(reason="position_mismatch"),
    )
    assert engine.ledger.owned("ABC") == 4
    assert broker.calls == 1


def test_position_read_failure_cannot_be_a_successful_idle_cycle(copier):
    engine, broker, _ = copier

    def unavailable():
        raise BrokerError(503)

    broker.positions = unavailable
    with pytest.raises(BrokerError):
        cycle(engine, NOW, halted=False)
