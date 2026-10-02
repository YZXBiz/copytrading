"""Finite order status mapping and transition rules."""

import pytest

from copytrading_engine.execution.adapters.alpaca.models import decode_broker_order
from copytrading_engine.execution.domain.order_lifecycle import (
    OrderStatus,
    is_cancelable,
    is_pending,
    is_terminal,
    map_broker_status,
    validate_transition,
)


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        ("new", OrderStatus.NEW),
        ("partially_filled", OrderStatus.PARTIALLY_FILLED),
        ("filled", OrderStatus.FILLED),
        ("done_for_day", OrderStatus.DONE_FOR_DAY),
        ("canceled", OrderStatus.CANCELED),
        ("expired", OrderStatus.EXPIRED),
        ("replaced", OrderStatus.REPLACED),
        ("pending_cancel", OrderStatus.PENDING_CANCEL),
        ("pending_replace", OrderStatus.PENDING_REPLACE),
        ("accepted", OrderStatus.ACCEPTED),
        ("pending_new", OrderStatus.PENDING_NEW),
        ("accepted_for_bidding", OrderStatus.ACCEPTED_FOR_BIDDING),
        ("stopped", OrderStatus.STOPPED),
        ("rejected", OrderStatus.REJECTED),
        ("suspended", OrderStatus.SUSPENDED),
        ("calculated", OrderStatus.CALCULATED),
        ("held", OrderStatus.HELD),
    ],
)
def test_documented_broker_statuses_map_to_finite_internal_status(raw, expected):
    assert map_broker_status(raw) is expected


def test_unknown_broker_status_is_preserved_but_reserved_and_not_cancelable():
    raw = "future_vendor_state"
    order = decode_broker_order(
        {
            "id": "broker-1",
            "client_order_id": "client-1",
            "symbol": "ABC",
            "side": "buy",
            "qty": "4",
            "filled_qty": "0",
            "filled_avg_price": None,
            "status": raw,
        }
    )

    assert order.status == raw
    assert map_broker_status(raw) is OrderStatus.UNRECOGNIZED
    assert is_pending(OrderStatus.UNRECOGNIZED)
    assert not is_terminal(OrderStatus.UNRECOGNIZED)
    assert not is_cancelable(OrderStatus.UNRECOGNIZED)


def test_released_intent_frees_pending_slot_and_is_not_cancelable():
    assert not is_pending(OrderStatus.RELEASED_UNSUBMITTED)
    assert is_terminal(OrderStatus.RELEASED_UNSUBMITTED)
    assert not is_cancelable(OrderStatus.RELEASED_UNSUBMITTED)


def test_calculated_order_stays_pending_for_reconciliation_but_is_not_cancelable():
    assert is_pending(OrderStatus.CALCULATED)
    assert not is_terminal(OrderStatus.CALCULATED)
    assert not is_cancelable(OrderStatus.CALCULATED)


def test_unknown_status_can_recover_to_a_known_broker_status():
    validate_transition(OrderStatus.UNRECOGNIZED, OrderStatus.NEW)


def test_terminal_order_cannot_transition_back_to_working():
    with pytest.raises(ValueError, match="transition"):
        validate_transition(OrderStatus.FILLED, OrderStatus.NEW)


def test_filled_order_may_transition_to_calculated():
    validate_transition(OrderStatus.FILLED, OrderStatus.CALCULATED)
