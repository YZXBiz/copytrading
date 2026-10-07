"""Broker holdings and app lots have separate, durable ownership."""

import asyncio
import datetime as dt
import json
import sqlite3
import threading
from decimal import Decimal

import pytest
from pydantic import SecretStr, ValidationError

from copytrading_engine.execution.adapters.alpaca.broker import AlpacaCredentials
from copytrading_engine.execution.adapters.owner import ExecutionOwner
from copytrading_engine.execution.adapters.sqlite_ledger import Store
from copytrading_engine.execution.application.engine import CopyEngine
from copytrading_engine.execution.application.ports import AccountOpenRefused
from copytrading_engine.execution.application.recovery import RecoveryApplication
from copytrading_engine.execution.domain.ledger_state import LedgerSnapshot
from copytrading_engine.execution.domain.lifecycle import AccountControlCommand
from copytrading_engine.execution.domain.market import BrokerOrder, Position
from copytrading_engine.execution.domain.ownership import OwnershipResolutionRequest
from copytrading_engine.execution.domain.progress import Skipped
from copytrading_engine.execution.domain.recovery import ManualSale
from copytrading_engine.execution.domain.signals import CopyConfig
from copytrading_engine.shared.signals import StockSignal

from .builders import (
    NOW,
    destination_signal,
    engine_with_wide_limits,
    event,
    late_sell_with_consumed_source_lot,
    mixed_account,
    receive,
)
from .fakes import FakeBroker, MemoryRepository


def test_initial_holdings_are_external_and_broker_order_blocks_initialization():
    store = MemoryRepository()
    broker = FakeBroker()
    broker.holdings["ABC"] = Decimal("100")
    engine = engine_with_wide_limits(store, broker)

    engine.bind(NOW)

    assert engine.ledger.owned("ABC") == 0
    assert engine.ledger.snapshot().external_positions["ABC"].qty == 100
    assert engine.audit_positions().matched
    assert len(store.events) == 1
    assert store.events[0].payload.kind == "account_inventoried"
    corrupt = store.load().model_dump(mode="json")
    corrupt["external_positions"]["WRONG"] = corrupt["external_positions"].pop("ABC")
    with pytest.raises(ValidationError, match="External position"):
        LedgerSnapshot.model_validate_json(json.dumps(corrupt))


def test_initial_manual_open_order_prevents_inventory_commit():
    store = MemoryRepository()
    broker = FakeBroker()
    broker.holdings["ABC"] = Decimal("100")
    broker.orders["manual-pending"] = BrokerOrder(
        id="broker-manual",
        client_order_id="manual-pending",
        symbol="ABC",
        side="sell",
        qty=Decimal(1),
        filled_qty=Decimal(0),
        filled_avg_price=None,
        status="new",
    ).model_dump(mode="json")
    with pytest.raises(AccountOpenRefused) as refused:
        engine_with_wide_limits(store, broker).bind(NOW)
    assert refused.value.reason == "outside_open_orders"
    assert store.load().account_id is None
    assert not store.events


def test_external_only_holding_cannot_be_sold_by_app_exit():
    store = MemoryRepository()
    broker = FakeBroker()
    broker.holdings["ABC"] = Decimal("100")
    engine = engine_with_wide_limits(store, broker)
    engine.bind(NOW)
    receive(
        engine,
        StockSignal.model_validate(event("exit", action="close", price="27", entry="25")),
        NOW,
    )
    engine.process(NOW)
    assert engine.ledger.message("discord:demo:exit").parts == (
        Skipped(reason="missing_or_ambiguous_lot"),
    )
    assert broker.calls == 0


def test_mixed_100_external_plus_50_owned_exit_sells_only_owned_lot():
    _, broker, engine = mixed_account()
    assert engine.audit_positions().positions[0].expected == 150
    assert engine.audit_positions().matched
    later = NOW + dt.timedelta(minutes=11)
    receive(
        engine,
        StockSignal.model_validate(
            event("exit", action="close", price="27", entry="25", timestamp=later)
        ),
        later,
    )
    engine.process(later)
    assert broker.holdings["ABC"] == 100
    assert engine.ledger.owned("ABC") == 0
    assert engine.ledger.snapshot().external_positions["ABC"].qty == 100
    sell = next(order for order in engine.ledger.orders() if order.side == "sell")
    assert sell.qty == 50
    assert sell.position_intent == "sell_to_close"


