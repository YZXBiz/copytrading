"""Execution notifications tell the truth about fills, rejections, and unknown outcomes."""

import datetime as dt
from decimal import Decimal

from copytrading_engine.execution.application.engine import CopyEngine
from copytrading_engine.execution.domain.order_lifecycle import OrderStatus
from copytrading_engine.execution.domain.recovery import IncidentClearanceEvidence, ReleaseEvidence
from copytrading_engine.execution.domain.signals import CopyConfig
from copytrading_engine.execution.presentation.notifications import execution_notification
from copytrading_engine.shared.signals import StockSignal

from .builders import NOW, event, receive
from .fakes import FakeBroker, MemoryRepository


class ObservedRepository(MemoryRepository):
    def __init__(self):
        super().__init__()
        self.notices = []

    def save(self, snapshot, event):
        super().save(snapshot, event)
        notice = execution_notification(snapshot, event)
        if notice:
            self.notices.append(notice)


def system():
    repository = ObservedRepository()
    broker = FakeBroker()
    broker.auto_fill = False
    engine = CopyEngine(repository, broker, CopyConfig(sources=["discord:demo"]))
    engine.bind(NOW)
    receive(engine, StockSignal.model_validate(event()), NOW)
    return repository, broker, engine


def test_accepted_partial_and_final_fill_are_distinct_and_priced():
    repository, broker, engine = system()
    engine.process(NOW)
    accepted = repository.notices[-1].payload.annotations
    assert "order accepted" in accepted["summary"]
    assert "Filled: 0" in accepted["evidence"]
    assert "Average fill" not in accepted["evidence"]
    order = engine.ledger.orders()[0]
    broker.fill(order.client_id, "1")
    engine.reconcile(NOW)
    partial = repository.notices[-1]
    assert "partially filled" in partial.payload.annotations["summary"]
    assert "Average fill:" in partial.payload.annotations["evidence"]
    broker.fill(order.client_id, str(order.qty))
    engine.reconcile(NOW)
    final = repository.notices[-1]
    assert final.key != partial.key
    assert "Filled value:" in final.payload.annotations["evidence"]
    assert "partially" not in final.payload.annotations["summary"]
    count = len(repository.notices)
    engine.reconcile(NOW)
    assert len(repository.notices) == count


def test_risk_rejection_notifies_without_submitting():
    repository, broker, engine = system()
    broker.account_data["cash"] = "0"
    engine.process(NOW)
    assert broker.calls == 0
    assert "trade skipped" in repository.notices[-1].payload.annotations["summary"]
    assert "Insufficient cash" in repository.notices[-1].payload.annotations["evidence"]


def test_exposure_rejection_names_both_limits_and_saved_amounts():
    repository, broker, engine = system()
    broker.auto_fill = True
    engine.process(NOW)
    engine.config = CopyConfig(
        sources=["discord:demo"],
        max_symbol_usd=Decimal(150),
        max_total_usd=Decimal(150),
    )
    later = NOW + dt.timedelta(minutes=11)
    receive(engine, StockSignal.model_validate(event(id="second", timestamp=later)), later)
    engine.process(later)
    notice = repository.notices[-1].payload.annotations
    assert "Symbol and total exposure limits" in notice["evidence"]
    assert "Symbol cost exposure $100 + proposed budget $100 > $150 limit" in notice["evidence"]
    assert "Total cost exposure $100 + proposed budget $100 > $150 limit" in notice["evidence"]
    assert broker.calls == 1


def test_unknown_submission_and_cancel_request_never_claim_completion():
    repository, broker, engine = system()
    broker.timeout_after_accept = True
    engine.process(NOW)
    assert "uncertain" in repository.notices[-1].payload.annotations["summary"]
    assert "Do not submit a duplicate" in repository.notices[-1].payload.annotations["evidence"]
    engine.reconcile(NOW)
    order = engine.ledger.orders()[0]
    engine.cancel(order, NOW)
    notice = repository.notices[-1]
    cancel_key = notice.key
    assert "cancellation requested" in notice.payload.annotations["summary"]
    assert "not yet confirmed" in notice.payload.annotations["evidence"]
    engine.cancel(order, NOW)
    assert repository.notices[-1].key == cancel_key
    engine.reconcile(NOW)
    assert "canceled" in repository.notices[-1].payload.annotations["summary"]


def test_unknown_status_notification_explains_quarantine_and_reservation():
    repository, broker, engine = system()
    broker.auto_fill = False
    engine.process(NOW)
    order = engine.ledger.orders()[0]
    broker.orders[order.client_id]["status"] = "awaiting_internal_routing"

    engine.reconcile(NOW + dt.timedelta(seconds=1))

    notice = repository.notices[-1]
    key = notice.key
    assert engine.ledger.order(order.client_id).status is OrderStatus.UNRECOGNIZED
    assert notice.payload.labels["notification_id"] == key
    assert notice.payload.labels["signal_id"] == order.message_id
    assert notice.payload.labels["severity"] == "warning"
    assert "quarantined" in notice.payload.annotations["summary"]
    assert "awaiting_internal_routing" in notice.payload.annotations["evidence"]
    assert "reserved" in notice.payload.annotations["evidence"]


