"""Diagnostics settings: where the private journal lives and how long it is kept."""

import os
from dataclasses import dataclass
from pathlib import Path

_DEFAULT_QUEUE_CAPACITY = 32
_MAX_QUEUE_CAPACITY = 256
DEFAULT_RETENTION_DAYS = 7
DEFAULT_MAX_BYTES = 256 * 1_024 * 1_024
MIN_MAX_BYTES = 8 * 1_024 * 1_024
MAX_MAX_BYTES = 16 * 1_024 * 1_024 * 1_024


@dataclass(frozen=True)
class TelemetryConfig:
    """Finite local diagnostics settings; nothing here leaves the Mac."""

    journal_directory: Path
    retention_age_days: int = DEFAULT_RETENTION_DAYS
    max_bytes: int = DEFAULT_MAX_BYTES
    queue_capacity: int = _DEFAULT_QUEUE_CAPACITY

    def __post_init__(self) -> None:
        if not 1 <= self.queue_capacity <= _MAX_QUEUE_CAPACITY:
            raise ValueError("telemetry queue capacity is outside the supported bounds")
        if not 1 <= self.retention_age_days <= 3_650:
            raise ValueError("diagnostics retention age is outside the supported bounds")
        if not MIN_MAX_BYTES <= self.max_bytes <= MAX_MAX_BYTES:
            raise ValueError("diagnostics storage limit is outside the supported bounds")

    @classmethod
    def from_environment(cls, journal_directory: Path) -> TelemetryConfig:
        """Read the app's retention choice; an unreadable value keeps the default."""
        return cls(
            journal_directory=journal_directory,
            retention_age_days=_bounded_int(
                "COPYTRADING_DESKTOP_DIAGNOSTICS_RETENTION_DAYS", DEFAULT_RETENTION_DAYS, 1, 3_650
            ),
            max_bytes=_bounded_int(
                "COPYTRADING_DESKTOP_DIAGNOSTICS_MAX_BYTES",
                DEFAULT_MAX_BYTES,
                MIN_MAX_BYTES,
                MAX_MAX_BYTES,
            ),
        )


def _bounded_int(name: str, default: int, low: int, high: int) -> int:
    try:
        value = int(os.environ.get(name, str(default)))
    except ValueError:
        return default
    return value if low <= value <= high else default
