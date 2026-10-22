"""A post read back after the app was away is copied while it is no older than the accounts'
maximum signal age; older history is audit-only; live capture stays live."""

import datetime as dt

import pytest

from copytrading_engine.sources.delivery_policy import delivery_mode


@pytest.mark.parametrize(
    ("window", "age", "expected"),
    [
        (120, 119, "live"),
        (120, 120, "live"),
        (120, 121, "historical"),
        # An account that allows 10-minute-old calls catches up on a post missed for 9.
        (600, 540, "live"),
        (600, 601, "historical"),
    ],
)
def test_recovered_delivery_follows_the_maximum_signal_age(window, age, expected):
    now = dt.datetime(2026, 1, 1, tzinfo=dt.UTC)
    assert (
        delivery_mode(
            recovered=True,
            source_at=now - dt.timedelta(seconds=age),
            assigned_at=now,
            catch_up_seconds=window,
        )
        == expected
    )


def test_live_capture_is_not_reclassified_as_history():
    now = dt.datetime(2026, 1, 1, tzinfo=dt.UTC)
    assert (
        delivery_mode(
            recovered=False,
            source_at=now - dt.timedelta(days=1),
            assigned_at=now,
            catch_up_seconds=120,
        )
        == "live"
    )


@pytest.mark.parametrize("naive_timestamp", ["source_at", "assigned_at"])
def test_delivery_classification_requires_aware_timestamps(naive_timestamp):
    now = dt.datetime(2026, 1, 1, tzinfo=dt.UTC)
    values = {
        "recovered": True,
        "source_at": now,
        "assigned_at": now,
        "catch_up_seconds": 120,
    }
    values[naive_timestamp] = now.replace(tzinfo=None)

    with pytest.raises(ValueError, match="Delivery classification requires aware timestamps"):
        delivery_mode(**values)
