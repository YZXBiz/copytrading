"""A queue observation must be internally consistent or it is refused, never guessed at."""

import datetime as dt

import pytest

from copytrading_engine.shared.queue_snapshot import QueueSnapshot

NOW = dt.datetime(2026, 1, 5, 15, tzinfo=dt.UTC)


def test_an_empty_queue_has_no_oldest_time():
    assert QueueSnapshot(0, None, 0).count == 0


def test_a_queue_with_known_ages_reports_its_oldest():
    assert QueueSnapshot(3, NOW, 1).oldest_at == NOW


@pytest.mark.parametrize(
    ("count", "oldest", "unknown", "message"),
    [
        (True, None, 0, "integers"),
        (1, None, 1.0, "integers"),
        (1, None, 2, "between zero"),
        (1, None, -1, "between zero"),
        (2, None, 1, "exactly when"),
        (1, NOW, 1, "exactly when"),
        (1, "yesterday", 0, "timezone-aware"),
        (1, dt.datetime(2026, 1, 5), 0, "timezone-aware"),
        (1, dt.datetime(1970, 1, 1, tzinfo=dt.UTC), 0, "telemetry zero"),
    ],
)
def test_an_inconsistent_observation_is_refused(count, oldest, unknown, message):
    with pytest.raises(ValueError, match=message):
        QueueSnapshot(count, oldest, unknown)


def test_a_row_becomes_a_snapshot_and_a_missing_row_is_an_error():
    assert QueueSnapshot.from_row((2, NOW, 0)) == QueueSnapshot(2, NOW, 0)
    with pytest.raises(RuntimeError, match="no row"):
        QueueSnapshot.from_row(None)
