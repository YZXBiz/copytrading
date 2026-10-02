"""Immutable values shared by notification presenters, persistence, and delivery."""

from collections.abc import Mapping
from dataclasses import dataclass
from datetime import datetime
from types import MappingProxyType


@dataclass(frozen=True, slots=True)
class NotificationPayload:
    labels: Mapping[str, str]
    annotations: Mapping[str, str]
    starts_at: datetime

    def __post_init__(self) -> None:
        object.__setattr__(self, "labels", _freeze_strings(self.labels, "labels"))
        object.__setattr__(self, "annotations", _freeze_strings(self.annotations, "annotations"))
        if not isinstance(self.starts_at, datetime):
            raise TypeError("Notification start time must be a datetime")
        if self.starts_at.tzinfo is None or self.starts_at.utcoffset() is None:
            raise ValueError("Notification start time must be timezone-aware")


@dataclass(frozen=True, slots=True)
class QueuedNotification:
    key: str
    payload: NotificationPayload

    def __post_init__(self) -> None:
        if not self.key:
            raise ValueError("Notification key cannot be empty")
        if not isinstance(self.payload, NotificationPayload):
            raise TypeError("Queued notification payload must be a NotificationPayload")


@dataclass(frozen=True, slots=True)
class NotificationIntent:
    key: str
    stream_id: str
    payload: NotificationPayload

    def __post_init__(self) -> None:
        if not self.key or not self.stream_id:
            raise ValueError("Notification key and stream ID cannot be empty")
        if not isinstance(self.payload, NotificationPayload):
            raise TypeError("Notification intent payload must be a NotificationPayload")


def _freeze_strings(values: Mapping[str, str], name: str) -> Mapping[str, str]:
    if not isinstance(values, Mapping):
        raise TypeError(f"Notification {name} must be a mapping")
    copied: dict[str, str] = {}
    for key, value in values.items():
        if not isinstance(key, str) or not isinstance(value, str):
            raise TypeError(f"Notification {name} keys and values must be strings")
        copied[key] = value
    return MappingProxyType(copied)
