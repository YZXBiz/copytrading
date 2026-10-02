"""Immutable observations shared by durable queue stores and operators."""

import datetime as dt
from dataclasses import dataclass


@dataclass(frozen=True)
class QueueSnapshot:
    count: int
    oldest_at: dt.datetime | None
    unknown_age_count: int

    def __post_init__(self) -> None:
        if type(self.count) is not int or type(self.unknown_age_count) is not int:
            raise ValueError("Queue counts must be integers")
        if not 0 <= self.unknown_age_count <= self.count:
            raise ValueError("Unknown-age count must be between zero and pending count")
        has_known_age = self.count > self.unknown_age_count
        if has_known_age != (self.oldest_at is not None):
            raise ValueError("Oldest timestamp must exist exactly when a pending age is known")
        if self.oldest_at is not None:
            if not isinstance(self.oldest_at, dt.datetime) or self.oldest_at.utcoffset() is None:
                raise ValueError("Queue timestamps must be timezone-aware datetimes")
            if self.oldest_at.timestamp() <= 0:
                raise ValueError("Queue timestamps must be after the telemetry zero sentinel")

    @classmethod
    def from_row(cls, row: tuple[int, dt.datetime | None, int] | None) -> QueueSnapshot:
        if row is None:
            raise RuntimeError("Queue observation query returned no row")
        return cls(*row)