def test_release_late_incident_and_clear_notifications_keep_stable_trace_ids():
    repository, broker, engine = system()
    broker.timeout_after_accept = True
    engine.process(NOW)
    order = engine.ledger.orders()[0]
    observed_order = dict(broker.orders.pop(order.client_id))

    engine.ledger.release_uncertain_intent(
        order.client_id,
        ReleaseEvidence(
            actor="operator@example.test",
            reason="Broker history confirms no accepted order or fills",
            order_history_ref="order-history-1",
            fill_history_ref="fill-history-1",
            checked_at=NOW + dt.timedelta(seconds=1),
            account_id="paper-demo",
        ),
    )
    release_notice = repository.notices[-1]
    release_key = release_notice.key
    assert release_notice.payload.labels["notification_id"] == release_key
    assert release_notice.payload.labels["signal_id"] == order.message_id
    assert "released" in release_notice.payload.annotations["summary"]

    observed_order["status"] = "rejected"
    broker.orders[order.client_id] = observed_order
    engine.reconcile(NOW + dt.timedelta(seconds=2))
    incident_notice = repository.notices[-1]
    incident_key = incident_notice.key
    assert incident_notice.payload.labels["notification_id"] == incident_key
    assert incident_notice.payload.labels["signal_id"] == order.message_id
    assert incident_notice.payload.labels["severity"] == "critical"
    assert "late broker order" in incident_notice.payload.annotations["summary"].lower()
    assert "new buys" in incident_notice.payload.annotations["evidence"].lower()

    engine.ledger.clear_late_order_incident(
        order.client_id,
        IncidentClearanceEvidence(
            actor="operator@example.test",
            reason="Fresh matched position audit",
            checked_at=NOW + dt.timedelta(seconds=3),
            account_id="paper-demo",
            matched_audit_ref="audit-1",
            symbol="ABC",
            expected_qty=Decimal(0),
            broker_qty=Decimal(0),
        ),
    )
    clear_notice = repository.notices[-1]
    clear_key = clear_notice.key
    assert clear_notice.payload.labels["notification_id"] == clear_key
    assert clear_notice.payload.labels["signal_id"] == order.message_id
    assert "cleared" in clear_notice.payload.annotations["summary"].lower()


def test_incident_notification_replay_is_stable_and_reopen_has_new_identity():
    repository, broker, engine = system()
    broker.timeout_after_accept = True
    engine.process(NOW)
    order = engine.ledger.orders()[0]
    observed_order = dict(broker.orders.pop(order.client_id))
    engine.ledger.release_uncertain_intent(
        order.client_id,
        ReleaseEvidence(
            actor="operator@example.test",
            reason="Broker history confirms no accepted order or fills",
            order_history_ref="order-history-1",
            fill_history_ref="fill-history-1",
            checked_at=NOW + dt.timedelta(seconds=1),
            account_id="paper-demo",
        ),
    )
    observed_order["status"] = "rejected"
    broker.orders[order.client_id] = observed_order
    engine.reconcile(NOW + dt.timedelta(seconds=2))
    opened_event = repository.events[-1]
    opened_snapshot = repository.load()
    first_open = execution_notification(opened_snapshot, opened_event)
    replayed_open = execution_notification(opened_snapshot, opened_event)
    assert first_open == replayed_open
    assert first_open is not None
    opened_key = first_open.key

    engine.ledger.clear_late_order_incident(
        order.client_id,
        IncidentClearanceEvidence(
            actor="operator@example.test",
            reason="Fresh matched position audit",
            checked_at=NOW + dt.timedelta(seconds=3),
            account_id="paper-demo",
            matched_audit_ref="audit-1",
            symbol="ABC",
            expected_qty=Decimal(0),
            broker_qty=Decimal(0),
        ),
    )
    broker.orders[order.client_id].update(
        status="rejected",
        filled_qty="1",
        filled_avg_price=str(order.limit_price),
    )
    broker.holdings[order.symbol] = Decimal(1)
    engine.reconcile(NOW + dt.timedelta(seconds=4))

    reopened_event = repository.events[-1]
    assert reopened_event.payload.kind == "late_order_incident_reopened"
    reopened = execution_notification(repository.load(), reopened_event)
    assert reopened is not None
    assert reopened.key != opened_key
    assert repository.notices[-1].key == reopened.key


def test_sell_notifications_show_the_limit_and_actual_fill():
    repository, broker, engine = system()
    broker.auto_fill = True
    engine.process(NOW)
    broker.auto_fill = False
    receive(engine, StockSignal.model_validate(event("exit", "reduce", "24", "25")), NOW)
    engine.process(NOW)
    accepted = repository.notices[-1].payload.annotations
    assert "Limit: $23.76." in accepted["evidence"]
    assert "Market order." not in accepted["evidence"]
    order = engine.ledger.orders()[-1]
    broker.fill(order.client_id, str(order.qty))
    engine.reconcile(NOW)
    filled = repository.notices[-1].payload.annotations
    assert "Average fill: $23.76" in filled["evidence"]
    assert "Limit: $23.76." in filled["evidence"]


def test_exit_outside_regular_hours_reports_its_limit_order():
    import datetime as dt

    repository, broker, engine = system()
    broker.auto_fill = True
    engine.process(NOW)
    now = dt.datetime.fromisoformat("2026-01-06T18:00:00-05:00")
    receive(
        engine, StockSignal.model_validate(event("exit", "close", "27", "25", timestamp=now)), now
    )
    engine.process(now)
    evidence = " ".join(notice.payload.annotations["evidence"] for notice in repository.notices)
    assert "Limit" in evidence
    assert all(notice.payload.labels["severity"] != "warning" for notice in repository.notices)
