"""Finite internal order states and guarded lifecycle transitions."""

from enum import StrEnum


class OrderStatus(StrEnum):
    """Local intent and Alpaca order states understood by the executor."""

    PREPARED = "prepared"
    UNCERTAIN = "uncertain"
    ABORTED_BEFORE_SUBMIT = "aborted_before_submit"
    RELEASED_UNSUBMITTED = "released_unsubmitted"

    ACCEPTED = "accepted"
    PENDING_NEW = "pending_new"
    ACCEPTED_FOR_BIDDING = "accepted_for_bidding"
    NEW = "new"
    PARTIALLY_FILLED = "partially_filled"
    PENDING_CANCEL = "pending_cancel"
    PENDING_REPLACE = "pending_replace"
    STOPPED = "stopped"
    SUSPENDED = "suspended"
    HELD = "held"
    DONE_FOR_DAY = "done_for_day"

    FILLED = "filled"
    CANCELED = "canceled"
    EXPIRED = "expired"
    REPLACED = "replaced"
    REJECTED = "rejected"
    CALCULATED = "calculated"
    UNRECOGNIZED = "unrecognized"


_BROKER_STATUSES = frozenset(
    {
        OrderStatus.ACCEPTED,
        OrderStatus.PENDING_NEW,
        OrderStatus.ACCEPTED_FOR_BIDDING,
        OrderStatus.NEW,
        OrderStatus.PARTIALLY_FILLED,
        OrderStatus.PENDING_CANCEL,
        OrderStatus.PENDING_REPLACE,
        OrderStatus.STOPPED,
        OrderStatus.SUSPENDED,
        OrderStatus.HELD,
        OrderStatus.DONE_FOR_DAY,
        OrderStatus.FILLED,
        OrderStatus.CANCELED,
        OrderStatus.EXPIRED,
        OrderStatus.REPLACED,
        OrderStatus.REJECTED,
        OrderStatus.CALCULATED,
    }
)

_PENDING = frozenset(
    {
        OrderStatus.PREPARED,
        OrderStatus.UNCERTAIN,
        OrderStatus.ACCEPTED,
        OrderStatus.PENDING_NEW,
        OrderStatus.ACCEPTED_FOR_BIDDING,
        OrderStatus.NEW,
        OrderStatus.PARTIALLY_FILLED,
        OrderStatus.PENDING_CANCEL,
        OrderStatus.PENDING_REPLACE,
        OrderStatus.STOPPED,
        OrderStatus.SUSPENDED,
        OrderStatus.HELD,
        OrderStatus.DONE_FOR_DAY,
        OrderStatus.CALCULATED,
        OrderStatus.UNRECOGNIZED,
    }
)

_TERMINAL = frozenset(
    {
        OrderStatus.ABORTED_BEFORE_SUBMIT,
        OrderStatus.RELEASED_UNSUBMITTED,
        OrderStatus.FILLED,
        OrderStatus.CANCELED,
        OrderStatus.EXPIRED,
        OrderStatus.REPLACED,
        OrderStatus.REJECTED,
    }
)

# A pending status does not always mean another cancel request is useful or safe.
# In particular, unknown states and requests already pending replacement stay put.
_CANCELABLE = frozenset(
    {
        OrderStatus.ACCEPTED,
        OrderStatus.PENDING_NEW,
        OrderStatus.ACCEPTED_FOR_BIDDING,
        OrderStatus.NEW,
        OrderStatus.PARTIALLY_FILLED,
        OrderStatus.STOPPED,
        OrderStatus.SUSPENDED,
        OrderStatus.HELD,
        OrderStatus.DONE_FOR_DAY,
    }
)

