"""Orders reach the broker once, lots stay owned by their source, and uncertainty stops the line."""

import datetime as dt
from decimal import Decimal

import pytest
from pydantic import ValidationError

from copytrading_engine.execution.application.engine import CopyEngine
from copytrading_engine.execution.domain.order_lifecycle import OrderStatus
from copytrading_engine.execution.domain.progress import Skipped
from copytrading_engine.execution.domain.recovery import IncidentClearanceEvidence, ReleaseEvidence
from copytrading_engine.execution.domain.signals import CopyConfig
from copytrading_engine.shared.signals import StockSignal

from .builders import NOW, deliver, event, evidence, receive, set_tolerance
from .fakes import FakeBroker, MemoryRepository


def test_buy_reduce_close_preserves_owned_lot(system):
    engine, broker, store = system
    deliver(engine, event())
    assert broker.holdings["ABC"] == 4
    deliver(engine, event("2", "reduce", "27", "25"))
    assert broker.holdings["ABC"] == 2
    deliver(engine, event("3", "close", "28", "25"))
    assert broker.holdings["ABC"] == 0
    assert all(Decimal(lot.remaining_qty) == 0 for lot in store.load().lots.values())


def test_repeated_id_and_reposted_instruction_do_not_duplicate(system):
    engine, broker, _ = system
    deliver(engine, event())
    deliver(engine, event())
    deliver(engine, event("different-id"))
    assert broker.calls == 1


def test_timeout_after_accept_reconciles_once_after_restart(system, tmp_path):
    engine, broker, store = system
    broker.timeout_after_accept = True
    deliver(engine, event())
    assert next(iter(store.load().orders.values())).status == "uncertain"
    resumed_store = MemoryRepository(store.snapshot_json)
    resumed = CopyEngine(resumed_store, broker, engine.config)
    resumed.bind(NOW)
    resumed.reconcile(NOW)
    deliver(resumed, event())
    assert broker.calls == 1
    assert Decimal(next(iter(resumed_store.load().lots.values())).remaining_qty) == 4


def test_unknown_submission_is_never_retried(system):
    engine, broker, store = system
    broker.timeout_after_accept = True
    deliver(engine, event())
    broker.orders.clear()
    engine.reconcile(NOW + dt.timedelta(seconds=70))
    engine.process(NOW + dt.timedelta(seconds=70))
    assert broker.calls == 1
    assert next(iter(store.load().orders.values())).status == "uncertain"


def test_exit_cancels_a_preceding_cancelable_entry_then_sells_filled_shares(system):
    engine, broker, _ = system
    broker.auto_fill = False
    deliver(engine, event())
    buy_id = next(iter(broker.orders))
    broker.fill(buy_id, "2")
    engine.reconcile(NOW)
    engine.reconcile(NOW)
    deliver(engine, event("2", "reduce", "27", "25"))
    assert broker.calls == 1
    assert broker.orders[buy_id]["status"] == "canceled"
    assert engine.pending()[0].status is OrderStatus.PARTIALLY_FILLED
    engine.reconcile(NOW)
    assert engine.ledger.order(buy_id).status is OrderStatus.CANCELED
    broker.auto_fill = True
    engine.process(NOW)
    assert broker.calls == 2
    assert broker.holdings["ABC"] == 1


def test_other_source_cannot_close_owned_lot(system):
    engine, broker, _ = system
    deliver(engine, event())
    with pytest.raises(ValueError, match="source"):
        deliver(engine, event("2", "close", "27", "25", channel="other"))
    assert broker.holdings["ABC"] == 4


def test_same_entry_price_in_multiple_lots_is_ambiguous(system):
    engine, broker, _ = system
    deliver(engine, event())
    later = NOW + dt.timedelta(minutes=11)
    deliver(engine, event("2", timestamp=later), later)
    deliver(engine, event("3", "close", "27", "25", timestamp=later), later)
    assert broker.calls == 2