def test_broker_result_cannot_change_persisted_position_intent():
    broker = FakeBroker()
    engine = engine_with_wide_limits(MemoryRepository(), broker)
    engine.bind(NOW)
    receive(engine, StockSignal.model_validate(event()), NOW)
    engine.process(NOW)
    order = engine.ledger.orders()[0]
    assert order.position_intent == "buy_to_open"
    assert broker.orders[order.client_id]["position_intent"] == "buy_to_open"
    before = engine.ledger.snapshot()
    missing_intent = before.model_dump(mode="json")
    missing_intent["orders"][order.client_id].pop("position_intent")
    with pytest.raises(ValidationError, match="position_intent"):
        LedgerSnapshot.model_validate_json(json.dumps(missing_intent))
    broker.orders[order.client_id]["position_intent"] = "sell_to_close"
    with pytest.raises(RuntimeError, match="position intent mismatch"):
        engine.ledger.apply_order(order.client_id, broker.lookup(order.client_id), NOW)
    assert engine.ledger.snapshot() == before


def test_first_bind_identity_inventory_and_journal_roll_back_together(tmp_path):
    path = tmp_path / "execution.sqlite3"
    broker = FakeBroker()
    broker.holdings["ABC"] = Decimal("100")
    store = Store(path)
    store.bind_identity("paper-demo", "paper")
    store.db.execute(
        "CREATE TRIGGER reject_journal BEFORE INSERT ON journal "
        "BEGIN SELECT RAISE(ABORT, 'failure'); END"
    )
    engine = engine_with_wide_limits(store, broker)
    with pytest.raises(sqlite3.DatabaseError):
        engine.bind(NOW)
    assert store.db.execute("SELECT count(*) FROM identity").fetchone()[0] == 0
    assert store.db.execute("SELECT count(*) FROM snapshot").fetchone()[0] == 0
    store.close()

    reopened = Store(path)
    assert reopened.load().account_id is None
    reopened.close()


def test_manual_sale_from_mixed_holdings_opens_durable_symbol_incident():
    store, broker, engine = mixed_account()
    owned = engine.ledger.owned("ABC")
    sale_qty = Decimal("10")
    order = BrokerOrder(
        id="manual-1",
        client_order_id="manual-client-1",
        symbol="ABC",
        side="sell",
        qty=sale_qty,
        filled_qty=sale_qty,
        filled_avg_price=Decimal("25"),
        status="filled",
    )
    broker.orders[order.client_order_id] = order.model_dump(mode="json")
    broker.holdings["ABC"] -= sale_qty
    sale = ManualSale(
        order=order,
        filled_at=NOW + dt.timedelta(seconds=1),
        recorded_at=NOW + dt.timedelta(seconds=2),
        reason="verified account activity",
    )
    RecoveryApplication(
        engine.ledger, broker, clock=lambda: NOW + dt.timedelta(seconds=2)
    ).record_manual_sale(sale, account_id="paper-demo")

    assert engine.ledger.owned("ABC") == owned
    incident = engine.ledger.snapshot().ownership_incidents[order.id]
    assert incident.symbol == "ABC"
    assert incident.expected_qty == owned + 100
    assert incident.actual_qty == owned + 90
    assert not incident.resolved
    count = len(store.events)
    RecoveryApplication(
        engine.ledger, broker, clock=lambda: NOW + dt.timedelta(seconds=3)
    ).record_manual_sale(
        sale.model_copy(update={"recorded_at": NOW + dt.timedelta(seconds=3)}),
        account_id="paper-demo",
    )
    assert len(store.events) == count
    restarted = engine_with_wide_limits(store, broker)
    assert restarted.ledger.snapshot().ownership_incidents[order.id] == incident

    later = NOW + dt.timedelta(minutes=11)
    receive(engine, StockSignal.model_validate(event("blocked-buy", timestamp=later)), later)
    receive(
        engine,
        StockSignal.model_validate(
            event("blocked-exit", action="close", price="27", entry="25", timestamp=later)
        ),
        later,
    )
    engine.process(later)
    assert engine.ledger.message("discord:demo:blocked-buy").parts == (
        Skipped(reason="ownership_incident"),
    )
    assert engine.ledger.message("discord:demo:blocked-exit").parts == (
        Skipped(reason="ownership_incident"),
    )

    other = event("other-symbol", timestamp=later)
    other["instructions"][0]["symbol"] = "XYZ"
    other["evidence"][0]["symbol"] = "XYZ"
    other["evidence"][0]["symbol_evidence"] = "XYZ"
    receive(engine, StockSignal.model_validate(other), later)
    engine.process(later)
    assert broker.calls == 2
    assert engine.ledger.owned("XYZ") == 4


