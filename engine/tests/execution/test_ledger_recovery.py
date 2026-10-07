"""Durable release and late-order accounting for uncertain submissions."""

import datetime as dt
from decimal import Decimal

import pytest
from pydantic import ValidationError

from copytrading_engine.execution.application.engine import CopyEngine
from copytrading_engine.execution.domain.events import (
    LateOrderIncidentOpened,
    LateOrderIncidentReopened,
    OrderUpdate,
)
from copytrading_engine.execution.domain.ledger_state import LedgerSnapshot
from copytrading_engine.execution.domain.order_lifecycle import OrderStatus
from copytrading_engine.execution.domain.orders import OwnedLot
from copytrading_engine.execution.domain.progress import Skipped
from copytrading_engine.execution.domain.recovery import IncidentClearanceEvidence, ReleaseEvidence
from copytrading_engine.execution.domain.signals import CopyConfig
from copytrading_engine.shared.signals import StockSignal

from .builders import NOW, event, late_sell_with_consumed_source_lot, receive
from .builders import evidence as make_instruction_evidence
from .fakes import FakeBroker, MemoryRepository


def uncertain_system(*, auto_fill=False):
    repository = MemoryRepository()
    broker = FakeBroker()
    broker.auto_fill = auto_fill
    broker.timeout_after_accept = True
    engine = CopyEngine(repository, broker, CopyConfig(sources=["discord:demo"]))
    engine.bind(NOW)
    receive(engine, StockSignal.model_validate(event()), NOW)
    engine.process(NOW)
    order = engine.ledger.orders()[0]
    assert order.status is OrderStatus.UNCERTAIN
    return engine, broker, repository, order


def release_evidence(account_id="paper-demo", checked_at=None):
    return ReleaseEvidence(
        actor="operator@example.test",
        reason="broker histories confirm no accepted order or fills",
        order_history_ref="ticket-123-order-history",
        fill_history_ref="ticket-123-fill-history",
        checked_at=checked_at or NOW + dt.timedelta(seconds=1),
        account_id=account_id,
    )


def clearance_evidence(account_id="paper-demo", **changes):
    return IncidentClearanceEvidence(
        actor="operator@example.test",
        reason="matched position audit is clear",
        checked_at=NOW + dt.timedelta(seconds=5),
        account_id=account_id,
        matched_audit_ref="audit-123",
        **changes,
    )


def test_audited_release_frees_only_the_old_intent_for_future_independent_signals():
    engine, broker, repository, uncertain = uncertain_system()
    evidence = release_evidence()

    engine.ledger.release_uncertain_intent(uncertain.client_id, evidence)

    released = engine.ledger.order(uncertain.client_id)
    assert released.status is OrderStatus.RELEASED_UNSUBMITTED
    assert released.broker_id is None
    assert released.filled_qty == 0
    assert engine.ledger.pending("ABC") == ()
    assert engine.ledger.snapshot().release_evidence[uncertain.client_id] == evidence
    assert repository.events[-1].payload.kind == "order_intent_released"
    with pytest.raises(RuntimeError, match="prepared"):
        engine.ledger.submitting(uncertain.client_id, NOW + dt.timedelta(seconds=2))

    # The offline release is permitted only after the operator's broker lookup
    # confirmed the uncertain client ID is absent.
    broker.orders.pop(uncertain.client_id)
    broker.timeout_after_accept = False
    engine.process(NOW + dt.timedelta(seconds=1))
    assert broker.calls == 1
    future = event(
        id="future",
        price="26",
        timestamp=NOW + dt.timedelta(seconds=1),
    )
    receive(engine, StockSignal.model_validate(future), NOW + dt.timedelta(seconds=1))
    engine.process(NOW + dt.timedelta(seconds=1))

    assert broker.calls == 2
    assert engine.ledger.order(uncertain.client_id).status is OrderStatus.RELEASED_UNSUBMITTED
    assert engine.ledger.order(uncertain.client_id).broker_id is None
    assert len(engine.ledger.orders()) == 2


@pytest.mark.parametrize("bad_account", ["other-account"])
def test_release_rejects_evidence_for_a_different_account(bad_account):
    engine, _, repository, uncertain = uncertain_system()
    before = engine.ledger.snapshot()

    with pytest.raises(ValueError, match="account"):
        engine.ledger.release_uncertain_intent(uncertain.client_id, release_evidence(bad_account))

    assert engine.ledger.snapshot() == before == repository.load()


