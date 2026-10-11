"""How a broker count splits between copied lots and the owner's own shares (ADR-0011)."""

from decimal import Decimal

import pytest

from copytrading_engine.execution.domain.ownership import allocate, sync_reason

LOTS = [("first", Decimal("3")), ("second", Decimal("2"))]


def test_extra_shares_at_the_broker_are_the_owners_and_copied_lots_keep_theirs():
    allocation = allocate(Decimal("7"), LOTS)
    assert allocation.lot_remaining == {"first": Decimal("3"), "second": Decimal("2")}
    assert allocation.external_qty == Decimal("2")


def test_a_shortfall_takes_the_oldest_buys_first():
    allocation = allocate(Decimal("1"), LOTS)
    assert allocation.lot_remaining == {"first": Decimal("0"), "second": Decimal("1")}
    assert allocation.external_qty == 0


def test_the_order_given_is_the_order_taken():
    allocation = allocate(Decimal("4"), list(reversed(LOTS)))
    assert allocation.lot_remaining == {"second": Decimal("1"), "first": Decimal("3")}


@pytest.mark.parametrize(
    ("broker", "expected", "copied", "reason"),
    [
        ("5", "5", "5", "broker_matches_again"),
        ("6", "5", "5", "owner_bought_outside"),
        ("5", "8", "5", "owner_sold_own_shares"),
        ("4", "8", "5", "owner_sold_copied_shares"),
    ],
)
def test_each_settle_says_what_the_owner_did(broker, expected, copied, reason):
    assert sync_reason(Decimal(broker), Decimal(expected), Decimal(copied)) == reason
