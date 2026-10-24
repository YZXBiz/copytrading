"""Limit prices round down within the permitted ceiling."""

from decimal import Decimal

import pytest
from pydantic import ValidationError

from copytrading_engine.execution.domain.pricing import PricePolicy
from copytrading_engine.execution.domain.signals import CopyConfig
from copytrading_engine.trading.domain.config import AccountPolicy


@pytest.mark.parametrize(
    ("source", "percent", "expected"),
    [
        ("839", "1", "847.39"),
        ("839", "0", "839.00"),
        ("100", "0.5", "100.50"),
        ("100.01", "1", "101.01"),
        ("0.99", "1", "0.9999"),
        ("0.9950", "1", "1.00"),
        ("0.0001", "1", "0.0001"),
    ],
)
def test_limit_is_rounded_down_without_crossing_ceiling(source, percent, expected):
    price, tolerance = Decimal(source), Decimal(percent)
    limit = PricePolicy(max_above_signal_pct=tolerance).buy_ceiling(price)
    assert limit == Decimal(expected)
    assert limit <= price * (1 + tolerance / 100)
    tick = Decimal("0.01") if limit >= 1 else Decimal("0.0001")
    assert limit == limit.quantize(tick)


@pytest.mark.parametrize("value", ["-1", "101", "NaN", "Infinity", "one percent"])
def test_invalid_tolerance_is_rejected(value):
    with pytest.raises(ValidationError):
        PricePolicy(max_above_signal_pct=value)


def test_existing_configuration_preserves_exact_price_behavior():
    config = CopyConfig(sources=["discord:demo"])
    assert config.pricing.buy_ceiling(Decimal("839")) == Decimal("839")
    with pytest.raises(ValidationError):
        CopyConfig(sources=["discord:demo"], pricing={"max_above_signal_percent": "1"})


@pytest.mark.parametrize(
    ("source", "percent", "expected"),
    [
        ("100", "1", "99.00"),
        ("27.123", "1", "26.86"),
        ("100", "0", "100.00"),
        ("100.01", "1", "99.01"),
        ("0.99", "1", "0.9801"),
        ("100", "2.5", "97.50"),
    ],
)
def test_exit_limit_is_rounded_up_without_crossing_the_floor(source, percent, expected):
    price, tolerance = Decimal(source), Decimal(percent)
    limit = PricePolicy(max_below_signal_pct=tolerance).sell_floor(price)
    assert limit == Decimal(expected)
    assert limit >= price * (1 - tolerance / 100)
    tick = Decimal("0.01") if limit >= 1 else Decimal("0.0001")
    assert limit == limit.quantize(tick)


def test_exit_allowance_defaults_to_one_percent_and_is_separate_from_the_entry_allowance():
    policy = PricePolicy(max_above_signal_pct=Decimal("3"))
    assert policy.max_below_signal_pct == Decimal("1")
    assert policy.sell_floor(Decimal("100")) == Decimal("99.00")
    assert policy.buy_ceiling(Decimal("100")) == Decimal("103.00")


@pytest.mark.parametrize("value", ["-1", "101", "NaN", "Infinity", "one percent"])
def test_invalid_exit_allowance_is_rejected(value):
    with pytest.raises(ValidationError):
        PricePolicy(max_below_signal_pct=value)


def test_a_sell_can_never_be_allowed_to_fill_at_nothing():
    """At 100% below the guru's price the floor was $0, a limit no order can carry: the plan failed
    validation inside the copy cycle and the account stopped until CopyTrading restarted."""
    with pytest.raises(ValidationError):
        PricePolicy(max_below_signal_pct="100")
    with pytest.raises(ValidationError):
        AccountPolicy(max_below_signal_pct="100")
    widest = PricePolicy(max_below_signal_pct="99.99")
    for price in ("0.0001", "0.5", "1", "25.10"):
        assert widest.sell_floor(Decimal(price)) > 0