def test_resolution_requires_fresh_conservation_and_replays_by_id():
    store, broker, engine = mixed_account()
    owned = engine.ledger.owned("ABC")
    order = BrokerOrder(
        id="manual-2",
        client_order_id="manual-client-2",
        symbol="ABC",
        side="sell",
        qty=Decimal("10"),
        filled_qty=Decimal("10"),
        filled_avg_price=Decimal("25"),
        status="filled",
    )
    broker.orders[order.client_order_id] = order.model_dump(mode="json")
    broker.holdings["ABC"] -= Decimal("10")
    app = RecoveryApplication(engine.ledger, broker, clock=lambda: NOW + dt.timedelta(seconds=3))
    app.record_manual_sale(
        ManualSale(
            order=order,
            filled_at=NOW + dt.timedelta(seconds=1),
            recorded_at=NOW + dt.timedelta(seconds=2),
            reason="verified account activity",
        ),
        account_id="paper-demo",
    )
    lot_id = next(iter(engine.ledger.snapshot().lots))
    request = OwnershipResolutionRequest(
        resolution_id="resolution-1",
        incident_id="manual-2",
        account_id="paper-demo",
        symbol="ABC",
        actor="operator",
        reason="verified external sale allocation",
        broker_qty=owned + 90,
        external_qty=Decimal("90"),
        lot_remaining={lot_id: owned},
    )
    result = app.resolve_ownership(request)
    assert result.external_qty == 90
    assert result.allocation_revision == 1
    assert app.resolve_ownership(request) == result
    assert (
        engine_with_wide_limits(store, broker)
        .ledger.snapshot()
        .ownership_resolutions["resolution-1"]
        == result
    )
    corrupt = store.load().model_dump(mode="json")
    corrupt["ownership_resolutions"]["resolution-1"]["request"]["account_id"] = "other"
    with pytest.raises(ValidationError, match="Ownership resolution"):
        LedgerSnapshot.model_validate_json(json.dumps(corrupt))
    corrupt = store.load().model_dump(mode="json")
    corrupt["ownership_resolutions"]["resolution-1"]["lot_reductions"][lot_id] = "1"
    with pytest.raises(ValidationError, match="Lot quantity"):
        LedgerSnapshot.model_validate_json(json.dumps(corrupt))
    corrupt = store.load().model_dump(mode="json")
    corrupt["ownership_resolutions"]["resolution-1"]["lot_reductions"] = {}
    with pytest.raises(ValidationError, match="lot allocation"):
        LedgerSnapshot.model_validate_json(json.dumps(corrupt))
    corrupt = store.load().model_dump(mode="json")
    corrupt["external_positions"]["ABC"]["qty"] = "89"
    with pytest.raises(ValidationError, match="latest ownership allocation"):
        LedgerSnapshot.model_validate_json(json.dumps(corrupt))
    with pytest.raises(ValueError, match=r"conflict|different"):
        app.resolve_ownership(request.model_copy(update={"reason": "different"}))
    with pytest.raises(ValueError, match=r"conserv|quantity"):
        app.resolve_ownership(
            request.model_copy(
                update={"resolution_id": "resolution-2", "external_qty": Decimal("89")}
            )
        )
    broker.holdings["ABC"] = Decimal("139")
    engine.reconcile(NOW + dt.timedelta(seconds=2))
    next_incident = next(
        incident.incident_id
        for incident in engine.ledger.snapshot().ownership_incidents.values()
        if not incident.resolved
    )
    next_request = request.model_copy(
        update={
            "resolution_id": "resolution-2",
            "incident_id": next_incident,
            "broker_qty": Decimal("139"),
            "external_qty": Decimal("89"),
        }
    )
    second = app.resolve_ownership(next_request)
    assert second.checked_at == result.checked_at
    assert second.allocation_revision == 2
    assert store.load().external_positions["ABC"].qty == 89


