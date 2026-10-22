"""Pure classification policy for captured ingestion events."""

from datetime import datetime, timedelta
from typing import Literal


def delivery_mode(
    *, recovered: bool, source_at: datetime, assigned_at: datetime, catch_up_seconds: int
) -> Literal["live", "historical"]:
    """A post read back after the app was away is still copied while it is no older than the
    accounts' maximum signal age (`catch_up_seconds`); an older one is history, never traded."""
    if any(value.utcoffset() is None for value in (source_at, assigned_at)):
        raise ValueError("Delivery classification requires aware timestamps")
    late = source_at < assigned_at - timedelta(seconds=catch_up_seconds)
    return "historical" if recovered and late else "live"