def test_release_rejects_a_non_uncertain_order():
    repository = MemoryRepository()
    broker = FakeBroker()
    broker.auto_fill = False
    engine = CopyEngine(repository, broker, CopyConfig(sources=["discord:demo"]))
    engine.bind(NOW)
    receive(engine, StockSignal.model_validate(event()), NOW)
    engine.process(NOW)
    order = engine.ledger.orders()[0]
    assert order.status is OrderStatus.NEW

    with pytest.raises(ValueError, match="uncertain"):
        engine.ledger.release_uncertain_intent(order.client_id, release_evidence())


@pytest.mark.parametrize("activity", ["broker_id", "fill"])
def test_release_requires_zero_saved_fills_and_no_broker_id(activity):
    engine, _, repository, uncertain = uncertain_system()
    snapshot = engine.ledger.snapshot()
    order_changes = (
        {"broker_id": "broker-already-known"}
        if activity == "broker_id"
        else {"filled_qty": Decimal("1")}
    )
    order = uncertain.model_copy(update=order_changes)
    lots = snapshot.lots
    if activity == "fill":
        lots = lots | {
            uncertain.client_id: OwnedLot(
                symbol=uncertain.symbol,
                entry_price=uncertain.entry_price,
                source_key=uncertain.source_key,
                original_qty=Decimal("1"),
                remaining_qty=Decimal("1"),
                average_price=uncertain.limit_price,
                entry_remaining={uncertain.client_id: Decimal("1")},
                entry_prices={uncertain.client_id: uncertain.entry_price},
            )
        }
    engine.ledger._snapshot = snapshot.model_copy(
        update={
            "orders": snapshot.orders | {uncertain.client_id: order},
            "lots": lots,
        }
    )
    before = engine.ledger.snapshot()

    with pytest.raises(ValueError, match=r"broker|fill"):
        engine.ledger.release_uncertain_intent(uncertain.client_id, release_evidence())

    assert engine.ledger.snapshot() == before
    assert repository.load().orders[uncertain.client_id].broker_id is None


def test_late_order_observation_reconciles_cumulative_fill_and_opens_one_persisted_incident():
    engine, broker, repository, uncertain = uncertain_system()
    evidence = release_evidence()
    engine.ledger.release_uncertain_intent(uncertain.client_id, evidence)
    broker.timeout_after_accept = False
    broker.fill(uncertain.client_id, str(uncertain.qty / 2))
    observation = broker.lookup(uncertain.client_id)

    engine.ledger.apply_order(uncertain.client_id, observation, NOW + dt.timedelta(seconds=1))

    snapshot = engine.ledger.snapshot()
    incident = snapshot.late_order_incidents[uncertain.client_id]
    assert snapshot.entry_halted
    assert snapshot.buy_halted
    assert incident.unresolved
    assert incident.broker_id == observation.id
    assert incident.raw_broker_status == "partially_filled"
    assert engine.ledger.order(uncertain.client_id).status is OrderStatus.PARTIALLY_FILLED
    assert engine.ledger.order(uncertain.client_id).raw_broker_status == "partially_filled"
    assert engine.ledger.order(uncertain.client_id).filled_qty == observation.filled_qty
    assert engine.ledger.owned("ABC") == observation.filled_qty
    assert repository.events[-1].payload.kind == "late_order_incident_opened"

    broker.fill(uncertain.client_id, str(uncertain.qty))
    engine.ledger.apply_order(
        uncertain.client_id,
        broker.lookup(uncertain.client_id),
        NOW + dt.timedelta(seconds=2),
    )

    updated = engine.ledger.snapshot().late_order_incidents[uncertain.client_id]
    assert updated.latest_filled_qty == uncertain.qty
    assert engine.ledger.order(uncertain.client_id).status is OrderStatus.FILLED
    assert engine.ledger.owned("ABC") == uncertain.qty
    assert len(engine.ledger.snapshot().late_order_incidents) == 1


