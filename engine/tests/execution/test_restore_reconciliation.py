"""A restored ledger is accepted only when broker evidence proves nothing moved since the cut."""

import datetime as dt
from decimal import Decimal

import pytest

from copytrading_engine.execution.application.ports import (
    BrokerRestoreEvidence,
    BrokerTimelineEvent,
)
from copytrading_engine.execution.application.restore_reconciliation import (
    RestoreReconciliationError,
    reconcile_restore_snapshot,
)
from copytrading_engine.execution.domain.ledger_state import LedgerSnapshot
from copytrading_engine.execution.domain.market import Account
from copytrading_engine.execution.domain.order_lifecycle import OrderStatus
from copytrading_engine.execution.domain.orders import OrderRecord
from copytrading_engine.execution.domain.sessions import Session


def _snapshot():
    return LedgerSnapshot(account_id="broker-account", environment="paper")


def _evidence(**changes):
    cutoff = dt.datetime(2026, 9, 27, 16, 30, 0, 500_000, tzinfo=dt.UTC)
    order_ids = changes.pop("orders_after_snapshot", ())
    activity_ids = changes.pop("activity_ids_after_snapshot", ())
    values = {
        "account": Account(
            id="broker-account",
            status="ACTIVE",
            cash=Decimal("5000"),
            buying_power=Decimal("5000"),
            equity=Decimal("5000"),
            last_equity=Decimal("5000"),
            trading_blocked=False,
            account_blocked=False,
            trade_suspended_by_user=False,
            currency="USD",
        ),
        "environment": "paper",
        "positions": {},
        "open_order_client_ids": (),
        "known_orders": {},
        "snapshot_started_at": cutoff,
        "order_events_near_snapshot": tuple(
            BrokerTimelineEvent(identifier, cutoff, resolution_nanoseconds=1_000)
            for identifier in order_ids
        ),
        "activity_events_near_snapshot": tuple(
            BrokerTimelineEvent(identifier, cutoff, resolution_nanoseconds=1_000)
            for identifier in activity_ids
        ),
        "complete": True,
    }
    return BrokerRestoreEvidence(**(values | changes))


def test_restore_blocks_fills_after_snapshot_even_when_positions_return_to_same_value():
    evidence = _evidence(activity_ids_after_snapshot=("fill-buy", "fill-sell"))

    with pytest.raises(RestoreReconciliationError, match="activity after the snapshot"):
        reconcile_restore_snapshot(_snapshot(), evidence)


def test_restore_fails_closed_when_broker_activity_evidence_is_incomplete():
    with pytest.raises(RestoreReconciliationError, match="complete broker activity"):
        reconcile_restore_snapshot(_snapshot(), _evidence(complete=False))


@pytest.mark.parametrize(
    "changes",
    [
        {
            "account": Account(
                id="other-account",
                status="ACTIVE",
                cash=Decimal("5000"),
                buying_power=Decimal("5000"),
                equity=Decimal("5000"),
                last_equity=Decimal("5000"),
                trading_blocked=False,
                account_blocked=False,
                trade_suspended_by_user=False,
                currency="USD",
            )
        },
        {"environment": "live"},
    ],
)
def test_restore_rejects_account_or_environment_identity_mismatch(changes):
    with pytest.raises(RestoreReconciliationError, match="identity"):
        reconcile_restore_snapshot(_snapshot(), _evidence(**changes))


def test_restore_blocks_saved_uncertain_client_id():
    created_at = dt.datetime.now(dt.UTC)
    order = OrderRecord(
        side="buy",
        position_intent="buy_to_open",
        type="limit",
        limit_price=Decimal("200"),
        symbol="AAPL",
        qty=Decimal("1"),
        source_price=Decimal("200"),
        entry_tolerance_pct=Decimal("0"),
        lot_id=None,
        entry_price=Decimal("200"),
        session=Session.REGULAR,
        client_id="uncertain-client",
        message_id="source:123",
        instruction_index=0,
        source_key="source:123",
        status=OrderStatus.UNCERTAIN,
        filled_qty=Decimal("0"),
        broker_id=None,
        created_at=created_at,
        day=created_at.date(),
    )
    snapshot = _snapshot().model_copy(update={"orders": {order.client_id: order}})

    with pytest.raises(RestoreReconciliationError, match="unresolved"):
        reconcile_restore_snapshot(snapshot, _evidence())


def test_restore_rejects_unknown_open_orders_and_position_mismatch():
    with pytest.raises(RestoreReconciliationError, match="open broker orders"):
        reconcile_restore_snapshot(
            _snapshot(),
            _evidence(open_order_client_ids=("manual-order",)),
        )

    with pytest.raises(RestoreReconciliationError, match="holdings"):
        reconcile_restore_snapshot(
            _snapshot(),
            _evidence(positions={"AAPL": Decimal("1")}),
        )


