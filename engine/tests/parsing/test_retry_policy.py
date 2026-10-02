"""Parser retries follow a fixed schedule over aware time."""

from datetime import UTC, datetime, timedelta

import pytest

from copytrading_engine.parsing.retry_policy import next_retry_at


@pytest.mark.parametrize(("attempts", "seconds"), [(0, 10), (1, 20), (2, 30), (9, 30)])
def test_retry_schedule(attempts, seconds):
    now = datetime(2026, 1, 1, tzinfo=UTC)

    assert next_retry_at(now, attempts) == now + timedelta(seconds=seconds)


@pytest.mark.parametrize(
    ("now", "attempts"),
    [
        (datetime(2026, 1, 1), 0),
        (datetime(2026, 1, 1, tzinfo=UTC), -1),
    ],
)
def test_retry_schedule_requires_aware_time_and_nonnegative_attempts(now, attempts):
    with pytest.raises(
        ValueError,
        match="Retry scheduling requires aware time and nonnegative attempts",
    ):
        next_retry_at(now, attempts)
