"""Offline operator recovery must verify broker state before ledger writes."""

import datetime as dt
import re
from decimal import Decimal

import pytest

from copytrading_engine.execution.application.engine import CopyEngine
from copytrading_engine.execution.application.ports import BrokerError
from copytrading_engine.execution.domain.market import BrokerOrder
from copytrading_engine.execution.domain.order_lifecycle import OrderStatus
from copytrading_engine.execution.domain.progress import OrderLinked
from copytrading_engine.execution.domain.recovery import ManualSale
from copytrading_engine.execution.domain.signals import CopyConfig
from copytrading_engine.shared.signals import StockSignal

from .builders import NOW, event, receive
from .fakes import FakeBroker, MemoryRepository

ACTOR = "operator@example.test"
REASON = "verified broker order and account history"


def _uncertain_system():
    repository = MemoryRepository()
    broker = FakeBroker()
    broker.auto_fill = False
    broker.timeout_after_accept = True
    engine = CopyEngine(repository, broker, CopyConfig(sources=["discord:demo"]))
    engine.bind(NOW)
    receive(engine, StockSignal.model_validate(event()), NOW)
    engine.process(NOW)
    order = engine.ledger.orders()[0]
    assert order.status is OrderStatus.UNCERTAIN
    return engine, broker, repository, order


def _release(app, client_id):
    return app.release_uncertain_intent(
        client_id,
        actor=ACTOR,
        reason=REASON,
        order_history_ref="order-history-ticket-12",
        fill_history_ref="fill-history-ticket-12",
        account_id="paper-demo",
    )


def _manual_sale_system():
    repository = MemoryRepository()
    broker = FakeBroker()
    engine = CopyEngine(repository, broker, CopyConfig(sources=["discord:demo"]))
    engine.bind(NOW)
    receive(engine, StockSignal.model_validate(event()), NOW)
    engine.process(NOW)
    owned_before = engine.ledger.owned("ABC")
    sold = owned_before / 2
    order = BrokerOrder(
        id="manual-broker-order",
        client_order_id="manual-client-order",
        symbol="ABC",
        side="sell",
        qty=sold,
        filled_qty=sold,
        filled_avg_price=Decimal("26.25"),
        status="filled",
    )
    broker.orders[order.client_order_id] = order.model_dump(mode="json")
    broker.holdings["ABC"] = owned_before - sold
    sale = ManualSale(
        lot_id=engine.ledger.orders()[0].client_id,
        order=order,
        filled_at=NOW + dt.timedelta(seconds=1),
        recorded_at=NOW + dt.timedelta(seconds=2),
        reason="verified external sale in account activity",
    )
    return engine, broker, repository, sale


def test_release_records_attestation_only_after_absence_and_exact_position_checks():
    from copytrading_engine.execution.application.recovery import RecoveryApplication

    engine, broker, repository, uncertain = _uncertain_system()
    broker.orders.clear()
    checked_at = NOW + dt.timedelta(seconds=10)
    app = RecoveryApplication(engine.ledger, broker, clock=lambda: checked_at)

    evidence = _release(app, uncertain.client_id)

    assert engine.ledger.order(uncertain.client_id).status is OrderStatus.RELEASED_UNSUBMITTED
    assert engine.ledger.snapshot().release_evidence[uncertain.client_id] == evidence
    assert evidence.actor == ACTOR
    assert evidence.reason == REASON
    assert evidence.order_history_ref == "order-history-ticket-12"
    assert evidence.fill_history_ref == "fill-history-ticket-12"
    assert evidence.checked_at == checked_at
    assert repository.events[-1].payload.kind == "order_intent_released"
    assert broker.calls == 1  # The only call so far was the original uncertain submission.