def test_resolution_rejects_stale_broker_quantity_and_overlapping_order():
    _, broker, engine = mixed_account()
    broker.holdings["ABC"] = Decimal("145")
    engine.reconcile(NOW + dt.timedelta(seconds=1))
    incident_id = next(iter(engine.ledger.snapshot().ownership_incidents))
    lot_id = next(iter(engine.ledger.snapshot().lots))
    app = RecoveryApplication(engine.ledger, broker, clock=lambda: NOW + dt.timedelta(seconds=2))
    request = OwnershipResolutionRequest(
        resolution_id="resolution-overlap",
        incident_id=incident_id,
        account_id="paper-demo",
        symbol="ABC",
        actor="operator",
        reason="verified allocation",
        broker_qty=Decimal("145"),
        external_qty=Decimal("95"),
        lot_remaining={lot_id: Decimal("50")},
    )
    broker.holdings["ABC"] = Decimal("144")
    with pytest.raises(ValueError, match="Fresh broker quantity"):
        app.resolve_ownership(request)
    broker.holdings["ABC"] = Decimal("145")
    broker.orders["manual-pending"] = BrokerOrder(
        id="broker-manual",
        client_order_id="manual-pending",
        symbol="ABC",
        side="sell",
        qty=Decimal(1),
        filled_qty=Decimal(0),
        filled_avg_price=None,
        status="new",
    ).model_dump(mode="json")
    with pytest.raises(ValueError, match="open order"):
        app.resolve_ownership(request)
    broker.orders.pop("manual-pending")
    for index in range(500):
        broker.orders[f"other-{index}"] = BrokerOrder(
            id=f"broker-other-{index}",
            client_order_id=f"other-{index}",
            symbol="XYZ",
            side="buy",
            qty=Decimal(1),
            filled_qty=Decimal(0),
            filled_avg_price=None,
            status="new",
        ).model_dump(mode="json")
    with pytest.raises(ValueError, match="incomplete"):
        app.resolve_ownership(request)


@pytest.mark.parametrize("interleaved_symbol", ["ABC", "XYZ"])
def test_resolution_rechecks_activity_after_position_observation(interleaved_symbol):
    _, broker, engine = mixed_account()
    broker.holdings["ABC"] = Decimal("145")
    engine.reconcile(NOW + dt.timedelta(seconds=1))
    incident_id = next(iter(engine.ledger.snapshot().ownership_incidents))
    lot_id = next(iter(engine.ledger.snapshot().lots))
    request = OwnershipResolutionRequest(
        resolution_id="resolution-race",
        incident_id=incident_id,
        account_id="paper-demo",
        symbol="ABC",
        actor="operator",
        reason="verified allocation",
        broker_qty=Decimal("145"),
        external_qty=Decimal("95"),
        lot_remaining={lot_id: Decimal("50")},
    )
    original_positions = broker.positions

    def interleaved_positions():
        broker.orders["manual-pending"] = BrokerOrder(
            id="broker-manual",
            client_order_id="manual-pending",
            symbol=interleaved_symbol,
            side="sell",
            qty=Decimal(1),
            filled_qty=Decimal(0),
            filled_avg_price=None,
            status="new",
        ).model_dump(mode="json")
        return original_positions()

    broker.positions = interleaved_positions
    with pytest.raises(ValueError, match=r"activity changed|open order"):
        RecoveryApplication(
            engine.ledger, broker, clock=lambda: NOW + dt.timedelta(seconds=2)
        ).resolve_ownership(request)
    assert not engine.ledger.snapshot().ownership_incidents[incident_id].resolved