def test_late_sell_overflow_is_quarantined_atomically_cumulatively_and_reloaded():
    engine, broker, repository, late_order, late_broker_record = (
        late_sell_with_consumed_source_lot()
    )
    late_broker_record["status"] = "new"
    broker.orders[late_order.client_id] = late_broker_record
    first_fill = late_order.qty / 2
    broker.fill(late_order.client_id, str(first_fill))
    before = engine.ledger.snapshot()
    repository.fail_event = "late_order_incident_opened"

    with pytest.raises(RuntimeError, match="simulated persistence failure"):
        engine.reconcile(NOW + dt.timedelta(minutes=4))

    assert engine.ledger.snapshot() == before == repository.load()
    assert engine.ledger.snapshot().late_order_incidents == {}

    repository.fail_event = None
    engine.reconcile(NOW + dt.timedelta(minutes=4))

    snapshot = engine.ledger.snapshot()
    evidence = snapshot.quarantined_fills[late_order.client_id]
    assert evidence.observed_filled_qty == first_fill
    assert evidence.applied_filled_qty == 0
    assert evidence.unapplied_qty == first_fill
    assert evidence.lot_id == late_order.lot_id
    assert snapshot.orders[late_order.client_id].filled_qty == first_fill
    assert snapshot.late_order_incidents[late_order.client_id].unresolved
    assert snapshot.entry_halted
    assert snapshot.buy_halted
    # Both ABC buys share one lot (ADR-0010): the sell named the first, which is sold out, and
    # the overflow never reaches the other buy.
    lot = snapshot.lots[late_order.lot_id]
    named = late_order.from_entries
    assert named
    assert all(lot.entry_remaining[entry] == 0 for entry in named)
    untouched = before.lots[late_order.lot_id].entry_remaining
    assert all(
        lot.entry_remaining[entry] == untouched[entry]
        for entry in lot.entry_remaining
        if entry not in named
    )
    assert all(lot.remaining_qty >= 0 for lot in snapshot.lots.values())
    report = repository.events[-1]
    assert isinstance(report.payload, LateOrderIncidentOpened)
    assert report.payload.unapplied_fill_qty == first_fill
    assert report.payload.late_order_incident.client_id == late_order.client_id

    event_count = len(repository.events)
    engine.reconcile(NOW + dt.timedelta(minutes=5))
    assert len(repository.events) == event_count
    assert engine.ledger.snapshot().quarantined_fills[late_order.client_id] == evidence

    broker.fill(late_order.client_id, str(late_order.qty))
    engine.reconcile(NOW + dt.timedelta(minutes=6))
    final_evidence = engine.ledger.snapshot().quarantined_fills[late_order.client_id]
    assert final_evidence.observed_filled_qty == late_order.qty
    assert final_evidence.applied_filled_qty == 0
    assert final_evidence.unapplied_qty == late_order.qty
    assert repository.load().quarantined_fills[late_order.client_id] == final_evidence

    restarted = CopyEngine(repository, broker, CopyConfig(sources=["discord:demo"]))
    assert restarted.ledger.snapshot().quarantined_fills[late_order.client_id] == final_evidence

    def_close_at = NOW + dt.timedelta(minutes=7)
    unrelated_exit = event(
        "def-close",
        "close",
        "27",
        "25",
        timestamp=def_close_at,
    )
    unrelated_exit["instructions"][0]["symbol"] = "DEF"
    unrelated_exit["evidence"] = [
        make_instruction_evidence(instruction) for instruction in unrelated_exit["instructions"]
    ]
    receive(engine, StockSignal.model_validate(unrelated_exit), def_close_at)
    engine.process(def_close_at)
    assert broker.holdings["DEF"] == 4
    assert engine.ledger.message("discord:demo:def-close").parts == (
        Skipped(reason="unresolved_order_incident"),
    )
    assert engine.ledger.snapshot().entry_halted