def test_never_submitted_uncertain_intent_can_be_audited_and_released_after_restart():
    from copytrading_engine.execution.application.recovery import RecoveryApplication

    repository = MemoryRepository()
    broker = FakeBroker()
    engine = CopyEngine(repository, broker, CopyConfig(sources=["discord:demo"]))
    engine.bind(NOW)
    receive(engine, StockSignal.model_validate(event("pre-post-commit-failure")), NOW)
    repository.fail_event = "submit_started"

    with pytest.raises(RuntimeError, match="simulated persistence failure"):
        engine.process(NOW)

    prepared = engine.ledger.orders()[0]
    assert prepared.status is OrderStatus.PREPARED
    assert prepared.submit_started_at is None
    assert repository.load().orders[prepared.client_id].status is OrderStatus.PREPARED
    assert broker.calls == 0

    repository.fail_event = None
    restarted = CopyEngine(repository, broker, CopyConfig(sources=["discord:demo"]))
    restarted.reconcile(NOW + dt.timedelta(seconds=1))
    uncertain = restarted.ledger.order(prepared.client_id)
    assert uncertain.status is OrderStatus.UNCERTAIN
    assert uncertain.submit_started_at is None
    assert broker.calls == 0
    restarted.process(NOW + dt.timedelta(seconds=2))
    assert restarted.ledger.order(prepared.client_id).status is OrderStatus.UNCERTAIN
    assert broker.calls == 0

    app = RecoveryApplication(
        restarted.ledger,
        broker,
        clock=lambda: NOW + dt.timedelta(seconds=2),
    )
    evidence = _release(app, uncertain.client_id)

    assert evidence.submission_state == "not_started"
    assert restarted.ledger.order(uncertain.client_id).status is OrderStatus.RELEASED_UNSUBMITTED
    assert restarted.ledger.message("discord:demo:pre-post-commit-failure").parts == (
        OrderLinked(client_id=uncertain.client_id),
    )
    assert repository.events[-1].payload.kind == "order_intent_released"
    assert repository.events[-1].payload.evidence.submission_state == "not_started"
    assert broker.calls == 0

    restarted.process(NOW + dt.timedelta(seconds=3))
    assert restarted.ledger.message("discord:demo:pre-post-commit-failure").status == "done"
    assert broker.calls == 0

    loaded_again = CopyEngine(repository, broker, CopyConfig(sources=["discord:demo"]))
    assert (
        loaded_again.ledger.snapshot().release_evidence[uncertain.client_id].submission_state
        == "not_started"
    )


def test_release_rejects_blank_operator_attestation_without_releasing_intent():
    from copytrading_engine.execution.application.recovery import RecoveryApplication

    engine, broker, repository, uncertain = _uncertain_system()
    broker.orders.clear()
    before = engine.ledger.snapshot()
    app = RecoveryApplication(
        engine.ledger,
        broker,
        clock=lambda: NOW + dt.timedelta(seconds=10),
    )

    with pytest.raises(ValueError, match="attestation"):
        app.release_uncertain_intent(
            uncertain.client_id,
            actor=" ",
            reason=REASON,
            order_history_ref="order-history-ticket-12",
            fill_history_ref="fill-history-ticket-12",
            account_id="paper-demo",
        )

    assert engine.ledger.snapshot() == before == repository.load()


@pytest.mark.parametrize("observation", ["lookup", "open_order", "position", "account"])
def test_release_fails_closed_when_broker_evidence_is_not_unambiguous(observation):
    from copytrading_engine.execution.application.recovery import RecoveryApplication

    engine, broker, repository, uncertain = _uncertain_system()
    app = RecoveryApplication(
        engine.ledger,
        broker,
        clock=lambda: NOW + dt.timedelta(seconds=10),
    )
    before = engine.ledger.snapshot()
    if observation == "lookup":
        broker.orders[uncertain.client_id]["status"] = "canceled"
    elif observation == "open_order":
        broker.orders["other-client-id"] = {
            **broker.orders[uncertain.client_id],
            "client_order_id": uncertain.client_id,
        }
        broker.orders.pop(uncertain.client_id)
    elif observation == "position":
        # The order is gone at the broker, so release reaches the position check.
        broker.orders.pop(uncertain.client_id)
        broker.holdings[uncertain.symbol] = Decimal("1")
    else:
        broker.account_data["id"] = "different-paper-account"
    expected = {
        "lookup": "Broker lookup found the uncertain order; reconcile it first",
        "open_order": "A matching broker order is still open",
        "position": "Broker position does not exactly match the saved ledger position",
        "account": "Supplied, broker, and ledger account identities must match",
    }

    with pytest.raises(ValueError, match=re.escape(expected[observation])):
        _release(app, uncertain.client_id)

    assert engine.ledger.snapshot() == before == repository.load()


def test_manual_sale_checks_observed_fill_and_resulting_positions_before_ledger_import():
    from copytrading_engine.execution.application.recovery import RecoveryApplication

    engine, broker, repository, sale = _manual_sale_system()
    owned_before = engine.ledger.owned("ABC")
    manual_order = sale.order
    sold = sale.order.filled_qty

    RecoveryApplication(engine.ledger, broker).record_manual_sale(sale, account_id="paper-demo")

    assert engine.ledger.owned("ABC") == owned_before - sold
    assert engine.ledger.snapshot().manual_sales[manual_order.id] == sale
    assert repository.events[-1].payload.kind == "manual_sale_recorded"
    assert broker.calls == 1
    event_count = len(repository.events)

    RecoveryApplication(engine.ledger, broker).record_manual_sale(
        sale.model_copy(update={"recorded_at": NOW + dt.timedelta(seconds=3)}),
        account_id="paper-demo",
    )

    assert len(repository.events) == event_count


