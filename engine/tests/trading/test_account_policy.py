"""A saved account's limits and the engine's are one definition."""

from copytrading_engine.execution.domain.pricing import PricePolicy
from copytrading_engine.execution.domain.signals import AccountLimits, CopyConfig
from copytrading_engine.trading.domain.config import AccountPolicy

PRICING = {"max_above_signal_pct", "max_below_signal_pct"}


def test_the_saved_policy_and_the_engine_take_every_limit_from_one_place():
    """Each limit was declared twice, in AccountPolicy and CopyConfig, with its default and its
    bounds; the 100% sell allowance had to be fixed in both."""
    shared = set(AccountLimits.model_fields)
    assert set(AccountPolicy.model_fields) == shared | PRICING
    assert set(CopyConfig.model_fields) == shared | {"sources", "pricing"}
    for name in shared:
        assert repr(AccountPolicy.model_fields[name]) == repr(CopyConfig.model_fields[name])
    for name in PRICING:
        assert repr(AccountPolicy.model_fields[name]) == repr(PricePolicy.model_fields[name])