def test_released_fill_then_competing_close_fill_is_quarantined_and_reloaded(tmp_path):
    from copytrading_engine.execution.adapters.ownership_probe import has_unresolved_ownership
    from copytrading_engine.execution.application.recovery import RecoveryApplication
    from copytrading_engine.execution.domain.ownership import OwnershipResolutionRequest

    from .builders import save_snapshot

    repository = MemoryRepository()
    broker = FakeBroker()
    engine = CopyEngine(repository, broker, CopyConfig(sources=["discord:demo"]))
    engine.bind(NOW)
    receive(engine, StockSignal.model_validate(event("entry")), NOW)
    engine.process(NOW)
    lot_id = engine.ledger.orders()[0].client_id
    assert engine.ledger.lots()[0].remaining_qty == Decimal("4")

    reduction_at = NOW + dt.timedelta(minutes=1)
    broker.auto_fill = False
    broker.timeout_after_accept = True
    receive(
        engine,
        StockSignal.model_validate(
            event("released-reduction", "reduce", "27", "25", timestamp=reduction_at)
        ),
        reduction_at,
    )
    engine.process(reduction_at)
    reduction = next(order for order in engine.ledger.orders() if order.side == "sell")
    reduction_record = dict(broker.orders.pop(reduction.client_id))
    assert reduction.qty == Decimal("2")

    RecoveryApplication(
        engine.ledger,
        broker,
        clock=lambda: NOW + dt.timedelta(minutes=1, seconds=1),
    ).release_uncertain_intent(
        reduction.client_id,
        actor="operator@example.test",
        reason="Broker history confirms no accepted order or fills",
        order_history_ref="reverse-order-history",
        fill_history_ref="reverse-fill-history",
        account_id="paper-demo",
    )

    close_at = NOW + dt.timedelta(minutes=2)
    receive(
        engine,
        StockSignal.model_validate(
            event("independent-close", "close", "27", "25", timestamp=close_at)
        ),
        close_at,
    )
    engine.process(close_at)
    close = next(
        order
        for order in engine.ledger.orders()
        if order.client_id != reduction.client_id and order.side == "sell"
    )
    assert close.qty == Decimal("4")
    assert close.pending

    broker.timeout_after_accept = False
    reduction_record["status"] = "new"
    broker.orders[reduction.client_id] = reduction_record
    broker.fill(reduction.client_id, str(reduction.qty))
    engine.reconcile(NOW + dt.timedelta(minutes=3))

    incident = engine.ledger.snapshot().late_order_incidents[reduction.client_id]
    assert incident.unresolved
    assert engine.ledger.order(reduction.client_id).filled_qty == reduction.qty
    assert engine.ledger.snapshot().lots[lot_id].remaining_qty == Decimal("2")

    with pytest.raises(ValueError, match="Open orders"):
        RecoveryApplication(
            engine.ledger,
            broker,
            clock=lambda: NOW + dt.timedelta(minutes=3, seconds=1),
        ).clear_late_order_incident(
            reduction.client_id,
            actor="operator@example.test",
            reason="Verify the competing order blocks clearance",
            matched_audit_ref="pending-close-audit",
            account_id="paper-demo",
        )
    assert engine.ledger.snapshot().late_order_incidents[reduction.client_id].unresolved

    first_close_fill = Decimal("3")
    broker.fill(close.client_id, str(first_close_fill))
    before_competing_fill = engine.ledger.snapshot()
    repository.fail_event = "order_update"
    with pytest.raises(RuntimeError, match="simulated persistence failure"):
        engine.reconcile(NOW + dt.timedelta(minutes=4))
    assert engine.ledger.snapshot() == before_competing_fill == repository.load()

    repository.fail_event = None
    engine.reconcile(NOW + dt.timedelta(minutes=4))
    partial_fill = engine.ledger.snapshot().quarantined_fills[close.client_id]
    assert partial_fill.observed_filled_qty == first_close_fill
    assert partial_fill.applied_filled_qty == Decimal("2")
    assert partial_fill.unapplied_qty == Decimal("1")

    broker.fill(close.client_id, str(close.qty))
    engine.reconcile(NOW + dt.timedelta(minutes=4, seconds=30))

    snapshot = engine.ledger.snapshot()
    competing_fill = snapshot.quarantined_fills[close.client_id]
    assert snapshot.orders[reduction.client_id].filled_qty == Decimal("2")
    assert snapshot.orders[close.client_id].filled_qty == Decimal("4")
    assert competing_fill.observed_filled_qty == Decimal("4")
    assert competing_fill.applied_filled_qty == Decimal("2")
    assert competing_fill.unapplied_qty == Decimal("2")
    assert competing_fill.lot_id == lot_id
    assert competing_fill.incident_client_ids == (reduction.client_id,)
    assert snapshot.late_order_incidents[reduction.client_id].conflicting_order_ids == (
        close.client_id,
    )
    assert snapshot.lots[lot_id].remaining_qty == 0
    assert snapshot.entry_halted
    unresolved_inspection = RecoveryApplication(engine.ledger, broker).inspect_ownership()
    assert unresolved_inspection.account_activity_status == "unavailable"
    assert unresolved_inspection.account_activity_reason == "unresolved_order_incident"
    order_event = repository.events[-1].payload
    assert isinstance(
        order_event,
        (OrderUpdate, LateOrderIncidentOpened, LateOrderIncidentReopened),
    )
    assert order_event.late_order_incident_ids == (reduction.client_id,)

    event_count = len(repository.events)
    engine.reconcile(NOW + dt.timedelta(minutes=5))
    assert len(repository.events) == event_count
    blocked_at = NOW + dt.timedelta(minutes=5, seconds=1)
    blocked_entry = event("before-clear", timestamp=blocked_at)
    blocked_entry["instructions"][0]["symbol"] = "XYZ"
    blocked_entry["evidence"] = [
        make_instruction_evidence(instruction) for instruction in blocked_entry["instructions"]
    ]
    calls_before = broker.calls
    receive(engine, StockSignal.model_validate(blocked_entry), blocked_at)
    engine.process(blocked_at)
    assert engine.ledger.message("discord:demo:before-clear").parts == (Skipped(reason="halted"),)
    assert broker.calls == calls_before
    restarted = CopyEngine(repository, broker, CopyConfig(sources=["discord:demo"]))
    assert restarted.ledger.snapshot().quarantined_fills[close.client_id] == competing_fill
    conflicts = (
        restarted.ledger.snapshot().late_order_incidents[reduction.client_id].conflicting_order_ids
    )
    assert conflicts == (close.client_id,)

    broker.holdings["ABC"] = Decimal("-1")
    with pytest.raises(ValueError, match="positions do not exactly match"):
        RecoveryApplication(
            restarted.ledger,
            broker,
            clock=lambda: NOW + dt.timedelta(minutes=6),
        ).clear_late_order_incident(
            reduction.client_id,
            actor="operator@example.test",
            reason="Verify a mismatched position blocks clearance",
            matched_audit_ref="mismatched-close-audit",
            account_id="paper-demo",
        )
    assert restarted.ledger.snapshot().entry_halted

    broker.holdings["ABC"] = Decimal(0)
    RecoveryApplication(
        restarted.ledger,
        broker,
        clock=lambda: NOW + dt.timedelta(minutes=7),
    ).clear_late_order_incident(
        reduction.client_id,
        actor="operator@example.test",
        reason="Clear after all competing orders are terminal and positions match",
        matched_audit_ref="matched-close-audit",
        account_id="paper-demo",
    )
    cleared_restart = CopyEngine(repository, broker, CopyConfig(sources=["discord:demo"]))
    cleared_incident = cleared_restart.ledger.snapshot().late_order_incidents[reduction.client_id]
    assert cleared_incident.cleared
    assert cleared_incident.conflicting_order_ids == (close.client_id,)
    assert cleared_restart.ledger.snapshot().quarantined_fills[close.client_id] == competing_fill
    cleared_inspection = RecoveryApplication(cleared_restart.ledger, broker).inspect_ownership()
    assert cleared_inspection.account_activity_status == "ready"
    assert cleared_inspection.account_activity_reason is None
    ownership_incident = next(
        incident
        for incident in cleared_restart.ledger.snapshot().ownership_incidents.values()
        if not incident.resolved
    )
    RecoveryApplication(
        cleared_restart.ledger,
        broker,
        clock=lambda: NOW + dt.timedelta(minutes=8),
    ).resolve_ownership(
        OwnershipResolutionRequest(
            resolution_id="cleared-quarantine-ownership",
            incident_id=ownership_incident.incident_id,
            account_id="paper-demo",
            symbol="ABC",
            actor="operator",
            reason="matched zero share allocation",
            broker_qty=Decimal(0),
            external_qty=Decimal(0),
            lot_remaining={
                lot_id: lot.remaining_qty
                for lot_id, lot in cleared_restart.ledger.snapshot().lots.items()
                if lot.symbol == "ABC"
            },
        )
    )
    account_dir = tmp_path / "paper-demo"
    save_snapshot(account_dir, cleared_restart.ledger.snapshot())
    assert not has_unresolved_ownership(account_dir)

    after_clear = NOW + dt.timedelta(minutes=17)
    new_entry = event("after-clear", timestamp=after_clear)
    new_entry["instructions"][0]["symbol"] = "XYZ"
    new_entry["evidence"] = [
        make_instruction_evidence(instruction) for instruction in new_entry["instructions"]
    ]
    broker.auto_fill = True
    cleared_restart.bind(after_clear)
    receive(cleared_restart, StockSignal.model_validate(new_entry), after_clear)
    cleared_restart.process(after_clear)
    assert cleared_restart.ledger.owned("XYZ") > 0, cleared_restart.ledger.message(
        "discord:demo:after-clear"
    ).parts