def test_resolution_rechecks_account_identity_after_position_observation():
    _, broker, engine = mixed_account()
    broker.holdings["ABC"] = Decimal("145")
    engine.reconcile(NOW + dt.timedelta(seconds=1))
    incident_id = next(iter(engine.ledger.snapshot().ownership_incidents))
    lot_id = next(iter(engine.ledger.snapshot().lots))
    request = OwnershipResolutionRequest(
        resolution_id="resolution-account-race",
        incident_id=incident_id,
        account_id="paper-demo",
        symbol="ABC",
        actor="operator",
        reason="verified allocation",
        broker_qty=Decimal("145"),
        external_qty=Decimal("95"),
        lot_remaining={lot_id: Decimal("50")},
    )
    original_positions = broker.positions

    def switched_account_positions():
        broker.account_data["id"] = "other-account"
        return original_positions()

    broker.positions = switched_account_positions
    with pytest.raises(ValueError, match="identities"):
        RecoveryApplication(
            engine.ledger, broker, clock=lambda: NOW + dt.timedelta(seconds=2)
        ).resolve_ownership(request)
    assert not engine.ledger.snapshot().ownership_incidents[incident_id].resolved


def test_cleared_quarantine_audit_allows_later_ownership_resolution():
    engine, broker, store, late_order, late_record = late_sell_with_consumed_source_lot()
    late_record["status"] = "new"
    broker.orders[late_order.client_id] = late_record
    broker.fill(late_order.client_id, str(late_order.qty))
    engine.reconcile(NOW + dt.timedelta(minutes=4))
    assert engine.ledger.snapshot().quarantined_fills[late_order.client_id].unapplied_qty > 0
    assert engine.ledger.snapshot().late_order_incidents[late_order.client_id].unresolved

    broker.holdings["ABC"] = engine.ledger.expected_position("ABC")
    RecoveryApplication(
        engine.ledger, broker, clock=lambda: NOW + dt.timedelta(minutes=5)
    ).clear_late_order_incident(
        late_order.client_id,
        actor="operator",
        reason="matched account positions",
        matched_audit_ref="post-quarantine-audit",
        account_id="paper-demo",
    )
    assert store.load().quarantined_fills[late_order.client_id].unapplied_qty > 0
    assert not store.load().late_order_incidents[late_order.client_id].unresolved

    broker.holdings["ABC"] += Decimal("1")
    engine.reconcile(NOW + dt.timedelta(minutes=6))
    incident = next(
        incident
        for incident in engine.ledger.snapshot().ownership_incidents.values()
        if incident.symbol == "ABC" and not incident.resolved
    )
    lot_remaining = {
        lot_id: lot.remaining_qty
        for lot_id, lot in engine.ledger.snapshot().lots.items()
        if lot.symbol == "ABC"
    }
    request = OwnershipResolutionRequest(
        resolution_id="after-cleared-quarantine",
        incident_id=incident.incident_id,
        account_id="paper-demo",
        symbol="ABC",
        actor="operator",
        reason="verified new external share",
        broker_qty=engine.ledger.expected_position("ABC") + Decimal("1"),
        external_qty=Decimal("1"),
        lot_remaining=lot_remaining,
    )
    result = RecoveryApplication(
        engine.ledger, broker, clock=lambda: NOW + dt.timedelta(minutes=7)
    ).resolve_ownership(request)
    assert result.request == request
    assert store.load().quarantined_fills[late_order.client_id].unapplied_qty > 0
    assert engine.audit_positions().matched


