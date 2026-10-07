"""State ownership, atomic failures, and recovery through the real application port."""

import datetime as dt
import json
from decimal import Decimal

import pytest
from pydantic import ValidationError

from copytrading_engine.execution.application.engine import CopyEngine
from copytrading_engine.execution.domain.ledger_state import LedgerSnapshot
from copytrading_engine.execution.domain.progress import Skipped
from copytrading_engine.execution.domain.signals import CopyConfig
from copytrading_engine.shared.signals import StockSignal

from .builders import NOW, event, manual_sale, receive, system_with_queued_buy
from .fakes import FakeBroker, MemoryRepository


def test_failed_intent_commit_cannot_submit_or_mutate_memory():
    engine, broker, repository = system_with_queued_buy()
    before = engine.ledger.snapshot()
    repository.fail_commit = True
    with pytest.raises(RuntimeError, match="persistence"):
        engine.process(NOW)
    assert broker.calls == 0
    assert engine.ledger.snapshot() == before == repository.load()


def test_failed_fill_commit_recovers_accepted_order_without_resubmission():
    engine, broker, repository = system_with_queued_buy()
    repository.fail_event = "order_update"
    with pytest.raises(RuntimeError, match="persistence"):
        engine.process(NOW)
    assert broker.calls == 1
    assert engine.ledger.lots() == ()
    assert engine.ledger.snapshot() == repository.load()
    restarted_store = MemoryRepository(repository.snapshot_json)
    restarted = CopyEngine(restarted_store, broker, engine.config)
    restarted.bind(NOW)
    restarted.reconcile(NOW)
    restarted.process(NOW)
    restarted.reconcile(NOW)
    assert broker.calls == 1
    assert restarted.ledger.owned("ABC") == Decimal("4")
    assert len([e for e in restarted_store.events if e.payload.kind == "order_update"]) == 1


def test_snapshot_and_records_cannot_be_used_to_mutate_the_ledger():
    engine, _, _ = system_with_queued_buy()
    engine.process(NOW)
    snapshot = engine.ledger.snapshot()
    snapshot.orders.clear()
    snapshot.lots.clear()
    assert len(engine.ledger.orders()) == 1
    assert engine.ledger.owned("ABC") == 4
    with pytest.raises(ValidationError):
        engine.ledger.lots()[0].remaining_qty = Decimal(0)
    with pytest.raises(ValidationError):
        engine.ledger.message("discord:demo:1").instructions[0].price = Decimal(1)


@pytest.mark.parametrize("corruption", ["missing_lot", "remaining_qty", "message_id", "client_id"])
def test_corrupt_saved_references_and_quantities_are_rejected(corruption):
    engine, _, _ = system_with_queued_buy()
    engine.process(NOW)
    snapshot = engine.ledger.snapshot().model_dump(mode="json")
    key = next(iter(snapshot["orders"]))
    if corruption == "missing_lot":
        snapshot["lots"].clear()
    elif corruption == "remaining_qty":
        snapshot["lots"][key]["remaining_qty"] = "3"
    else:
        snapshot["orders"][key][corruption] = "another-order"
    with pytest.raises(ValidationError):
        LedgerSnapshot.model_validate_json(json.dumps(snapshot))


@pytest.mark.parametrize(
    "snapshot",
    [
        {"account_id": None, "cursor": None, "messages": {}, "orders": {}, "lots": {}},
        {"schema_version": True},
        {"schema_version": 1},
    ],
)
def test_only_current_snapshot_format_is_accepted(snapshot):
    with pytest.raises(ValidationError):
        LedgerSnapshot.model_validate_json(json.dumps(snapshot))


def test_snapshot_v9_is_the_only_supported_runtime_format():
    current = LedgerSnapshot()

    assert current.schema_version == 10
    with pytest.raises(ValidationError):
        LedgerSnapshot.model_validate_json(json.dumps({"schema_version": 8}))


def test_regressing_fill_cannot_change_committed_state():
    engine, broker, repository = system_with_queued_buy()
    broker.auto_fill = False
    engine.process(NOW)
    key = next(iter(broker.orders))
    broker.fill(key, "2")
    engine.reconcile(NOW)
    before = engine.ledger.snapshot()
    broker.orders[key]["filled_qty"] = "1"
    with pytest.raises(RuntimeError, match="inconsistent"):
        engine.reconcile(NOW)
    assert engine.ledger.snapshot() == before == repository.load()