def test_unknown_late_status_stays_unrecognized_then_recovers_without_losing_incident():
    engine, broker, _, uncertain = uncertain_system()
    engine.ledger.release_uncertain_intent(uncertain.client_id, release_evidence())
    broker.timeout_after_accept = False
    broker.orders[uncertain.client_id]["status"] = "future_vendor_state"

    engine.ledger.apply_order(
        uncertain.client_id,
        broker.lookup(uncertain.client_id),
        NOW + dt.timedelta(seconds=1),
    )
    assert engine.ledger.order(uncertain.client_id).status is OrderStatus.UNRECOGNIZED
    assert engine.ledger.order(uncertain.client_id).raw_broker_status == "future_vendor_state"
    assert engine.ledger.snapshot().late_order_incidents[uncertain.client_id].unresolved

    broker.orders[uncertain.client_id]["status"] = "new"
    engine.ledger.apply_order(
        uncertain.client_id,
        broker.lookup(uncertain.client_id),
        NOW + dt.timedelta(seconds=2),
    )
    assert engine.ledger.order(uncertain.client_id).status is OrderStatus.NEW
    assert engine.ledger.order(uncertain.client_id).raw_broker_status == "new"
    assert engine.ledger.snapshot().entry_halted


def test_late_incident_cannot_clear_while_the_order_is_pending():
    engine, broker, _, uncertain = uncertain_system()
    engine.ledger.release_uncertain_intent(uncertain.client_id, release_evidence())
    broker.timeout_after_accept = False
    engine.ledger.apply_order(
        uncertain.client_id,
        broker.lookup(uncertain.client_id),
        NOW + dt.timedelta(seconds=1),
    )

    with pytest.raises(ValueError, match="pending"):
        engine.ledger.clear_late_order_incident(uncertain.client_id, clearance_evidence())