def test_aged_cancelable_limit_order_is_canceled_and_confirmed(system):
    engine, broker, _ = system
    broker.auto_fill = False
    deliver(engine, event())
    client_id = next(iter(broker.orders))
    engine.reconcile(NOW + dt.timedelta(seconds=61))
    engine.reconcile(NOW + dt.timedelta(seconds=62))
    assert broker.orders[client_id]["status"] == "canceled"
    assert engine.ledger.order(client_id).status is OrderStatus.CANCELED
    assert engine.pending() == ()
    assert broker.calls == 1


def test_unknown_broker_status_remains_reserved_when_lookup_is_temporarily_absent(system):
    engine, broker, _ = system
    broker.auto_fill = False
    deliver(engine, event())
    client_id = next(iter(broker.orders))
    broker.orders[client_id]["status"] = "awaiting_internal_routing"

    engine.reconcile(NOW + dt.timedelta(seconds=70))

    quarantined = engine.ledger.order(client_id)
    assert quarantined.status is OrderStatus.UNRECOGNIZED
    assert quarantined.raw_broker_status == "awaiting_internal_routing"
    assert quarantined.pending
    assert broker.orders[client_id]["status"] == "awaiting_internal_routing"

    broker.orders.pop(client_id)
    engine.reconcile(NOW + dt.timedelta(seconds=75))

    assert engine.ledger.order(client_id).status is OrderStatus.UNRECOGNIZED
    assert engine.ledger.order(client_id).raw_broker_status == "awaiting_internal_routing"
    assert engine.pending()[0].client_id == client_id
    assert broker.calls == 1


def test_unknown_order_status_does_not_block_an_unrelated_new_entry(system):
    engine, broker, _ = system
    broker.auto_fill = False
    deliver(engine, event())
    client_id = next(iter(broker.orders))
    broker.orders[client_id]["status"] = "awaiting_internal_routing"
    engine.reconcile(NOW)
    assert engine.ledger.order(client_id).status is OrderStatus.UNRECOGNIZED

    unrelated = event("unrelated-entry", timestamp=NOW + dt.timedelta(seconds=1))
    unrelated["instructions"][0]["symbol"] = "DEF"
    unrelated["evidence"] = [evidence(unrelated["instructions"][0])]
    receive(engine, StockSignal.model_validate(unrelated), NOW + dt.timedelta(seconds=1))
    engine.process(NOW + dt.timedelta(seconds=1))

    assert broker.calls == 2
    assert engine.ledger.order(client_id).raw_broker_status == "awaiting_internal_routing"
    assert any(order.symbol == "DEF" for order in engine.ledger.orders())


def test_exit_does_not_cancel_an_unknown_order_status(system):
    engine, broker, store = system
    broker.auto_fill = False
    deliver(engine, event())
    client_id = next(iter(broker.orders))
    broker.fill(client_id, "2")
    engine.reconcile(NOW)
    broker.orders[client_id]["status"] = "awaiting_internal_routing"
    engine.reconcile(NOW + dt.timedelta(seconds=1))
    assert engine.ledger.order(client_id).status is OrderStatus.UNRECOGNIZED

    receive(
        engine,
        StockSignal.model_validate(event("exit-unknown", "reduce", "27", "25")),
        NOW + dt.timedelta(seconds=2),
    )
    engine.process(NOW + dt.timedelta(seconds=2))

    assert broker.orders[client_id]["status"] == "awaiting_internal_routing"
    assert engine.ledger.order(client_id).status is OrderStatus.UNRECOGNIZED
    assert not any(event.payload.kind == "cancel_requested" for event in store.events)
    assert broker.calls == 1


