"""Budget policy tests need no broker, ledger, or signal/configuration parser."""

from dataclasses import dataclass, replace
from decimal import Decimal

import pytest
from hypothesis import given
from hypothesis import strategies as st

from copytrading_engine.execution.domain.risk import (
    EntryFacts,
    entry_budget,
    requested_entry_budget,
)
from copytrading_engine.execution.domain.sizing import RouteConnection


@dataclass(frozen=True)
class Limits:
    max_order_usd: Decimal = Decimal(100)
    max_symbol_usd: Decimal = Decimal(600)
    max_total_usd: Decimal = Decimal(2500)
    daily_loss_cap_usd: Decimal = Decimal(250)
    max_entries_per_day: int = 30


FACTS = EntryFacts(
    symbol_exposure=Decimal(0),
    total_exposure=Decimal(0),
    cash=Decimal(5000),
    buying_power=Decimal(5000),
    equity=Decimal(5000),
    last_equity=Decimal(5000),
    entries_today=0,
    account_active=True,
)
FIXED = RouteConnection(account_id="paper-demo", mode="fixed", amount_usd=Decimal(100))


def decide(limits=None, facts=FACTS, connection=FIXED, fraction=None):
    return entry_budget(limits or Limits(), facts, connection, fraction)


@pytest.mark.parametrize(
    ("changes", "reason"),
    [
        ({"account_active": False}, "account_blocked"),
        ({"equity": Decimal(4750)}, "daily_loss_cap"),
        ({"entries_today": 30}, "daily_entry_cap"),
        ({"symbol_exposure": Decimal("500.01")}, "symbol_exposure_cap"),
        ({"total_exposure": Decimal("2400.01")}, "total_exposure_cap"),
        ({"cash": Decimal("99.99")}, "insufficient_cash"),
        ({"buying_power": Decimal("99.99")}, "insufficient_cash"),
    ],
)
def test_rejected_budget_has_no_spendable_amount(changes, reason):
    decision = decide(facts=replace(FACTS, **changes))
    assert decision.budget is None
    assert decision.reason == reason


def test_exact_exposure_and_cash_caps_allow_the_budget():
    facts = replace(
        FACTS,
        symbol_exposure=Decimal(500),
        total_exposure=Decimal(2400),
        cash=Decimal(100),
        buying_power=Decimal(100),
    )
    assert decide(facts=facts).budget == Decimal(100)


def test_both_exposure_caps_report_current_proposed_and_limit():
    facts = replace(FACTS, symbol_exposure=Decimal("550"), total_exposure=Decimal("2450"))
    decision = decide(facts=facts)
    assert decision.reason == "symbol_and_total_exposure_cap"
    assert [(b.scope, b.current, b.proposed, b.limit) for b in decision.breaches] == [
        ("symbol", Decimal(550), Decimal(100), Decimal(600)),
        ("total", Decimal(2450), Decimal(100), Decimal(2500)),
    ]


@given(
    alert_cents=st.integers(min_value=1, max_value=60000),
    order_cents=st.integers(min_value=1, max_value=60000),
    fraction_denominator=st.integers(min_value=1, max_value=20),
)
def test_approved_budget_respects_connection_amount_and_order_cap(
    alert_cents, order_cents, fraction_denominator
):
    limits = Limits(
        max_order_usd=Decimal(order_cents) / 100,
    )
    connection = RouteConnection(
        account_id="paper-demo", mode="proportional", amount_usd=Decimal(alert_cents) / 100
    )
    decision = decide(limits, connection=connection, fraction=Decimal(1) / fraction_denominator)
    if decision.reason == "below_minimum_budget":
        assert decision.budget is None
        return
    assert decision.budget is not None
    assert 0 < decision.budget <= limits.max_order_usd
    assert decision.budget <= connection.amount_usd


def test_fixed_ignores_source_fraction_and_proportional_applies_once():
    limits = Limits(
        max_order_usd=Decimal(5000), max_symbol_usd=Decimal(5000), max_total_usd=Decimal(5000)
    )
    fixed = RouteConnection(account_id="a", mode="fixed", amount_usd=Decimal(500))
    proportional = RouteConnection(account_id="b", mode="proportional", amount_usd=Decimal(3000))
    assert decide(limits, connection=fixed, fraction=Decimal(1) / 6).budget == Decimal("500.00")
    assert decide(limits, connection=fixed, fraction=Decimal(1) / 3).budget == Decimal("500.00")
    assert decide(limits, connection=proportional, fraction=Decimal(1) / 6).budget == Decimal(
        "500.00"
    )
    assert decide(limits, connection=proportional, fraction=Decimal(1) / 3).budget == Decimal(
        "1000.00"
    )


def test_read_only_requested_budget_uses_destination_terms_without_account_facts():
    fixed = RouteConnection(account_id="a", mode="fixed", amount_usd=Decimal(500))
    proportional = RouteConnection(account_id="b", mode="proportional", amount_usd=Decimal(3000))

    assert requested_entry_budget(fixed, Decimal(1) / 6).budget == Decimal("500.00")
    assert requested_entry_budget(proportional, Decimal(1) / 6).budget == Decimal("500.00")
    assert requested_entry_budget(proportional, None).reason == "missing_source_fraction_review"


def test_missing_fraction_requires_explicit_default_for_proportional():
    connection = RouteConnection(account_id="b", mode="proportional", amount_usd=Decimal(3000))
    limits = Limits(
        max_order_usd=Decimal(5000), max_symbol_usd=Decimal(5000), max_total_usd=Decimal(5000)
    )
    assert decide(limits, connection=connection).reason == "missing_source_fraction_review"
    configured = connection.model_copy(update={"default_fraction": Decimal(1) / 6})
    assert decide(limits, connection=configured).budget == Decimal("500.00")