@pytest.mark.parametrize("problem", ["fill", "pending", "position", "account"])
def test_manual_sale_does_not_import_when_account_evidence_is_uncertain(problem):
    from copytrading_engine.execution.application.recovery import RecoveryApplication

    engine, broker, repository, sale = _manual_sale_system()
    manual_order = sale.order
    if problem == "fill":
        broker.orders[manual_order.client_order_id]["filled_avg_price"] = "27.00"
    elif problem == "pending":
        broker.orders["pending-copy"] = {
            "id": "pending-broker-order",
            "client_order_id": "pending-copy",
            "symbol": "ABC",
            "side": "buy",
            "qty": "1",
            "filled_qty": "0",
            "filled_avg_price": None,
            "status": "new",
        }
    elif problem == "position":
        broker.holdings["ABC"] -= Decimal("1")
    else:
        broker.account_data["id"] = "different-paper-account"
    before = engine.ledger.snapshot()
    expected = {
        "fill": "Provided manual sale does not match the broker order record",
        "pending": "Broker has open orders; verify the account before recording a sale",
        "position": "Resulting broker positions do not match the projected ledger",
        "account": "Supplied, broker, and ledger account identities must match",
    }

    with pytest.raises(ValueError, match=re.escape(expected[problem])):
        RecoveryApplication(engine.ledger, broker).record_manual_sale(sale, account_id="paper-demo")

    assert engine.ledger.snapshot() == before == repository.load()


def test_clearance_refreshes_late_order_through_ledger_then_requires_exact_position_match():
    from copytrading_engine.execution.application.recovery import RecoveryApplication

    engine, broker, repository, uncertain = _uncertain_system()
    broker.orders.clear()
    app = RecoveryApplication(engine.ledger, broker, clock=lambda: NOW + dt.timedelta(seconds=2))
    _release(app, uncertain.client_id)
    broker.orders[uncertain.client_id] = {
        "id": "late-order-id",
        "client_order_id": uncertain.client_id,
        "symbol": uncertain.symbol,
        "side": uncertain.side,
        "qty": str(uncertain.qty),
        "filled_qty": str(uncertain.qty),
        "filled_avg_price": str(uncertain.limit_price),
        "status": "filled",
    }
    broker.holdings[uncertain.symbol] = uncertain.qty
    checked_at = NOW + dt.timedelta(seconds=20)
    app = RecoveryApplication(engine.ledger, broker, clock=lambda: checked_at)

    evidence = app.clear_late_order_incident(
        uncertain.client_id,
        actor=ACTOR,
        reason="late order is terminal and positions match",
        matched_audit_ref="position-audit-ticket-41",
        account_id="paper-demo",
    )

    snapshot = engine.ledger.snapshot()
    assert snapshot.orders[uncertain.client_id].status is OrderStatus.FILLED
    assert snapshot.late_order_incidents[uncertain.client_id].cleared
    assert not snapshot.entry_halted
    assert evidence.symbol == uncertain.symbol
    assert evidence.expected_qty == evidence.broker_qty == uncertain.qty
    assert evidence.matched_audit_ref == "position-audit-ticket-41"
    assert repository.events[-2].payload.kind == "late_order_incident_opened"
    assert repository.events[-1].payload.kind == "late_order_incident_cleared"
    assert broker.calls == 1


