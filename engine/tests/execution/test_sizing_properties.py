"""Generated connections: the source fraction sizes an entry exactly once, in cents."""

from decimal import Decimal
from fractions import Fraction

from hypothesis import given
from hypothesis import strategies as st

from copytrading_engine.execution.domain.risk import BudgetDecision, requested_entry_budget
from copytrading_engine.execution.domain.sizing import RouteConnection

CENT = Decimal("0.01")


def asked(connection: RouteConnection, fraction: Decimal | None) -> BudgetDecision:
    return requested_entry_budget(connection, fraction, None, unsized_usd=None)


AMOUNTS = st.decimals(
    min_value=Decimal("0.01"), max_value=Decimal("1000000"), places=2, allow_nan=False
)
FRACTIONS = st.fractions(min_value=Fraction(1, 1000), max_value=1, max_denominator=1000).map(
    lambda value: Decimal(value.numerator) / Decimal(value.denominator)
)


def _connection(amount: Decimal) -> RouteConnection:
    return RouteConnection(account_id="paper", full_position_usd=amount)


@given(amount=AMOUNTS, fraction=FRACTIONS)
def test_a_share_is_the_fraction_of_the_full_position_rounded_down_to_the_cent(amount, fraction):
    decision = asked(_connection(amount), fraction)

    exact = amount * fraction
    if decision.budget is None:
        assert decision.reason == "below_minimum_budget"
        assert exact < CENT
        return
    assert exact - CENT < decision.budget <= exact + Decimal("1e-10")
    assert decision.budget <= amount
    assert decision.budget.as_tuple().exponent == -2


@given(amount=AMOUNTS, denominator=st.integers(min_value=1, max_value=20))
def test_n_shares_of_one_nth_never_pass_the_full_position(amount, denominator):
    share = asked(_connection(amount), Decimal(1) / denominator).budget

    assert share is None or denominator * share <= amount


@given(amount=AMOUNTS, smaller=FRACTIONS, larger=FRACTIONS)
def test_a_larger_share_never_buys_less(amount, smaller, larger):
    smaller, larger = sorted((smaller, larger))
    connection = _connection(amount)

    low = asked(connection, smaller).budget or Decimal(0)
    high = asked(connection, larger).budget or Decimal(0)

    assert low <= high


@given(amount=AMOUNTS, largest=AMOUNTS)
def test_a_call_with_no_size_buys_the_largest_single_buy_never_more_than_the_full_position(
    amount, largest
):
    connection = _connection(amount)

    decision = requested_entry_budget(connection, None, None, unsized_usd=largest)

    assert decision.budget == min(amount, largest)