def test_numerically_equivalent_repost_does_not_create_another_order():
    engine, broker, _ = system_with_queued_buy()
    engine.process(NOW)
    receive(engine, StockSignal.model_validate(event(id="repost", price="25.0")), NOW)
    engine.process(NOW)
    assert broker.calls == 1
    assert engine.ledger.message("discord:demo:repost").parts == (Skipped(reason="duplicate"),)


def test_with_the_repeat_check_off_an_identical_post_buys_again():
    engine, broker, _ = system_with_queued_buy()
    engine.process(NOW)
    repost = StockSignal.model_validate(event(id="repost"))
    receive(engine, repost, NOW, repeat_window_minutes=None)
    engine.process(NOW)
    assert broker.calls == 2
    assert engine.ledger.message("discord:demo:repost").parts != (Skipped(reason="duplicate"),)


@pytest.mark.parametrize(("window", "repeat"), [(10, False), (30, True)])
def test_the_guru_window_decides_whether_a_later_identical_buy_is_a_repost(window, repeat):
    engine, broker, _ = system_with_queued_buy()
    engine.process(NOW)
    later = NOW + dt.timedelta(minutes=20)
    receive(
        engine,
        StockSignal.model_validate(event(id="later", timestamp=later)),
        later,
        repeat_window_minutes=window,
    )
    engine.process(later)
    skipped = engine.ledger.message("discord:demo:later").parts == (Skipped(reason="duplicate"),)
    assert skipped is repeat
    assert broker.calls == (1 if repeat else 2)


@pytest.mark.parametrize(
    ("decision", "status"), [("review", "review_required"), ("ignore", "ignored")]
)
def test_nontrade_decision_keeps_parser_reason_and_never_calls_broker(decision, status):
    repository = MemoryRepository()
    broker = FakeBroker()
    engine = CopyEngine(repository, broker, CopyConfig(sources=["discord:demo"]))
    engine.bind(NOW)
    signal = event() | {
        "decision": decision,
        "reason": "invalid_model_output",
        "instructions": [],
        "evidence": [],
    }
    receive(engine, StockSignal.model_validate(signal), NOW)
    engine.process(NOW)
    message = engine.ledger.message("discord:demo:1")
    assert message.status == status
    assert message.reason == "invalid_model_output"
    journal = next(item for item in repository.events if item.payload.kind == "message")
    from copytrading_engine.execution.domain.events import Message

    assert isinstance(journal.payload, Message)
    assert journal.payload.parser_decision == decision
    assert journal.payload.parser_reason == "invalid_model_output"
    assert broker.calls == 0


@pytest.mark.parametrize("decision", ["review", "ignore"])
def test_future_nontrade_timestamp_cannot_poison_trade_ordering(decision):
    import datetime as dt

    repository = MemoryRepository()
    broker = FakeBroker()
    engine = CopyEngine(repository, broker, CopyConfig(sources=["discord:demo"]))
    engine.bind(NOW)
    nontrade = event() | {
        "id": "future",
        "timestamp": (NOW + dt.timedelta(days=1)).isoformat(),
        "decision": decision,
        "reason": "stale_signal",
        "instructions": [],
        "evidence": [],
    }
    receive(engine, StockSignal.model_validate(nontrade), NOW)
    receive(engine, StockSignal.model_validate(event()), NOW)
    assert engine.ledger.message("discord:demo:1").status == "queued"


def test_verified_manual_sale_is_atomic_audited_and_idempotent_after_restart():
    import datetime as dt

    engine, broker, repository = system_with_queued_buy()
    engine.process(NOW)
    before = engine.ledger.snapshot()
    sale = manual_sale(engine)
    repository.fail_commit = True
    with pytest.raises(RuntimeError, match="persistence"):
        engine.ledger.record_manual_sale(sale)
    assert engine.ledger.snapshot() == before == repository.load()
    repository.fail_commit = False
    engine.ledger.record_manual_sale(sale)
    after = repository.load()
    assert after.orders == before.orders
    assert after.messages == before.messages
    assert engine.ledger.owned("ABC") == 0
    from copytrading_engine.execution.domain.events import ManualSaleRecorded

    assert isinstance(repository.events[-1].payload, ManualSaleRecorded)
    assert repository.events[-1].payload.previous_remaining_qty == Decimal("4")
    assert after.manual_sales[sale.order.id] == sale
    restarted_store = MemoryRepository(repository.snapshot_json)
    restarted = CopyEngine(restarted_store, broker, engine.config)
    restarted.ledger.record_manual_sale(
        sale.model_copy(update={"recorded_at": NOW + dt.timedelta(seconds=1)})
    )
    assert not restarted_store.events
    assert restarted.ledger.owned("ABC") == 0
    assert broker.calls == 1