_BROKER_TRANSITIONS: dict[OrderStatus, frozenset[OrderStatus]] = {
    OrderStatus.ACCEPTED: frozenset(
        {
            OrderStatus.PENDING_NEW,
            OrderStatus.ACCEPTED_FOR_BIDDING,
            OrderStatus.NEW,
            OrderStatus.PARTIALLY_FILLED,
            OrderStatus.PENDING_CANCEL,
            OrderStatus.PENDING_REPLACE,
            OrderStatus.STOPPED,
            OrderStatus.SUSPENDED,
            OrderStatus.HELD,
            OrderStatus.DONE_FOR_DAY,
            OrderStatus.FILLED,
            OrderStatus.CANCELED,
            OrderStatus.EXPIRED,
            OrderStatus.REPLACED,
            OrderStatus.REJECTED,
            OrderStatus.CALCULATED,
        }
    ),
    OrderStatus.PENDING_NEW: frozenset(
        {
            OrderStatus.ACCEPTED,
            OrderStatus.ACCEPTED_FOR_BIDDING,
            OrderStatus.NEW,
            OrderStatus.PARTIALLY_FILLED,
            OrderStatus.PENDING_CANCEL,
            OrderStatus.PENDING_REPLACE,
            OrderStatus.STOPPED,
            OrderStatus.SUSPENDED,
            OrderStatus.HELD,
            OrderStatus.DONE_FOR_DAY,
            OrderStatus.FILLED,
            OrderStatus.CANCELED,
            OrderStatus.EXPIRED,
            OrderStatus.REPLACED,
            OrderStatus.REJECTED,
            OrderStatus.CALCULATED,
        }
    ),
    OrderStatus.ACCEPTED_FOR_BIDDING: frozenset(
        {
            OrderStatus.NEW,
            OrderStatus.PARTIALLY_FILLED,
            OrderStatus.PENDING_CANCEL,
            OrderStatus.PENDING_REPLACE,
            OrderStatus.STOPPED,
            OrderStatus.SUSPENDED,
            OrderStatus.HELD,
            OrderStatus.DONE_FOR_DAY,
            OrderStatus.FILLED,
            OrderStatus.CANCELED,
            OrderStatus.EXPIRED,
            OrderStatus.REPLACED,
            OrderStatus.REJECTED,
            OrderStatus.CALCULATED,
        }
    ),
    OrderStatus.NEW: frozenset(
        {
            OrderStatus.PARTIALLY_FILLED,
            OrderStatus.PENDING_CANCEL,
            OrderStatus.PENDING_REPLACE,
            OrderStatus.STOPPED,
            OrderStatus.SUSPENDED,
            OrderStatus.HELD,
            OrderStatus.DONE_FOR_DAY,
            OrderStatus.FILLED,
            OrderStatus.CANCELED,
            OrderStatus.EXPIRED,
            OrderStatus.REPLACED,
            OrderStatus.REJECTED,
            OrderStatus.CALCULATED,
        }
    ),
    OrderStatus.PARTIALLY_FILLED: frozenset(
        {
            OrderStatus.PENDING_CANCEL,
            OrderStatus.PENDING_REPLACE,
            OrderStatus.STOPPED,
            OrderStatus.SUSPENDED,
            OrderStatus.HELD,
            OrderStatus.DONE_FOR_DAY,
            OrderStatus.FILLED,
            OrderStatus.CANCELED,
            OrderStatus.EXPIRED,
            OrderStatus.REPLACED,
            OrderStatus.REJECTED,
            OrderStatus.CALCULATED,
        }
    ),
    OrderStatus.PENDING_CANCEL: frozenset(
        {
            OrderStatus.PARTIALLY_FILLED,
            OrderStatus.FILLED,
            OrderStatus.CANCELED,
            OrderStatus.EXPIRED,
            OrderStatus.REPLACED,
            OrderStatus.REJECTED,
        }
    ),
    OrderStatus.PENDING_REPLACE: frozenset(
        {
            OrderStatus.NEW,
            OrderStatus.PARTIALLY_FILLED,
            OrderStatus.PENDING_CANCEL,
            OrderStatus.STOPPED,
            OrderStatus.SUSPENDED,
            OrderStatus.HELD,
            OrderStatus.DONE_FOR_DAY,
            OrderStatus.FILLED,
            OrderStatus.CANCELED,
            OrderStatus.EXPIRED,
            OrderStatus.REPLACED,
            OrderStatus.REJECTED,
            OrderStatus.CALCULATED,
        }
    ),
    OrderStatus.STOPPED: frozenset(
        {
            OrderStatus.PARTIALLY_FILLED,
            OrderStatus.PENDING_CANCEL,
            OrderStatus.PENDING_REPLACE,
            OrderStatus.SUSPENDED,
            OrderStatus.DONE_FOR_DAY,
            OrderStatus.FILLED,
            OrderStatus.CANCELED,
            OrderStatus.EXPIRED,
            OrderStatus.REPLACED,
            OrderStatus.REJECTED,
            OrderStatus.CALCULATED,
        }
    ),
    OrderStatus.SUSPENDED: frozenset(
        {
            OrderStatus.NEW,
            OrderStatus.PARTIALLY_FILLED,
            OrderStatus.PENDING_CANCEL,
            OrderStatus.PENDING_REPLACE,
            OrderStatus.HELD,
            OrderStatus.DONE_FOR_DAY,
            OrderStatus.FILLED,
            OrderStatus.CANCELED,
            OrderStatus.EXPIRED,
            OrderStatus.REPLACED,
            OrderStatus.REJECTED,
            OrderStatus.CALCULATED,
        }
    ),
    OrderStatus.HELD: frozenset(
        {
            OrderStatus.NEW,
            OrderStatus.PARTIALLY_FILLED,
            OrderStatus.PENDING_CANCEL,
            OrderStatus.PENDING_REPLACE,
            OrderStatus.STOPPED,
            OrderStatus.SUSPENDED,
            OrderStatus.DONE_FOR_DAY,
            OrderStatus.FILLED,
            OrderStatus.CANCELED,
            OrderStatus.EXPIRED,
            OrderStatus.REPLACED,
            OrderStatus.REJECTED,
            OrderStatus.CALCULATED,
        }
    ),
    OrderStatus.DONE_FOR_DAY: frozenset(
        {
            OrderStatus.NEW,
            OrderStatus.PARTIALLY_FILLED,
            OrderStatus.PENDING_CANCEL,
            OrderStatus.PENDING_REPLACE,
            OrderStatus.STOPPED,
            OrderStatus.SUSPENDED,
            OrderStatus.HELD,
            OrderStatus.FILLED,
            OrderStatus.CANCELED,
            OrderStatus.EXPIRED,
            OrderStatus.REPLACED,
            OrderStatus.REJECTED,
            OrderStatus.CALCULATED,
        }
    ),
    OrderStatus.CALCULATED: frozenset(
        {
            OrderStatus.NEW,
            OrderStatus.PARTIALLY_FILLED,
            OrderStatus.PENDING_CANCEL,
            OrderStatus.PENDING_REPLACE,
            OrderStatus.STOPPED,
            OrderStatus.SUSPENDED,
            OrderStatus.HELD,
            OrderStatus.DONE_FOR_DAY,
            OrderStatus.FILLED,
            OrderStatus.CANCELED,
            OrderStatus.EXPIRED,
            OrderStatus.REPLACED,
            OrderStatus.REJECTED,
        }
    ),
}