def test_clearance_requires_matched_evidence_and_clears_only_after_terminal_order():
    engine, broker, repository, uncertain = uncertain_system()
    engine.ledger.release_uncertain_intent(uncertain.client_id, release_evidence())
    broker.timeout_after_accept = False
    broker.orders[uncertain.client_id]["status"] = "rejected"
    engine.ledger.apply_order(
        uncertain.client_id,
        broker.lookup(uncertain.client_id),
        NOW + dt.timedelta(seconds=1),
    )
    before = engine.ledger.snapshot()

    with pytest.raises(ValidationError, match=r"audit|quantities"):
        IncidentClearanceEvidence(
            actor="operator@example.test",
            reason="no matched evidence",
            checked_at=NOW + dt.timedelta(seconds=5),
            account_id="paper-demo",
        )
    with pytest.raises(ValueError, match="account"):
        engine.ledger.clear_late_order_incident(
            uncertain.client_id,
            clearance_evidence(account_id="other-account"),
        )
    assert engine.ledger.snapshot() == before

    engine.ledger.clear_late_order_incident(uncertain.client_id, clearance_evidence())
    snapshot = engine.ledger.snapshot()
    assert not snapshot.entry_halted
    assert not snapshot.late_order_incidents[uncertain.client_id].unresolved
    assert snapshot.late_order_incidents[uncertain.client_id].clearance_history == (
        clearance_evidence(),
    )
    assert repository.events[-1].payload.kind == "late_order_incident_cleared"


def test_release_commit_failure_leaves_uncertain_state_and_evidence_unpublished():
    engine, _, repository, uncertain = uncertain_system()
    before = engine.ledger.snapshot()
    repository.fail_event = "order_intent_released"

    with pytest.raises(RuntimeError, match="persistence"):
        engine.ledger.release_uncertain_intent(uncertain.client_id, release_evidence())

    assert engine.ledger.snapshot() == before == repository.load()


def test_multiple_late_order_incidents_remain_addressable_by_client_id():
    engine, broker, _, first = uncertain_system()
    first_observation = dict(broker.orders[first.client_id])
    engine.ledger.release_uncertain_intent(first.client_id, release_evidence())
    broker.orders.pop(first.client_id)

    broker.timeout_after_accept = True
    second_signal = event(
        id="second",
        price="26",
        timestamp=NOW + dt.timedelta(seconds=2),
    )
    receive(engine, StockSignal.model_validate(second_signal), NOW + dt.timedelta(seconds=2))
    engine.process(NOW + dt.timedelta(seconds=2))
    second = next(order for order in engine.ledger.orders() if order.client_id != first.client_id)
    second_observation = dict(broker.orders[second.client_id])
    engine.ledger.release_uncertain_intent(
        second.client_id,
        release_evidence(checked_at=NOW + dt.timedelta(seconds=3)),
    )
    broker.orders.pop(second.client_id)

    first_observation["status"] = "new"
    second_observation["status"] = "new"
    broker.orders[first.client_id] = first_observation
    broker.orders[second.client_id] = second_observation
    engine.ledger.apply_order(
        first.client_id,
        broker.lookup(first.client_id),
        NOW + dt.timedelta(seconds=4),
    )
    engine.ledger.apply_order(
        second.client_id,
        broker.lookup(second.client_id),
        NOW + dt.timedelta(seconds=5),
    )

    incidents = engine.ledger.snapshot().late_order_incidents
    assert set(incidents) == {first.client_id, second.client_id}
    assert engine.ledger.snapshot().entry_halted