def test_released_client_id_is_rechecked_after_clearance(system):
    engine, broker, _ = system
    broker.auto_fill = False
    broker.timeout_after_accept = True
    deliver(engine, event())
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

    lookup_ids = []
    original_lookup = broker.lookup

    def tracked_lookup(client_id):
        lookup_ids.append(client_id)
        return original_lookup(client_id)

    broker.lookup = tracked_lookup
    engine.reconcile(NOW + dt.timedelta(seconds=2))
    assert engine.ledger.order(order.client_id).status is OrderStatus.RELEASED_UNSUBMITTED
    assert engine.ledger.order(order.client_id).raw_broker_status is None

    observed_order["status"] = "rejected"
    broker.orders[order.client_id] = observed_order
    engine.reconcile(NOW + dt.timedelta(seconds=3))
    incident = engine.ledger.snapshot().late_order_incidents[order.client_id]
    assert incident.unresolved
    assert engine.ledger.snapshot().buy_halted

    engine.ledger.clear_late_order_incident(
        order.client_id,
        IncidentClearanceEvidence(
            actor="operator@example.test",
            reason="Fresh matched position audit",
            checked_at=NOW + dt.timedelta(seconds=4),
            account_id="paper-demo",
            matched_audit_ref="audit-1",
            symbol="ABC",
            expected_qty=Decimal(0),
            broker_qty=Decimal(0),
        ),
    )
    assert not engine.ledger.snapshot().buy_halted
    lookups_before_clearance_poll = len(lookup_ids)

    engine.reconcile(NOW + dt.timedelta(seconds=5))

    assert len(lookup_ids) == lookups_before_clearance_poll + 1
    assert lookup_ids[-1] == order.client_id
    assert engine.ledger.snapshot().late_order_incidents[order.client_id].cleared


def test_late_incident_blocks_new_buys_and_unrelated_matched_lot_exit(system):
    engine, broker, _ = system
    deliver(engine, event())

    late_signal = event("late-intent", timestamp=NOW + dt.timedelta(minutes=11))
    late_signal["instructions"][0]["symbol"] = "DEF"
    late_signal["evidence"] = [evidence(late_signal["instructions"][0])]
    broker.auto_fill = False
    broker.timeout_after_accept = True
    receive(engine, StockSignal.model_validate(late_signal), NOW + dt.timedelta(minutes=11))
    engine.process(NOW + dt.timedelta(minutes=11))
    late_order = next(order for order in engine.ledger.orders() if order.symbol == "DEF")
    broker_observation = dict(broker.orders.pop(late_order.client_id))
    engine.ledger.release_uncertain_intent(
        late_order.client_id,
        ReleaseEvidence(
            actor="operator@example.test",
            reason="Broker history confirms no accepted order or fills",
            order_history_ref="order-history-1",
            fill_history_ref="fill-history-1",
            checked_at=NOW + dt.timedelta(minutes=11, seconds=1),
            account_id="paper-demo",
        ),
    )
    broker_observation["status"] = "rejected"
    broker.orders[late_order.client_id] = broker_observation
    broker.timeout_after_accept = False
    engine.reconcile(NOW + dt.timedelta(minutes=11, seconds=2))
    assert engine.ledger.snapshot().buy_halted

    blocked_buy = event("blocked-buy", timestamp=NOW + dt.timedelta(minutes=12))
    blocked_buy["instructions"][0]["symbol"] = "GHI"
    blocked_buy["evidence"] = [evidence(blocked_buy["instructions"][0])]
    receive(engine, StockSignal.model_validate(blocked_buy), NOW + dt.timedelta(minutes=12))
    engine.process(NOW + dt.timedelta(minutes=12))
    assert engine.ledger.message("discord:demo:blocked-buy").parts == (Skipped(reason="halted"),)
    assert broker.calls == 2

    broker.auto_fill = True
    exit_signal = event(
        "matched-exit",
        "close",
        "27",
        "25",
        timestamp=NOW + dt.timedelta(minutes=13),
    )
    receive(engine, StockSignal.model_validate(exit_signal), NOW + dt.timedelta(minutes=13))
    engine.process(NOW + dt.timedelta(minutes=13))
    assert broker.calls == 2
    assert broker.holdings["ABC"] == 4
    assert engine.ledger.message("discord:demo:matched-exit").parts == (
        Skipped(reason="unresolved_order_incident"),
    )