@pytest.mark.parametrize("problem", ["missing_valuation", "unknown_order"])
def test_healthy_symbol_exit_requires_accountwide_readiness(problem):
    broker = FakeBroker()
    broker.holdings["ABC"] = Decimal("100")
    engine = engine_with_wide_limits(MemoryRepository(), broker)
    engine.bind(NOW)
    entry = event("xyz-entry")
    entry["instructions"][0]["symbol"] = "XYZ"
    entry["evidence"][0]["symbol"] = "XYZ"
    entry["evidence"][0]["symbol_evidence"] = "XYZ"
    receive(engine, StockSignal.model_validate(entry), NOW)
    engine.process(NOW)
    assert engine.ledger.owned("XYZ") > 0
    submitted = broker.calls

    if problem == "missing_valuation":
        original_positions = broker.positions

        def unvalued_external():
            return tuple(
                Position(symbol=position.symbol, qty=position.qty)
                if position.symbol == "ABC"
                else position
                for position in original_positions()
            )

        broker.positions = unvalued_external
        reason = "account_risk_unavailable"
    else:
        broker.orders["unrelated-manual"] = BrokerOrder(
            id="unrelated-manual",
            client_order_id="unrelated-manual",
            symbol="ABC",
            side="sell",
            qty=Decimal(1),
            filled_qty=Decimal(0),
            filled_avg_price=None,
            status="new",
        ).model_dump(mode="json")
        inspection = RecoveryApplication(engine.ledger, broker).inspect_ownership()
        assert inspection.account_risk_status == "ready"
        assert inspection.account_activity_status == "unavailable"
        reason = "unresolved_account_order"

    later = NOW + dt.timedelta(minutes=11)
    exit_signal = event("xyz-exit", action="close", price="27", entry="25", timestamp=later)
    exit_signal["instructions"][0]["symbol"] = "XYZ"
    exit_signal["evidence"][0]["symbol"] = "XYZ"
    exit_signal["evidence"][0]["symbol_evidence"] = "XYZ"
    receive(engine, StockSignal.model_validate(exit_signal), later)
    engine.process(later)
    assert engine.ledger.message("discord:demo:xyz-exit").parts == (Skipped(reason=reason),)
    assert broker.calls == submitted


def test_external_market_value_consumes_cap_and_missing_value_blocks_entry():
    broker = FakeBroker()
    broker.holdings["ABC"] = Decimal("100")
    engine = CopyEngine(
        MemoryRepository(),
        broker,
        CopyConfig(
            sources=["discord:demo"],
            max_symbol_usd=Decimal("5000"),
            max_total_usd=Decimal("2550"),
        ),
    )
    engine.bind(NOW)
    receive(engine, StockSignal.model_validate(event()), NOW)
    engine.process(NOW)
    [skipped] = engine.ledger.message("discord:demo:1").parts
    assert isinstance(skipped, Skipped)
    assert (skipped.reason, [limit.scope for limit in skipped.exposure]) == (
        "total_exposure_cap",
        ["total"],
    )
    assert broker.calls == 0

    broker.positions = lambda: (Position(symbol="ABC", qty=Decimal("100")),)
    inspection = RecoveryApplication(engine.ledger, broker).inspect_ownership()
    assert inspection.account_risk_status == "unavailable"
    assert inspection.total_exposure_usd is None
    receive(
        engine,
        StockSignal.model_validate(event("second", timestamp=NOW + dt.timedelta(minutes=11))),
        NOW + dt.timedelta(minutes=11),
    )
    engine.process(NOW + dt.timedelta(minutes=11))
    assert engine.ledger.message("discord:demo:second").parts == (
        Skipped(reason="account_risk_unavailable"),
    )


def test_pending_buy_reservation_consumes_total_cap_without_double_counting_fill():
    broker = FakeBroker()
    broker.auto_fill = False
    engine = CopyEngine(
        MemoryRepository(),
        broker,
        CopyConfig(
            sources=["discord:demo"],
            max_total_usd=Decimal("150"),
        ),
    )
    engine.bind(NOW)
    receive(engine, StockSignal.model_validate(event()), NOW)
    engine.process(NOW)
    assert broker.calls == 1

    other = event("other", timestamp=NOW + dt.timedelta(minutes=11))
    other["instructions"][0]["symbol"] = "XYZ"
    other["evidence"][0]["symbol"] = "XYZ"
    other["evidence"][0]["symbol_evidence"] = "XYZ"
    receive(engine, StockSignal.model_validate(other), NOW + dt.timedelta(minutes=11))
    engine.process(NOW + dt.timedelta(minutes=11))
    [skipped] = engine.ledger.message("discord:demo:other").parts
    assert isinstance(skipped, Skipped)
    assert (skipped.reason, [limit.scope for limit in skipped.exposure]) == (
        "total_exposure_cap",
        ["total"],
    )
    assert broker.calls == 1


