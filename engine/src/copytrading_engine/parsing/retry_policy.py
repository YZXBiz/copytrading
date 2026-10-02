"""Application-owned retry scheduling for parser extraction attempts."""

from datetime import datetime, timedelta


def next_retry_at(now: datetime, prior_attempts: int) -> datetime:
    if now.tzinfo is None or now.utcoffset() is None or prior_attempts < 0:
        raise ValueError("Retry scheduling requires aware time and nonnegative attempts")
    delay = 10 if prior_attempts == 0 else 20 if prior_attempts == 1 else 30
    return now + timedelta(seconds=delay)