def test_existing_account_positions_are_inventoried_without_app_lots(tmp_path):
    broker = FakeBroker()
    broker.holdings["ABC"] = Decimal(10)
    store = MemoryRepository()
    engine = CopyEngine(
        store,
        broker,
        CopyConfig(sources=["discord:demo"]),
    )
    engine.bind(NOW)
    assert engine.ledger.owned("ABC") == 0
    assert engine.ledger.snapshot().external_positions["ABC"].qty == 10


def test_review_cannot_smuggle_an_instruction(system):
    engine, broker, _ = system
    message = event()
    message["decision"] = "review"
    with pytest.raises(
        ValidationError, match="Only validated trade decisions contain instructions"
    ):
        deliver(engine, message)
    assert broker.calls == 0


def test_broker_identity_mismatch_stops_processing(system):
    engine, broker, _ = system
    broker.auto_fill = False
    deliver(engine, event())
    order = next(iter(broker.orders.values()))
    order["symbol"] = "OTHER"
    with pytest.raises(RuntimeError, match="identity"):
        engine.reconcile(NOW)


def test_reconciliation_does_not_require_message_bus(system):
    engine, broker, _ = system
    broker.auto_fill = False
    deliver(engine, event())
    broker.fill(next(iter(broker.orders)), "2")
    engine.reconcile(NOW)
    engine.process(NOW, halted=True)
    engine.audit_positions()
    assert Decimal(next(iter(engine.ledger.snapshot().lots.values())).remaining_qty) == 2


def test_late_entry_cannot_execute_after_a_newer_exit_was_seen(system):
    engine, broker, _ = system
    deliver(engine, event("exit", "close", "27", "25"))
    deliver(engine, event("late-entry", timestamp=NOW - dt.timedelta(seconds=10)))
    assert broker.calls == 0
    assert engine.ledger.snapshot().messages["discord:demo:late-entry"].status == "out_of_order"


def test_pending_limit_survives_restart_and_policy_change(system):
    engine, broker, store = system
    set_tolerance(engine)
    broker.auto_fill = False
    deliver(engine, event())
    restarted = MemoryRepository(store.snapshot_json)
    new_engine = CopyEngine(restarted, broker, CopyConfig(sources=["discord:demo"]))
    new_engine.reconcile(NOW)
    saved = next(iter(restarted.load().orders.values()))
    assert saved.limit_price == Decimal("25.25")
    assert saved.entry_price == Decimal("25")
    assert saved.entry_tolerance_pct == Decimal("1")
    assert broker.calls == 1


@pytest.mark.parametrize("stage", ["asset", "order_prepared", "submit_started"])
def test_late_submission_is_aborted_at_every_durable_boundary(system, stage):
    engine, broker, store = system
    current = [NOW + dt.timedelta(seconds=119)]
    receive(engine, StockSignal.model_validate(event()), current[0])

    def advance():
        current[0] += dt.timedelta(seconds=2)

    if stage == "asset":
        original = broker.asset

        def delayed_asset(symbol):
            result = original(symbol)
            advance()
            return result

        broker.asset = delayed_asset
    else:
        original = store.save

        def delayed_save(snapshot, journal):
            original(snapshot, journal)
            if journal.payload.kind == stage:
                advance()

        store.save = delayed_save
    engine.process(current[0], now_clock=lambda: current[0])
    assert broker.calls == 0
    assert engine.ledger.message("discord:demo:1").status == "done"
    if stage == "asset":
        assert engine.ledger.message("discord:demo:1").parts == (Skipped(reason="stale"),)
        assert not engine.ledger.orders()
    else:
        order = engine.ledger.orders()[0]
        assert order.status == "aborted_before_submit"
        assert not order.pending
        assert [e.payload.kind for e in store.events][-2:] == ["submission_aborted", "message_done"]
        engine.reconcile(current[0])
        assert broker.calls == 0