def test_resolution_sqlite_failure_rolls_back_and_reopens_with_incident(tmp_path):
    path = tmp_path / "execution.sqlite3"
    store = Store(path)
    store.bind_identity("paper-demo", "paper")
    broker = FakeBroker()
    broker.holdings["ABC"] = Decimal("100")
    engine = engine_with_wide_limits(store, broker)
    engine.bind(NOW)
    receive(engine, StockSignal.model_validate(event()), NOW, full_position_usd="7500")
    engine.process(NOW)
    assert engine.ledger.owned("ABC") == 50
    order = BrokerOrder(
        id="manual-sqlite",
        client_order_id="manual-sqlite-client",
        symbol="ABC",
        side="sell",
        qty=Decimal(10),
        filled_qty=Decimal(10),
        filled_avg_price=Decimal(25),
        status="filled",
    )
    broker.orders[order.client_order_id] = order.model_dump(mode="json")
    broker.holdings["ABC"] = Decimal("140")
    app = RecoveryApplication(engine.ledger, broker, clock=lambda: NOW + dt.timedelta(seconds=3))
    app.record_manual_sale(
        ManualSale(
            order=order,
            filled_at=NOW + dt.timedelta(seconds=1),
            recorded_at=NOW + dt.timedelta(seconds=2),
            reason="verified sale",
        ),
        account_id="paper-demo",
    )
    lot_id = next(iter(engine.ledger.snapshot().lots))
    request = OwnershipResolutionRequest(
        resolution_id="resolve-sqlite",
        incident_id="manual-sqlite",
        account_id="paper-demo",
        symbol="ABC",
        actor="operator",
        reason="allocate sale to external holding",
        broker_qty=Decimal(140),
        external_qty=Decimal(90),
        lot_remaining={lot_id: Decimal(50)},
    )
    before = engine.ledger.snapshot()
    journal_count = store.db.execute("SELECT count(*) FROM journal").fetchone()[0]
    store.db.execute(
        "CREATE TRIGGER reject_resolution BEFORE INSERT ON journal "
        "BEGIN SELECT RAISE(ABORT, 'forced rollback'); END"
    )
    with pytest.raises(sqlite3.DatabaseError):
        app.resolve_ownership(request)
    assert engine.ledger.snapshot() == before == store.load()
    assert store.db.execute("SELECT count(*) FROM journal").fetchone()[0] == journal_count
    store.close()

    reopened = Store(path)
    reopened.bind_identity("paper-demo", "paper")
    assert not reopened.load().ownership_incidents["manual-sqlite"].resolved
    reopened.db.execute("DROP TRIGGER reject_resolution")
    restarted = engine_with_wide_limits(reopened, broker)
    result = RecoveryApplication(
        restarted.ledger, broker, clock=lambda: NOW + dt.timedelta(seconds=4)
    ).resolve_ownership(request)
    assert reopened.load().ownership_resolutions["resolve-sqlite"] == result
    reopened.close()