def test_clearance_evidence_accepts_equal_matched_position_quantities():
    evidence = IncidentClearanceEvidence(
        actor="operator@example.test",
        reason="broker and ledger position quantities match",
        checked_at=NOW,
        account_id="paper-demo",
        symbol="ABC",
        expected_qty=Decimal("4"),
        broker_qty=Decimal("4"),
    )
    assert evidence.expected_qty == evidence.broker_qty

    with pytest.raises(ValidationError, match="equal"):
        IncidentClearanceEvidence(
            actor="operator@example.test",
            reason="position quantities do not match",
            checked_at=NOW,
            account_id="paper-demo",
            symbol="ABC",
            expected_qty=Decimal("4"),
            broker_qty=Decimal("3"),
        )


def test_clearance_commit_failure_keeps_the_entry_halt_and_prior_incident_state():
    engine, broker, repository, uncertain = uncertain_system()
    engine.ledger.release_uncertain_intent(uncertain.client_id, release_evidence())
    broker.timeout_after_accept = False
    broker.orders[uncertain.client_id]["status"] = "rejected"
    engine.ledger.apply_order(
        uncertain.client_id,
        broker.lookup(uncertain.client_id),
        NOW + dt.timedelta(seconds=2),
    )
    before = engine.ledger.snapshot()
    repository.fail_event = "late_order_incident_cleared"

    with pytest.raises(RuntimeError, match="persistence"):
        engine.ledger.clear_late_order_incident(uncertain.client_id, clearance_evidence())

    assert engine.ledger.snapshot() == before == repository.load()
    assert engine.ledger.snapshot().entry_halted


def test_unchanged_late_order_snapshot_after_clearance_does_not_reopen_incident():
    engine, broker, _, uncertain = uncertain_system()
    engine.ledger.release_uncertain_intent(uncertain.client_id, release_evidence())
    broker.timeout_after_accept = False
    broker.orders[uncertain.client_id]["status"] = "rejected"
    observation = broker.lookup(uncertain.client_id)
    engine.ledger.apply_order(
        uncertain.client_id,
        observation,
        NOW + dt.timedelta(seconds=1),
    )
    engine.ledger.clear_late_order_incident(uncertain.client_id, clearance_evidence())
    before = engine.ledger.snapshot()

    engine.ledger.apply_order(
        uncertain.client_id,
        broker.lookup(uncertain.client_id),
        NOW + dt.timedelta(seconds=6),
    )

    after = engine.ledger.snapshot()
    incident = after.late_order_incidents[uncertain.client_id]
    assert after == before
    assert not incident.unresolved
    assert incident.clearance_history == (clearance_evidence(),)


def test_new_fill_after_clearance_reopens_incident_without_erasing_clearance_evidence():
    engine, broker, _, uncertain = uncertain_system()
    engine.ledger.release_uncertain_intent(uncertain.client_id, release_evidence())
    broker.timeout_after_accept = False
    broker.orders[uncertain.client_id]["status"] = "canceled"
    engine.ledger.apply_order(
        uncertain.client_id,
        broker.lookup(uncertain.client_id),
        NOW + dt.timedelta(seconds=1),
    )
    clearance = clearance_evidence()
    engine.ledger.clear_late_order_incident(uncertain.client_id, clearance)

    order_data = broker.orders[uncertain.client_id]
    order_data["filled_qty"] = str(uncertain.qty / 2)
    order_data["filled_avg_price"] = order_data["limit_price"]
    engine.ledger.apply_order(
        uncertain.client_id,
        broker.lookup(uncertain.client_id),
        NOW + dt.timedelta(seconds=6),
    )

    incident = engine.ledger.snapshot().late_order_incidents[uncertain.client_id]
    assert incident.unresolved
    assert incident.clearance_history == (clearance,)
    assert incident.latest_filled_qty == uncertain.qty / 2
    assert engine.ledger.snapshot().entry_halted


def test_late_observation_commit_failure_does_not_publish_order_fill_or_incident():
    engine, broker, repository, uncertain = uncertain_system()
    engine.ledger.release_uncertain_intent(uncertain.client_id, release_evidence())
    broker.timeout_after_accept = False
    broker.fill(uncertain.client_id, str(uncertain.qty / 2))
    before = engine.ledger.snapshot()
    repository.fail_event = "late_order_incident_opened"

    with pytest.raises(RuntimeError, match="persistence"):
        engine.ledger.apply_order(
            uncertain.client_id,
            broker.lookup(uncertain.client_id),
            NOW + dt.timedelta(seconds=1),
        )

    assert engine.ledger.snapshot() == before == repository.load()
    assert engine.ledger.owned("ABC") == Decimal(0)
    assert engine.ledger.snapshot().late_order_incidents == {}