@pytest.mark.parametrize("stage", ["order_prepared", "submit_started"])
@pytest.mark.parametrize(("control", "reason"), [("halted", "halted"), ("stopping", "stopping")])
def test_dynamic_control_blocks_submission_after_durable_transition(system, stage, control, reason):
    engine, broker, store = system
    receive(engine, StockSignal.model_validate(event()), NOW)
    flags = {"halted": False, "stopping": False}
    original = store.save

    def changed_after_save(snapshot, journal):
        original(snapshot, journal)
        if journal.payload.kind == stage:
            flags[control] = True

    store.save = changed_after_save
    engine.process(
        NOW,
        halted_now=lambda: flags["halted"],
        stopping=lambda: flags["stopping"],
    )

    assert broker.calls == 0
    assert engine.ledger.orders()[0].status == "aborted_before_submit"
    assert store.events[-2].payload.kind == "submission_aborted"
    assert store.events[-2].payload.reason == reason


@pytest.mark.parametrize("stage", ["order_prepared", "submit_started"])
def test_session_change_blocks_submission_after_durable_transition(system, stage):
    engine, broker, store = system
    near_close = dt.datetime(2026, 1, 5, 20, 59, 59, tzinfo=dt.UTC)
    current = [near_close]
    receive(engine, StockSignal.model_validate(event(timestamp=near_close)), near_close)
    original = store.save

    def changed_after_save(snapshot, journal):
        original(snapshot, journal)
        if journal.payload.kind == stage:
            current[0] += dt.timedelta(seconds=2)

    store.save = changed_after_save
    engine.process(near_close, now_clock=lambda: current[0])

    assert broker.calls == 0
    assert engine.ledger.orders()[0].status == "aborted_before_submit"
    assert store.events[-2].payload.kind == "submission_aborted"
    assert store.events[-2].payload.reason == "session_changed"


def test_default_process_clock_advances_with_monotonic_time(system):
    engine, broker, _ = system
    received_at = NOW + dt.timedelta(seconds=119)
    receive(engine, StockSignal.model_validate(event()), received_at)
    monotonic = [100.0]
    original = broker.asset

    def delayed_asset(symbol):
        result = original(symbol)
        monotonic[0] += 2
        return result

    broker.asset = delayed_asset
    engine.process(received_at, monotonic_clock=lambda: monotonic[0])
    assert broker.calls == 0
    assert engine.ledger.message("discord:demo:1").parts == (Skipped(reason="stale"),)


@pytest.mark.parametrize(("action", "qty"), [("reduce", "2"), ("close", "4")])
def test_market_exit_survives_timeout_restart_and_partial_fills(system, action, qty):
    engine, broker, store = system
    deliver(engine, event())
    broker.auto_fill = False
    # The source price is metadata, not a limit or tick-size restriction.
    deliver(engine, event("exit", action, "27.123", "25"))
    order = engine.ledger.orders()[-1]
    assert order.type == "market"
    assert order.limit_price is None
    assert order.source_price == Decimal("27.123")
    assert order.qty == Decimal(qty)
    broker.fill(order.client_id, "1")
    restarted = CopyEngine(MemoryRepository(store.snapshot_json), broker, engine.config)
    later = NOW + dt.timedelta(seconds=90)
    restarted.bind(later)
    restarted.reconcile(later)
    restarted.reconcile(later)
    restarted.process(later)
    assert restarted.ledger.order(order.client_id).status == "partially_filled"
    assert restarted.ledger.owned("ABC") == 3
    assert broker.calls == 2
    broker.fill(order.client_id, qty)
    restarted.reconcile(later)
    assert restarted.ledger.owned("ABC") == 4 - Decimal(qty)
    assert not restarted.pending()


def test_uncertain_market_exit_is_reconciled_without_duplicate_submission(system):
    engine, broker, store = system
    deliver(engine, event())
    broker.timeout_after_accept = True
    deliver(engine, event("exit", "reduce", "27", "25"))
    order = engine.ledger.orders()[-1]
    assert order.status == "uncertain"
    restarted = CopyEngine(MemoryRepository(store.snapshot_json), broker, engine.config)
    restarted.bind(NOW)
    restarted.reconcile(NOW)
    deliver(restarted, event("exit", "reduce", "27", "25"))
    assert broker.calls == 2
    assert restarted.ledger.owned("ABC") == 2
