"""The app sizes its examples with its own copy of the rule; both must agree on every example."""

from decimal import Decimal

import pytest

from copytrading_engine.execution.domain.risk import requested_entry_budget
from copytrading_engine.execution.domain.sizing import RouteConnection

from ..contracts import contract

EXAMPLES = contract("sizing-examples.json")["examples"]


@pytest.mark.parametrize("example", EXAMPLES, ids=[example["case"] for example in EXAMPLES])
def test_the_engine_sizes_every_shared_example(example):
    connection = RouteConnection(
        account_id="paper",
        full_position_usd=Decimal(example["full_position_usd"]),
    )
    fraction = example["fraction"]
    source = (
        None
        if fraction is None
        else Decimal(fraction["numerator"]) / Decimal(fraction["denominator"])
    )

    budget = requested_entry_budget(connection, source).budget

    expected = example["budget_usd"]
    assert budget == (None if expected is None else Decimal(expected))