def test_terminal_late_order_unknown_status_and_fill_commit_atomically_and_reload():
    engine, broker, repository, uncertain = uncertain_system()
    engine.ledger.release_uncertain_intent(uncertain.client_id, release_evidence())
    broker.timeout_after_accept = False
    broker.orders[uncertain.client_id]["status"] = "canceled"
    engine.ledger.apply_order(
        uncertain.client_id,
        broker.lookup(uncertain.client_id),
        NOW + dt.timedelta(seconds=2),
    )
    clearance = clearance_evidence()
    engine.ledger.clear_late_order_incident(uncertain.client_id, clearance)

    late = broker.orders[uncertain.client_id]
    late.update(
        status="future_vendor_state",
        filled_qty="2",
        filled_avg_price=late["limit_price"],
    )
    engine.ledger.apply_order(
        uncertain.client_id,
        broker.lookup(uncertain.client_id),
        NOW + dt.timedelta(seconds=6),
    )

    snapshot = repository.load()
    incident = snapshot.late_order_incidents[uncertain.client_id]
    assert snapshot.orders[uncertain.client_id].status is OrderStatus.UNRECOGNIZED
    assert snapshot.orders[uncertain.client_id].raw_broker_status == "future_vendor_state"
    assert snapshot.orders[uncertain.client_id].filled_qty == Decimal("2")
    assert snapshot.lots[uncertain.client_id].remaining_qty == Decimal("2")
    assert incident.unresolved
    assert incident.clearance_history == (clearance,)
    assert incident.latest_filled_qty == Decimal("2")
    assert snapshot.entry_halted
    assert repository.events[-1].payload.kind == "late_order_incident_reopened"

    resumed = CopyEngine(repository, broker, CopyConfig(sources=["discord:demo"]))
    assert resumed.ledger.snapshot() == snapshot
    assert resumed.ledger.owned("ABC") == Decimal("2")


def test_snapshot_rejects_released_broker_activity_without_late_incident():
    engine, broker, _, uncertain = uncertain_system()
    engine.ledger.release_uncertain_intent(uncertain.client_id, release_evidence())
    broker.timeout_after_accept = False
    engine.ledger.apply_order(
        uncertain.client_id,
        broker.lookup(uncertain.client_id),
        NOW + dt.timedelta(seconds=2),
    )
    snapshot = engine.ledger.snapshot()
    assert snapshot.entry_halted

    malformed = snapshot.model_copy(update={"late_order_incidents": {}})
    assert not malformed.entry_halted
    with pytest.raises(ValidationError, match="incident"):
        LedgerSnapshot.model_validate(malformed.model_dump())


def test_clearance_quantities_must_match_actual_owned_quantity():
    engine, broker, repository, uncertain = uncertain_system()
    engine.ledger.release_uncertain_intent(uncertain.client_id, release_evidence())
    broker.timeout_after_accept = False
    broker.fill(uncertain.client_id, str(uncertain.qty))
    engine.ledger.apply_order(
        uncertain.client_id,
        broker.lookup(uncertain.client_id),
        NOW + dt.timedelta(seconds=2),
    )
    assert engine.ledger.owned("ABC") == Decimal("4")
    before = engine.ledger.snapshot()
    false_clearance = IncidentClearanceEvidence(
        actor="operator@example.test",
        reason="incorrect zero-share position audit",
        checked_at=NOW + dt.timedelta(seconds=5),
        account_id="paper-demo",
        matched_audit_ref="audit-incorrect-zero",
        symbol="ABC",
        expected_qty=Decimal(0),
        broker_qty=Decimal(0),
    )

    with pytest.raises(ValueError, match="ledger quantity"):
        engine.ledger.clear_late_order_incident(uncertain.client_id, false_clearance)

    assert engine.ledger.snapshot() == before == repository.load()
    assert engine.ledger.snapshot().entry_halted


@pytest.mark.parametrize("association_state", ["missing", "empty"])
def test_snapshot_v3_rejects_missing_or_empty_quarantine_incident_associations(
    association_state,
):
    from pydantic import ValidationError

    engine, broker, _, late_order, broker_record = late_sell_with_consumed_source_lot()
    broker_record["status"] = "new"
    broker.orders[late_order.client_id] = broker_record
    broker.fill(late_order.client_id, str(late_order.qty))
    engine.reconcile(NOW + dt.timedelta(minutes=4))

    snapshot = engine.ledger.snapshot()
    serialized = snapshot.model_dump(mode="json")
    quarantine = serialized["quarantined_fills"][late_order.client_id]
    assert quarantine["incident_client_ids"]
    if association_state == "missing":
        quarantine.pop("incident_client_ids")
    else:
        quarantine["incident_client_ids"] = []

    with pytest.raises(ValidationError):
        type(snapshot).model_validate(serialized)