def test_restore_blocks_unresolved_ownership_incident():
    from copytrading_engine.execution.domain.ownership import OwnershipIncident

    incident = OwnershipIncident(
        incident_id="incident-1",
        symbol="AAPL",
        expected_qty=Decimal("1"),
        actual_qty=Decimal("0"),
        observed_at=dt.datetime.now(dt.UTC),
        cause="position_mismatch",
    )
    snapshot = _snapshot().model_copy(
        update={"ownership_incidents": {incident.incident_id: incident}}
    )

    with pytest.raises(RestoreReconciliationError, match="unresolved broker evidence"):
        reconcile_restore_snapshot(snapshot, _evidence())


def test_restore_accepts_exact_quiet_broker_evidence():
    assert reconcile_restore_snapshot(_snapshot(), _evidence()) is None


def test_restore_allows_overlap_events_proven_to_precede_snapshot_cut():
    cutoff = dt.datetime(2026, 9, 27, 16, 30, 0, 500_000, tzinfo=dt.UTC)
    before_cut = cutoff - dt.timedelta(milliseconds=500)
    evidence = _evidence(
        order_events_near_snapshot=(
            BrokerTimelineEvent("before-order", before_cut, resolution_nanoseconds=1_000),
        ),
        activity_events_near_snapshot=(
            BrokerTimelineEvent("before-fill", before_cut, resolution_nanoseconds=1_000),
        ),
    )

    assert evidence.orders_after_snapshot == ()
    assert evidence.activity_ids_after_snapshot == ()
    assert reconcile_restore_snapshot(_snapshot(), evidence) is None


def test_restore_blocks_events_at_cut_and_ambiguous_coarse_timestamp():
    cutoff = dt.datetime(2026, 9, 27, 16, 30, 0, 500_000, tzinfo=dt.UTC)
    exact = _evidence(
        activity_events_near_snapshot=(
            BrokerTimelineEvent("at-cut", cutoff, resolution_nanoseconds=1_000),
        )
    )
    coarse = _evidence(
        activity_events_near_snapshot=(
            BrokerTimelineEvent(
                "coarse-ambiguous",
                cutoff.replace(microsecond=0),
                resolution_nanoseconds=1_000_000_000,
            ),
        )
    )

    for evidence in (exact, coarse):
        with pytest.raises(RestoreReconciliationError, match="activity after the snapshot"):
            reconcile_restore_snapshot(_snapshot(), evidence)


def test_restore_compares_fresh_order_price_for_an_open_owned_lot():
    from copytrading_engine.execution.domain.market import BrokerOrder
    from copytrading_engine.execution.domain.orders import OwnedLot

    created_at = dt.datetime.now(dt.UTC)
    client_id = "open-buy"
    order = OrderRecord(
        side="buy",
        position_intent="buy_to_open",
        type="limit",
        limit_price=Decimal("200"),
        symbol="AAPL",
        qty=Decimal("1"),
        source_price=Decimal("200"),
        entry_tolerance_pct=Decimal("0"),
        lot_id=None,
        entry_price=Decimal("200"),
        session=Session.REGULAR,
        client_id=client_id,
        message_id="source:1",
        instruction_index=0,
        source_key="source:1",
        status=OrderStatus.FILLED,
        filled_qty=Decimal("1"),
        broker_id="broker-buy",
        raw_broker_status="filled",
        created_at=created_at,
        day=created_at.date(),
    )
    lot = OwnedLot(
        symbol="AAPL",
        entry_price=Decimal("200"),
        source_key="source:1",
        original_qty=Decimal("1"),
        remaining_qty=Decimal("1"),
        average_price=Decimal("200"),
    )
    snapshot = _snapshot().model_copy(
        update={"orders": {client_id: order}, "lots": {client_id: lot}}
    )
    broker_order = BrokerOrder(
        id="broker-buy",
        client_order_id=client_id,
        symbol="AAPL",
        side="buy",
        qty=Decimal("1"),
        filled_qty=Decimal("1"),
        filled_avg_price=Decimal("201"),
        status="filled",
        position_intent="buy_to_open",
    )

    with pytest.raises(RestoreReconciliationError, match="price"):
        reconcile_restore_snapshot(
            snapshot,
            _evidence(
                positions={"AAPL": Decimal("1")},
                known_orders={client_id: broker_order},
            ),
        )


def test_restore_does_not_require_remote_history_for_closed_terminal_orders():
    created_at = dt.datetime.now(dt.UTC)
    client_id = "closed-old-order"
    order = OrderRecord(
        side="buy",
        position_intent="buy_to_open",
        type="limit",
        limit_price=Decimal("200"),
        symbol="AAPL",
        qty=Decimal("1"),
        source_price=Decimal("200"),
        entry_tolerance_pct=Decimal("0"),
        lot_id=None,
        entry_price=Decimal("200"),
        session=Session.REGULAR,
        client_id=client_id,
        message_id="source:1",
        instruction_index=0,
        source_key="source:1",
        status=OrderStatus.CANCELED,
        filled_qty=Decimal("0"),
        broker_id="broker-old",
        raw_broker_status="canceled",
        created_at=created_at,
        day=created_at.date(),
    )
    snapshot = _snapshot().model_copy(update={"orders": {client_id: order}})

    assert reconcile_restore_snapshot(snapshot, _evidence()) is None