def map_broker_status(raw_status: str) -> OrderStatus:
    """Map a vendor string into the finite internal status vocabulary."""
    try:
        status = OrderStatus(raw_status)
    except ValueError:
        return OrderStatus.UNRECOGNIZED
    return status if status in _BROKER_STATUSES else OrderStatus.UNRECOGNIZED


def is_pending(status: OrderStatus) -> bool:
    return OrderStatus(status) in _PENDING


def is_terminal(status: OrderStatus) -> bool:
    return OrderStatus(status) in _TERMINAL


def is_cancelable(status: OrderStatus) -> bool:
    return OrderStatus(status) in _CANCELABLE


def is_valid_transition(previous: OrderStatus, current: OrderStatus) -> bool:
    previous = OrderStatus(previous)
    current = OrderStatus(current)
    if previous == current:
        return True
    if previous in {OrderStatus.PREPARED, OrderStatus.UNCERTAIN}:
        return (
            current in _BROKER_STATUSES | {OrderStatus.UNRECOGNIZED}
            or (
                previous == OrderStatus.PREPARED
                and current in {OrderStatus.UNCERTAIN, OrderStatus.ABORTED_BEFORE_SUBMIT}
            )
            or (previous == OrderStatus.UNCERTAIN and current == OrderStatus.RELEASED_UNSUBMITTED)
        )
    if previous == OrderStatus.RELEASED_UNSUBMITTED:
        return current in _BROKER_STATUSES | {OrderStatus.UNRECOGNIZED}
    if previous == OrderStatus.UNRECOGNIZED:
        return current in _BROKER_STATUSES | {OrderStatus.UNRECOGNIZED}
    if current == OrderStatus.UNRECOGNIZED and previous in _BROKER_STATUSES:
        return True
    if previous == OrderStatus.FILLED and current == OrderStatus.CALCULATED:
        return True
    if is_terminal(previous):
        return False
    if previous in _BROKER_TRANSITIONS:
        return current in _BROKER_TRANSITIONS[previous] | {OrderStatus.UNRECOGNIZED}
    return False


def validate_transition(previous: OrderStatus, current: OrderStatus) -> None:
    """Raise when an order attempts a lifecycle transition the broker cannot make."""
    previous = OrderStatus(previous)
    current = OrderStatus(current)
    if not is_valid_transition(previous, current):
        raise ValueError(f"Illegal order status transition: {previous.value} -> {current.value}")
