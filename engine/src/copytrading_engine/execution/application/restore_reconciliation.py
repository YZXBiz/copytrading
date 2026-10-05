"""Read-only broker evidence required before activating a restored ledger."""

from __future__ import annotations

from decimal import Decimal

from copytrading_engine.execution.application.ports import BrokerRestoreEvidence
from copytrading_engine.execution.domain.ledger_state import LedgerSnapshot
from copytrading_engine.execution.domain.order_lifecycle import OrderStatus, map_broker_status


class RestoreReconciliationError(ValueError):
    """A restored account cannot be activated from incomplete or changed evidence."""


def reconcile_restore_snapshot(
    snapshot: LedgerSnapshot,
    evidence: BrokerRestoreEvidence,
) -> None:
    """Require active identity, open-lot attribution, holdings, and activity evidence.

    Any returned order or activity at/after the archived timestamp blocks
    activation. The bounded broker queries are not a complete external order
    history: an external order submitted and canceled unfilled before the cut can
    be absent from both the current open-order set and the post-cut cursor. That
    case has no position or future ownership effect and is accepted. App-owned
    unresolved intents, current open orders, changed holdings, and observed
    post-cut activity still block activation. This also catches a filled-and-
    closed round trip whose current net position is unchanged. Only orders backing
    lots that remain open are re-read for future sell attribution.
    """
    if not evidence.complete:
        raise RestoreReconciliationError("complete broker activity evidence is unavailable")
    if snapshot.account_id is None or snapshot.environment is None:
        raise RestoreReconciliationError("restored broker identity is incomplete")
    if not evidence.account.active:
        raise RestoreReconciliationError("broker account is not active and tradable")
    if (evidence.account.id, evidence.environment) != (
        snapshot.account_id,
        snapshot.environment,
    ):
        raise RestoreReconciliationError("broker account identity does not match the restore")
    if evidence.orders_after_snapshot or evidence.activity_ids_after_snapshot:
        raise RestoreReconciliationError("broker activity after the snapshot blocks restore")
    if evidence.open_order_client_ids:
        raise RestoreReconciliationError("open broker orders block restore activation")
    if snapshot.entry_halted or any(
        not incident.resolved for incident in snapshot.ownership_incidents.values()
    ):
        raise RestoreReconciliationError("saved account contains unresolved broker evidence")

    for _, order in snapshot.orders.items():
        if order.status == OrderStatus.ABORTED_BEFORE_SUBMIT:
            if order.broker_id is not None:
                raise RestoreReconciliationError("aborted order has an uncertain broker identity")
            continue
        if order.pending or order.status == OrderStatus.RELEASED_UNSUBMITTED:
            raise RestoreReconciliationError("saved order intent is unresolved")
        if order.broker_id is None:
            raise RestoreReconciliationError("saved order has an uncertain broker identity")

    for lot_id, lot in snapshot.lots.items():
        if lot.remaining_qty <= 0:
            continue
        for entry in lot.entries(lot_id):
            order = snapshot.orders.get(entry)
            broker_order = evidence.known_orders.get(entry)
            if order is None or broker_order is None:
                raise RestoreReconciliationError(
                    "open owned lot is missing fresh broker order evidence"
                )
            # A lot of one buy carries that buy's average; a joined lot checks each buy's own.
            average = lot.average_price if not lot.joined_entries else order.filled_avg_price
            if (
                order.side != "buy"
                or order.broker_id is None
                or broker_order.id != order.broker_id
                or broker_order.client_order_id != entry
                or broker_order.symbol != order.symbol
                or broker_order.side != order.side
                or broker_order.qty != order.qty
                or broker_order.filled_qty != order.filled_qty
                or broker_order.filled_avg_price != average
                or broker_order.position_intent != order.position_intent
                or map_broker_status(broker_order.status) != order.status
            ):
                raise RestoreReconciliationError(
                    "open owned lot differs from fresh broker order identity, quantity, status, "
                    "or price"
                )

    expected = _expected_positions(snapshot)
    actual = {symbol: quantity for symbol, quantity in evidence.positions.items() if quantity}
    if expected != actual:
        raise RestoreReconciliationError("broker holdings do not match the restored ledger")


def _expected_positions(snapshot: LedgerSnapshot) -> dict[str, Decimal]:
    expected: dict[str, Decimal] = {}
    for lot in snapshot.lots.values():
        expected[lot.symbol] = expected.get(lot.symbol, Decimal(0)) + lot.remaining_qty
    for position in snapshot.external_positions.values():
        expected[position.symbol] = expected.get(position.symbol, Decimal(0)) + position.qty
    return {symbol: quantity for symbol, quantity in expected.items() if quantity}
