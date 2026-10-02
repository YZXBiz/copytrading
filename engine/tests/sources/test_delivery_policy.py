"""Recovered history is audit-only; live capture stays live."""

import datetime as dt

import pytest

from copytrading_engine.sources.delivery_policy import delivery_mode


@pytest.mark.parametrize(("age", "expected"), [(119, "live"), (120, "live"), (121, "historical")])
def test_recovered_delivery_boundary(age, expected):
    now = dt.datetime(2026, 1, 1, tzinfo=dt.UTC)
    assert (
        delivery_mode(
            recovered=True,
            source_at=now - dt.timedelta(seconds=age),
            assigned_at=now,
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
    }
    values[naive_timestamp] = now.replace(tzinfo=None)

    with pytest.raises(ValueError, match="Delivery classification requires aware timestamps"):
        delivery_mode(**values)
