"""The app sizes its examples with its own copy of the rule; both must agree on every example."""

from decimal import Decimal

import pytest

from copytrading_engine.execution.domain.risk import (
    EntryFacts,
    entry_budget,
    requested_entry_budget,
)
from copytrading_engine.execution.domain.signals import CopyConfig
from copytrading_engine.execution.domain.sizing import RouteConnection

from ..contracts import contract

EXAMPLES = contract("sizing-examples.json")["examples"]
CAPPED = [example for example in EXAMPLES if "max_order_usd" in example]


def _connection(example: dict) -> RouteConnection:
    return RouteConnection(
        account_id="paper",
        full_position_usd=Decimal(example["full_position_usd"]),
    )


def _source(example: dict) -> Decimal | None:
    fraction = example["fraction"]
    if fraction is None:
        return None
    return Decimal(fraction["numerator"]) / Decimal(fraction["denominator"])


@pytest.mark.parametrize("example", EXAMPLES, ids=[example["case"] for example in EXAMPLES])
def test_the_engine_sizes_every_shared_example(example):
    largest = example.get("max_order_usd")
    budget = requested_entry_budget(
        _connection(example),
        _source(example),
        None,
        unsized_usd=None if largest is None else Decimal(largest),
    ).budget

    expected = example["budget_usd"]
    assert budget == (None if expected is None else Decimal(expected))


@pytest.mark.parametrize("example", CAPPED, ids=[example["case"] for example in CAPPED])
def test_the_engine_spends_what_the_copy_sheet_shows_after_the_largest_single_buy(example):
    """The copy sheet's footer and button show `spent_usd`; the engine's plan spends the same."""
    limits = CopyConfig(
        sources=("discord:demo",),
        max_order_usd=Decimal(example["max_order_usd"]),
        max_symbol_usd=Decimal(100_000),
        max_total_usd=Decimal(100_000),
    )
    roomy = EntryFacts(
        symbol_exposure=Decimal(0),
        total_exposure=Decimal(0),
        cash=Decimal(100_000),
        buying_power=Decimal(100_000),
        equity=Decimal(100_000),
        last_equity=Decimal(100_000),
        entries_today=0,
        account_active=True,
    )

    decision = entry_budget(limits, roomy, _connection(example), _source(example))

    assert decision.budget == Decimal(example["spent_usd"])
    assert decision.requested == Decimal(example["budget_usd"])
