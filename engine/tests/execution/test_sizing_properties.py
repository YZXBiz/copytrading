"""Generated connections: the source fraction sizes an entry exactly once, in cents."""

from decimal import Decimal
from fractions import Fraction

from hypothesis import given
from hypothesis import strategies as st

from copytrading_engine.execution.domain.risk import requested_entry_budget
from copytrading_engine.execution.domain.sizing import RouteConnection

CENT = Decimal("0.01")
HALF_CENT = Decimal("0.005")
AMOUNTS = st.decimals(
    min_value=Decimal("0.01"), max_value=Decimal("1000000"), places=2, allow_nan=False
)
FRACTIONS = st.fractions(min_value=Fraction(1, 1000), max_value=1, max_denominator=1000).map(
    lambda value: Decimal(value.numerator) / Decimal(value.denominator)
)


def _connection(mode: str, amount: Decimal, default: Decimal | None = None) -> RouteConnection:
    return RouteConnection(
        account_id="paper", mode=mode, amount_usd=amount, default_fraction=default
    )


@given(amount=AMOUNTS, fraction=st.none() | FRACTIONS)
def test_fixed_sizing_ignores_any_source_fraction(amount, fraction):
    decision = requested_entry_budget(_connection("fixed", amount), fraction)

    assert decision.budget == amount


@given(amount=AMOUNTS, fraction=FRACTIONS)
def test_proportional_sizing_applies_the_fraction_once_in_cents(amount, fraction):
    decision = requested_entry_budget(_connection("proportional", amount), fraction)

    exact = amount * fraction
    if decision.budget is None:
        assert decision.reason == "below_minimum_budget"
        assert exact <= HALF_CENT
        return
    assert abs(decision.budget - exact) <= HALF_CENT
    assert decision.budget <= amount
    assert decision.budget.as_tuple().exponent == -2


@given(amount=AMOUNTS, smaller=FRACTIONS, larger=FRACTIONS)
def test_proportional_sizing_never_decreases_as_the_fraction_grows(amount, smaller, larger):
    smaller, larger = sorted((smaller, larger))
    connection = _connection("proportional", amount)

    low = requested_entry_budget(connection, smaller).budget or Decimal(0)
    high = requested_entry_budget(connection, larger).budget or Decimal(0)

    assert low <= high


@given(amount=AMOUNTS, default=FRACTIONS)
def test_missing_fraction_uses_only_the_configured_default(amount, default):
    with_default = _connection("proportional", amount, default)

    assert requested_entry_budget(with_default, None) == requested_entry_budget(
        with_default, default
    )
    missing = requested_entry_budget(_connection("proportional", amount), None)
    assert missing.budget is None
    assert missing.reason == "missing_source_fraction_review"