@pytest.mark.parametrize("problem", ["pending", "missing", "position"])
def test_clearance_keeps_incident_halted_when_refresh_or_position_audit_is_not_clear(problem):
    from copytrading_engine.execution.application.recovery import RecoveryApplication

    engine, broker, repository, uncertain = _uncertain_system()
    broker.orders.clear()
    app = RecoveryApplication(engine.ledger, broker, clock=lambda: NOW + dt.timedelta(seconds=2))
    _release(app, uncertain.client_id)
    order_data = {
        "id": "late-order-id",
        "client_order_id": uncertain.client_id,
        "symbol": uncertain.symbol,
        "side": uncertain.side,
        "qty": str(uncertain.qty),
        "filled_qty": "0",
        "filled_avg_price": None,
        "status": "new",
    }
    if problem == "missing":
        broker.orders.clear()
    else:
        broker.orders[uncertain.client_id] = order_data
        if problem == "pending":
            broker.holdings[uncertain.symbol] = Decimal("0")
        else:
            order_data.update(
                filled_qty=str(uncertain.qty),
                filled_avg_price=str(uncertain.limit_price),
                status="filled",
            )
            broker.holdings[uncertain.symbol] = Decimal("0")
    before = engine.ledger.snapshot()
    app = RecoveryApplication(engine.ledger, broker, clock=lambda: NOW + dt.timedelta(seconds=20))
    expected = {
        "missing": "Broker lookup could not confirm the late order",
        "pending": "The refreshed late order is not in a terminal state",
        "position": "Fresh broker positions do not exactly match ledger-owned positions",
    }

    with pytest.raises(ValueError, match=expected[problem]):
        app.clear_late_order_incident(
            uncertain.client_id,
            actor=ACTOR,
            reason=REASON,
            matched_audit_ref="position-audit-ticket-41",
            account_id="paper-demo",
        )

    assert engine.ledger.snapshot().entry_halted is (problem != "missing")
    if problem == "missing":
        assert engine.ledger.snapshot() == before == repository.load()
    else:
        assert repository.events[-1].payload.kind == "late_order_incident_opened"
        assert engine.ledger.snapshot().late_order_incidents[uncertain.client_id].unresolved


@pytest.mark.parametrize("operation", ["account", "lookup", "open_orders", "positions"])
def test_release_does_not_commit_when_any_required_broker_read_fails(operation):
    from copytrading_engine.execution.application.recovery import RecoveryApplication

    engine, broker, repository, uncertain = _uncertain_system()
    broker.orders.clear()
    before = engine.ledger.snapshot()

    def unavailable(*_args, **_kwargs):
        raise BrokerError()

    setattr(broker, operation, unavailable)
    app = RecoveryApplication(engine.ledger, broker, clock=lambda: NOW + dt.timedelta(seconds=10))

    with pytest.raises(BrokerError):
        _release(app, uncertain.client_id)

    assert engine.ledger.snapshot() == before == repository.load()


@pytest.mark.parametrize("operation", ["account", "lookup", "open_orders", "positions"])
def test_manual_sale_does_not_commit_when_any_required_broker_read_fails(operation):
    from copytrading_engine.execution.application.recovery import RecoveryApplication

    engine, broker, repository, sale = _manual_sale_system()
    before = engine.ledger.snapshot()

    def unavailable(*_args, **_kwargs):
        raise BrokerError()

    setattr(broker, operation, unavailable)

    with pytest.raises(BrokerError):
        RecoveryApplication(engine.ledger, broker).record_manual_sale(sale, account_id="paper-demo")

    assert engine.ledger.snapshot() == before == repository.load()


@pytest.mark.parametrize("operation", ["account", "lookup", "open_orders", "positions"])
def test_clearance_does_not_clear_when_any_required_broker_read_fails(operation):
    from copytrading_engine.execution.application.recovery import RecoveryApplication

    engine, broker, repository, uncertain = _uncertain_system()
    broker.orders.clear()
    initial = RecoveryApplication(
        engine.ledger,
        broker,
        clock=lambda: NOW + dt.timedelta(seconds=2),
    )
    _release(initial, uncertain.client_id)
    broker.orders[uncertain.client_id] = {
        "id": "late-order-id",
        "client_order_id": uncertain.client_id,
        "symbol": uncertain.symbol,
        "side": uncertain.side,
        "qty": str(uncertain.qty),
        "filled_qty": str(uncertain.qty),
        "filled_avg_price": str(uncertain.limit_price),
        "status": "filled",
    }
    broker.holdings[uncertain.symbol] = uncertain.qty
    before = engine.ledger.snapshot()

    def unavailable(*_args, **_kwargs):
        raise BrokerError()

    setattr(broker, operation, unavailable)
    app = RecoveryApplication(engine.ledger, broker, clock=lambda: NOW + dt.timedelta(seconds=20))

    with pytest.raises(BrokerError):
        app.clear_late_order_incident(
            uncertain.client_id,
            actor=ACTOR,
            reason=REASON,
            matched_audit_ref="position-audit-ticket-41",
            account_id="paper-demo",
        )

    if operation in {"account", "lookup"}:
        assert engine.ledger.snapshot() == before == repository.load()
    else:
        incident = engine.ledger.snapshot().late_order_incidents[uncertain.client_id]
        assert engine.ledger.snapshot().entry_halted
        assert incident.unresolved
        assert repository.events[-1].payload.kind == "late_order_incident_opened"
