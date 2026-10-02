"""Domain values accept exact types; only JSON boundaries convert text to numbers and times."""

import datetime as dt
from decimal import Decimal

import pytest
from pydantic import ValidationError

from copytrading_engine.execution.domain.ownership import ExternalPosition, OwnershipIncident


@pytest.mark.parametrize("qty", [0.1, "0.1", 1e-7, True])
def test_domain_quantities_reject_floats_strings_and_bools(qty):
    with pytest.raises(ValidationError):
        ExternalPosition(symbol="ABC", qty=qty)


@pytest.mark.parametrize("revision", [True, 1.0, "1"])
def test_domain_integers_reject_bools_floats_and_strings(revision):
    with pytest.raises(ValidationError):
        ExternalPosition(symbol="ABC", qty=Decimal(1), allocation_revision=revision)


def test_json_boundary_converts_text_to_exact_decimals():
    position = ExternalPosition.model_validate_json(
        '{"symbol":"ABC","qty":"0.30000000000000004","allocation_revision":2}'
    )

    assert position.qty == Decimal("0.30000000000000004")
    assert position.allocation_revision == 2


def test_python_callers_cannot_pass_text_timestamps_or_amounts():
    observed_at = dt.datetime(2026, 9, 28, 14, 0, tzinfo=dt.UTC)
    fields = {
        "incident_id": "incident-1",
        "symbol": "ABC",
        "expected_qty": Decimal(10),
        "actual_qty": Decimal(9),
        "observed_at": observed_at,
        "cause": "manual_sale",
    }

    assert OwnershipIncident(**fields).observed_at == observed_at
    with pytest.raises(ValidationError):
        OwnershipIncident(**fields | {"observed_at": observed_at.isoformat()})
    with pytest.raises(ValidationError):
        OwnershipIncident(**fields | {"actual_qty": "9"})
