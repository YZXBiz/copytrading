"""Budget policy tests need no broker, ledger, or signal/configuration parser."""

from dataclasses import dataclass, replace
from decimal import Decimal

import pytest
from hypothesis import given
from hypothesis import strategies as st

from copytrading_engine.execution.domain.market import Position
from copytrading_engine.execution.domain.orders import OwnedLot
from copytrading_engine.execution.domain.risk import (
    EntryFacts,
    account_exposure,
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
FIXED = RouteConnection(account_id="paper-demo", full_position_usd=Decimal(100))


def decide(limits=None, facts=FACTS, connection=FIXED, fraction=None, usd=None):
    return entry_budget(limits or Limits(), facts, connection, fraction, usd)


@pytest.mark.parametrize(
    ("changes", "reason"),
    [
        ({"account_active": False}, "account_blocked"),
        ({"equity": Decimal(4750)}, "daily_loss_cap"),
        ({"entries_today": 30}, "daily_entry_cap"),
        # Less than Alpaca's $1 minimum left under a cap.
        ({"symbol_exposure": Decimal("599.01")}, "symbol_exposure_cap"),
        ({"total_exposure": Decimal("2499.01")}, "total_exposure_cap"),
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
    facts = replace(FACTS, symbol_exposure=Decimal("599.50"), total_exposure=Decimal("2499.50"))
    decision = decide(facts=facts)
    assert decision.reason == "symbol_and_total_exposure_cap"
    assert [(b.scope, b.current, b.proposed, b.limit) for b in decision.breaches] == [
        ("symbol", Decimal("599.50"), Decimal(100), Decimal(600)),
        ("total", Decimal("2499.50"), Decimal(100), Decimal(2500)),
    ]


@pytest.mark.parametrize(
    ("changes", "budget", "limit"),
    [
        pytest.param(
            {"symbol_exposure": Decimal(550)}, Decimal(50), "symbol_exposure_cap", id="stock"
        ),
        pytest.param(
            {"total_exposure": Decimal(2470)}, Decimal(30), "total_exposure_cap", id="total"
        ),
        pytest.param(
            {"symbol_exposure": Decimal(550), "total_exposure": Decimal(2480)},
            Decimal(20),
            "total_exposure_cap",
            id="the-tighter-of-both",
        ),
        pytest.param(
            {"symbol_exposure": Decimal(599)}, Decimal(1), "symbol_exposure_cap", id="one-dollar"
        ),
    ],
)
def test_a_cap_trims_a_buy_to_the_room_left_and_says_which(changes, budget, limit):
    decision = decide(facts=replace(FACTS, **changes))

    assert (decision.budget, decision.requested, decision.limited_by) == (
        budget,
        Decimal(100),
        limit,
    )
    assert decision.trimmed


def test_the_daily_loss_cap_still_refuses_outright():
    decision = decide(facts=replace(FACTS, equity=Decimal(4750), symbol_exposure=Decimal(0)))

    assert (decision.budget, decision.reason) == (None, "daily_loss_cap")


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
        account_id="paper-demo", full_position_usd=Decimal(alert_cents) / 100
    )
    decision = decide(limits, connection=connection, fraction=Decimal(1) / fraction_denominator)
    if decision.reason == "below_minimum_budget":
        assert decision.budget is None
        return
    assert decision.budget is not None
    assert 0 < decision.budget <= limits.max_order_usd
    assert decision.budget <= connection.full_position_usd


ROOMY = Limits(
    max_order_usd=Decimal(5000), max_symbol_usd=Decimal(5000), max_total_usd=Decimal(5000)
)
FULL_3000 = RouteConnection(account_id="b", full_position_usd=Decimal(3000))


@pytest.mark.parametrize(
    ("fraction", "budget"),
    [
        pytest.param(Decimal(1) / 6, Decimal("500.00"), id="a-sixth"),
        pytest.param(Decimal(1) / 3, Decimal("1000.00"), id="a-third"),
        pytest.param(Decimal("0.5"), Decimal("1500.00"), id="half"),
        pytest.param(None, Decimal("3000.00"), id="no-size-buys-the-full-position"),
    ],
)
def test_a_call_buys_its_share_of_the_full_position(fraction, budget):
    assert decide(ROOMY, connection=FULL_3000, fraction=fraction).budget == budget


def test_shares_round_down_so_six_sixths_never_pass_the_full_position():
    connection = RouteConnection(account_id="a", full_position_usd=Decimal(1000))

    sixth = decide(ROOMY, connection=connection, fraction=Decimal(1) / 6).budget

    assert sixth == Decimal("166.66")
    assert 6 * sixth <= connection.full_position_usd


def test_the_requested_budget_needs_no_account_facts():
    asked = requested_entry_budget(FULL_3000, Decimal(1) / 6, None, unsized_usd=Decimal(200))
    assert asked.budget == Decimal("500.00")
    # A call with no size buys the largest single buy, never more than the full position.
    assert requested_entry_budget(
        FULL_3000, None, None, unsized_usd=Decimal(200)
    ).budget == Decimal("200.00")
    assert requested_entry_budget(
        FULL_3000, None, None, unsized_usd=Decimal(9000)
    ).budget == Decimal("3000.00")
    # Without one, a preview says the call has no size, for the app to name the amount.
    assert requested_entry_budget(FULL_3000, None, None, unsized_usd=None).reason == "unsized_buy"


def test_a_call_with_no_size_buys_the_largest_single_buy_untrimmed():
    limits = Limits(max_order_usd=Decimal(200), max_symbol_usd=Decimal(1000))
    connection = RouteConnection(account_id="a", full_position_usd=Decimal(1000))

    decision = decide(limits, connection=connection)

    assert (decision.budget, decision.requested, decision.limited_by) == (
        Decimal(200),
        Decimal(200),
        None,
    )
    assert not decision.trimmed


def test_the_maximum_per_order_trims_a_buy_and_says_so():
    limits = Limits(max_order_usd=Decimal(100), max_symbol_usd=Decimal(600))
    connection = RouteConnection(account_id="a", full_position_usd=Decimal(600))

    decision = decide(limits, connection=connection, fraction=Decimal("0.5"))

    assert (decision.budget, decision.requested, decision.trimmed, decision.limited_by) == (
        Decimal(100),
        Decimal("300.00"),
        True,
        "largest_single_buy",
    )
    assert not decide(limits, connection=connection, fraction=Decimal(1) / 6).trimmed


def test_a_sold_lot_leaves_and_the_owners_own_shares_are_not_counted():
    sold = OwnedLot(
        symbol="PM",
        entry_price=Decimal("201"),
        source_key="copy-pm",
        original_qty=Decimal(1),
        remaining_qty=Decimal(0),
        average_price=Decimal("201.70"),
        entry_remaining={"copy-pm": Decimal(0)},
        entry_prices={"copy-pm": Decimal("201")},
    )
    outside = Position(
        symbol="CBRS",
        qty=Decimal(10),
        market_value=Decimal("2086"),
        currency="USD",
        asset_class="us_equity",
    )
    closed = Position(symbol="PM", qty=Decimal(0), currency="USD", asset_class="us_equity")

    exposure = account_exposure((outside, closed), (sold,), (), account_currency="USD")

    # The limits bound what CopyTrading does: the owner's CBRS is theirs.
    assert exposure.by_symbol == {}
    assert exposure.total == Decimal(0)


def test_only_the_copied_shares_of_a_stock_count_at_what_they_are_worth_or_cost():
    copied = OwnedLot(
        symbol="SOXL",
        entry_price=Decimal(90),
        source_key="discord:1",
        original_qty=Decimal(2),
        remaining_qty=Decimal(2),
        average_price=Decimal(90),
        entry_remaining={"b1": Decimal(2)},
        entry_prices={"b1": Decimal(90)},
    )

    def held(value: str) -> Position:
        # 2 copied shares and 8 of the owner's own, 10 in all.
        return Position(
            symbol="SOXL",
            qty=Decimal(10),
            market_value=Decimal(value),
            currency="USD",
            asset_class="us_equity",
        )

    # Worth $100 a share now: the 2 copied shares count $200, not the position's $1,000.
    assert account_exposure((held("1000"),), (copied,), (), account_currency="USD").total == 200
    # Worth less than they cost: they count what they cost.
    assert account_exposure((held("500"),), (copied,), (), account_currency="USD").total == 180


def test_a_dollar_size_buys_that_amount_never_more_than_the_full_position():
    assert decide(ROOMY, connection=FULL_3000, usd=Decimal(200)).budget == Decimal("200.00")
    assert decide(ROOMY, connection=FULL_3000, usd=Decimal(9000)).budget == Decimal("3000.00")


def test_a_dollar_size_is_still_trimmed_by_the_maximum_per_order():
    limits = replace(ROOMY, max_order_usd=Decimal(150))

    decision = decide(limits, connection=FULL_3000, usd=Decimal(200))

    assert (decision.budget, decision.requested) == (Decimal(150), Decimal("200.00"))


def test_a_stock_held_in_two_lots_counts_what_both_cost():
    def lot(source: str, entry: str) -> OwnedLot:
        return OwnedLot(
            symbol="NVDA",
            entry_price=Decimal(100),
            source_key=source,
            original_qty=Decimal(10),
            remaining_qty=Decimal(10),
            average_price=Decimal(100),
            entry_remaining={entry: Decimal(10)},
            entry_prices={entry: Decimal(100)},
        )

    # 20 copied shares that cost $2,000 in all, worth $1,800 now.
    held = Position(
        symbol="NVDA",
        qty=Decimal(20),
        market_value=Decimal(1800),
        currency="USD",
        asset_class="us_equity",
    )

    exposure = account_exposure(
        (held,), (lot("discord:a", "a1"), lot("discord:b", "b1")), (), account_currency="USD"
    )

    assert exposure.symbol("NVDA") == Decimal(2000)