@pytest.mark.parametrize("kind", ["wrong_symbol", "unknown_lot", "too_many", "copier_order"])
def test_manual_sale_rejects_invalid_evidence_without_changing_state(kind):
    engine, _, repository = system_with_queued_buy()
    engine.process(NOW)
    before = engine.ledger.snapshot()
    data = manual_sale(engine).model_dump()
    if kind == "wrong_symbol":
        data["order"]["symbol"] = "OTHER"
    elif kind == "unknown_lot":
        data["lot_id"] = "unknown"
    elif kind == "too_many":
        data["order"].update(qty=Decimal("5"), filled_qty=Decimal("5"))
    else:
        data["order"]["id"] = engine.ledger.orders()[0].broker_id
    expected = {
        "wrong_symbol": "Manual sale does not match an owned lot",
        "unknown_lot": "Manual sale does not match an owned lot",
        "too_many": "Manual sale exceeds remaining owned lot shares",
        "copier_order": "Manual sale duplicates an already recorded order",
    }
    with pytest.raises(ValueError, match=expected[kind]):
        engine.ledger.record_manual_sale(manual_sale(engine, **data))
    assert before == engine.ledger.snapshot() == repository.load()


def test_manual_sale_cannot_hide_a_pending_order_or_duplicate_changed_evidence():
    from .builders import deliver

    engine, broker, _ = system_with_queued_buy()
    engine.process(NOW)
    sale = manual_sale(engine)
    broker.auto_fill = False
    deliver(engine, event("exit", "reduce", "27", "25"))
    with pytest.raises(ValueError, match="pending"):
        engine.ledger.record_manual_sale(sale)
    engine.cancel(engine.pending()[0], NOW)
    engine.reconcile(NOW)
    engine.ledger.record_manual_sale(sale)
    with pytest.raises(ValueError, match="different evidence"):
        engine.ledger.record_manual_sale(sale.model_copy(update={"reason": "changed"}))


def test_manual_sale_snapshot_cannot_be_tampered_with():
    engine, _, _ = system_with_queued_buy()
    engine.process(NOW)
    engine.ledger.record_manual_sale(manual_sale(engine))
    data = engine.ledger.snapshot().model_dump()
    data["manual_sales"].clear()
    with pytest.raises(ValueError, match="recorded sell fills"):
        LedgerSnapshot.model_validate(data)


def test_repository_cannot_retain_mutable_ownership_of_loaded_or_saved_state():
    from copytrading_engine.execution.application.ledger import TradingLedger
    from copytrading_engine.execution.application.ports import NoOpObserver

    engine, _, _ = system_with_queued_buy()
    engine.process(NOW)

    class RetainingRepository:
        def __init__(self):
            self.state = engine.ledger.snapshot()
            self.fail_commit = False

        def load(self):
            return self.state

        def save(self, snapshot, event):
            self.state = snapshot
            if self.fail_commit:
                snapshot.lots.clear()
                raise RuntimeError("simulated persistence failure")

    repository = RetainingRepository()
    ledger = TradingLedger(repository, NoOpObserver())
    before = ledger.snapshot()
    repository.state.lots.clear()
    assert ledger.snapshot() == before
    from copytrading_engine.execution.domain.events import AccountBound, JournalEvent

    event = JournalEvent(at=NOW, payload=AccountBound(endpoint="paper"))
    ledger.record(event)
    repository.state.orders.clear()
    assert ledger.snapshot() == before
    repository.fail_commit = True
    with pytest.raises(RuntimeError, match="persistence"):
        ledger.record(event)
    assert ledger.snapshot() == before


def test_repository_load_revalidates_a_mutated_snapshot():
    from copytrading_engine.execution.application.ledger import TradingLedger
    from copytrading_engine.execution.application.ports import NoOpObserver

    engine, _, repository = system_with_queued_buy()
    engine.process(NOW)
    corrupted = engine.ledger.snapshot()
    corrupted.lots.clear()
    repository.load = lambda: corrupted
    with pytest.raises(ValidationError, match="Entry fills require"):
        TradingLedger(repository, NoOpObserver())


def test_buy_plan_cannot_hide_an_empty_lot_reference():
    from copytrading_engine.execution.domain.orders import OrderPlan

    engine, _, _ = system_with_queued_buy()
    engine.process(NOW)
    data = engine.ledger.orders()[0].model_dump(include=set(OrderPlan.model_fields))
    with pytest.raises(ValidationError):
        OrderPlan.model_validate(data | {"lot_id": ""})
