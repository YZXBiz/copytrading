"""Generated manual sales: any accepted ownership resolution conserves broker quantity."""

import datetime as dt
from decimal import Decimal

import pytest
from hypothesis import assume, given, settings
from hypothesis import strategies as st
from pydantic import ValidationError

from copytrading_engine.execution.application.recovery import RecoveryApplication
from copytrading_engine.execution.domain.market import BrokerOrder
from copytrading_engine.execution.domain.ownership import OwnershipResolutionRequest
from copytrading_engine.execution.domain.recovery import ManualSale

from .builders import NOW, mixed_account

EXTERNAL = Decimal("100")
MICRO = Decimal("0.000001")
UNITS = st.integers(min_value=1, max_value=150_000_000)


def _sell_manually(units: int):
    _, broker, engine = mixed_account()
    owned = engine.ledger.owned("ABC")
    sold = MICRO * units
    assume(sold <= owned + EXTERNAL)
    order = BrokerOrder(
        id="manual-sale",
        client_order_id="manual-sale-client",
        symbol="ABC",
        side="sell",
        qty=sold,
        filled_qty=sold,
        filled_avg_price=Decimal("25"),
        status="filled",
    )
    broker.orders[order.client_order_id] = order.model_dump(mode="json")
    broker.holdings["ABC"] -= sold
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
    return broker, engine, app, owned, sold


def _request(engine, broker_qty: Decimal, external: Decimal, remaining: Decimal):
    lot_id = next(iter(engine.ledger.snapshot().lots))
    return OwnershipResolutionRequest(
        resolution_id="resolution-generated",
        incident_id="manual-sale",
        account_id="paper-demo",
        symbol="ABC",
        actor="operator",
        reason="generated allocation",
        broker_qty=broker_qty,
        external_qty=external,
        lot_remaining={lot_id: remaining},
    )


@settings(max_examples=40, deadline=None)
@given(units=UNITS, external_share=st.integers(min_value=0, max_value=1_000_000))
def test_any_conserving_allocation_resolves_to_the_broker_quantity(units, external_share):
    broker, engine, app, owned, sold = _sell_manually(units)
    external_sold_min = max(Decimal(0), sold - owned)
    external_sold_max = min(sold, EXTERNAL)
    external_sold = external_sold_min + (
        (external_sold_max - external_sold_min) * external_share / 1_000_000
    ).quantize(MICRO)
    external = EXTERNAL - external_sold
    remaining = owned - (sold - external_sold)
    broker_qty = broker.holdings["ABC"]

    result = app.resolve_ownership(_request(engine, broker_qty, external, remaining))

    assert result.external_qty == external
    assert engine.ledger.owned("ABC") + external == broker_qty
    assert engine.ledger.snapshot().external_positions["ABC"].qty == external


@settings(max_examples=40, deadline=None)
@given(units=UNITS, drift=st.integers(min_value=1, max_value=1_000_000))
def test_non_conserving_allocation_is_rejected_without_changing_the_ledger(units, drift):
    broker, engine, app, owned, sold = _sell_manually(units)
    external = max(Decimal(0), EXTERNAL - sold)
    remaining = owned - (sold - (EXTERNAL - external))
    assume(remaining >= 0)
    before = engine.ledger.snapshot()

    with pytest.raises(ValidationError, match="quantity conservation failed"):
        app.resolve_ownership(
            _request(engine, broker.holdings["ABC"], external + MICRO * drift, remaining)
        )

    assert engine.ledger.snapshot() == before


@settings(max_examples=40, deadline=None)
@given(units=UNITS, invented=st.integers(min_value=1, max_value=100_000_000))
def test_allocation_cannot_move_external_shares_into_app_lots(units, invented):
    broker, engine, app, owned, _ = _sell_manually(units)
    broker_qty = broker.holdings["ABC"]
    remaining = owned + MICRO * invented
    external = broker_qty - remaining
    assume(external >= 0)
    before = engine.ledger.snapshot()

    with pytest.raises(ValueError, match="invent"):
        app.resolve_ownership(_request(engine, broker_qty, external, remaining))

    assert engine.ledger.snapshot() == before