def test_released_and_late_order_checks_include_external_inventory():
    broker = FakeBroker()
    broker.holdings["ABC"] = Decimal(100)
    broker.auto_fill = False
    broker.timeout_after_accept = True
    engine = engine_with_wide_limits(MemoryRepository(), broker)
    engine.bind(NOW)
    receive(engine, StockSignal.model_validate(event()), NOW)
    engine.process(NOW)
    client_id = engine.ledger.orders()[0].client_id
    saved_order = broker.orders.pop(client_id)
    from copytrading_engine.execution.application.recovery import RecoveryApplication

    app = RecoveryApplication(engine.ledger, broker, clock=lambda: NOW + dt.timedelta(seconds=2))
    app.release_uncertain_intent(
        client_id,
        actor="operator",
        reason="verified absent order",
        order_history_ref="orders-1",
        fill_history_ref="fills-1",
        account_id="paper-demo",
    )
    saved_order["status"] = "canceled"
    broker.orders[client_id] = saved_order
    app = RecoveryApplication(engine.ledger, broker, clock=lambda: NOW + dt.timedelta(seconds=4))
    clearance = app.clear_late_order_incident(
        client_id,
        actor="operator",
        reason="verified canceled order",
        matched_audit_ref="positions-1",
        account_id="paper-demo",
    )
    assert clearance.expected_qty == clearance.broker_qty == 100


async def test_owner_cancellation_waits_for_resolution_commit_and_reopens(tmp_path):
    broker = FakeBroker()
    broker.holdings["ABC"] = Decimal(100)
    owner = await ExecutionOwner.open(
        tmp_path / "account",
        AlpacaCredentials(SecretStr("key"), SecretStr("secret")),
        CopyConfig(
            sources=["discord:demo"],
            max_order_usd=Decimal(1250),
            max_symbol_usd=Decimal(10000),
            max_total_usd=Decimal(10000),
        ),
        environment="paper",
        broker_factory=lambda *_: broker,
        account_lock_root=tmp_path / "locks",
    )
    try:
        inventory = await owner.inventory_account(NOW)
        assert inventory.external_positions[0].qty == 100
        assert inventory.account_risk_status == "ready"
        await owner.control_account(
            AccountControlCommand(
                command_id="enable-owner-resolution-test",
                account_id="account",
                action="resume",
            ),
            NOW,
        )
        await owner.receive(
            destination_signal(StockSignal.model_validate(event()), full_position_usd="7500"),
            NOW,
        )
        await owner._submit(lambda resource: resource.engine.process(NOW))
        assert broker.holdings["ABC"] == 150
        manual = BrokerOrder(
            id="manual-owner",
            client_order_id="manual-owner-client",
            symbol="ABC",
            side="sell",
            qty=Decimal(10),
            filled_qty=Decimal(10),
            filled_avg_price=Decimal(25),
            status="filled",
        )
        broker.orders[manual.client_order_id] = manual.model_dump(mode="json")
        broker.holdings["ABC"] = Decimal(140)
        await owner.record_manual_sale(
            ManualSale(
                order=manual,
                filled_at=NOW + dt.timedelta(seconds=1),
                recorded_at=NOW + dt.timedelta(seconds=2),
                reason="verified owner sale",
            ),
            account_id="paper-demo",
        )
        inspection = await owner.inspect_ownership()
        assert inspection.incidents[0].incident_id == "manual-owner"
        lot_id = next(iter((await owner.observation()).ledger.lots))
        request = OwnershipResolutionRequest(
            resolution_id="owner-resolution",
            incident_id="manual-owner",
            account_id="paper-demo",
            symbol="ABC",
            actor="operator",
            reason="allocate verified sale externally",
            broker_qty=Decimal(140),
            external_qty=Decimal(90),
            lot_remaining={lot_id: Decimal(50)},
        )
        started = threading.Event()
        release = threading.Event()
        original_positions = broker.positions

        def delayed_positions():
            started.set()
            release.wait(timeout=5)
            return original_positions()

        broker.positions = delayed_positions
        task = asyncio.create_task(owner.resolve_ownership(request))
        assert await asyncio.to_thread(started.wait, 5)
        task.cancel()
        release.set()
        with pytest.raises(asyncio.CancelledError):
            await task
        broker.positions = original_positions
        assert (await owner.inspect_ownership()).incidents[0].resolved
    finally:
        await owner.close()

    reopened = Store(tmp_path / "account" / "execution.sqlite3")
    reopened.bind_identity("paper-demo", "paper")
    assert reopened.load().ownership_resolutions["owner-resolution"].request == request
    reopened.close()
