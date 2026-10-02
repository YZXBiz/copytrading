"""Pure classification policy for captured ingestion events."""

from datetime import datetime, timedelta
from typing import Literal


def delivery_mode(
    *, recovered: bool, source_at: datetime, assigned_at: datetime
) -> Literal["live", "historical"]:
    if any(value.utcoffset() is None for value in (source_at, assigned_at)):
        raise ValueError("Delivery classification requires aware timestamps")
    return (
        "historical" if recovered and source_at < assigned_at - timedelta(seconds=120) else "live"
    )
