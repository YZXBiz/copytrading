"""Immutable values exchanged by ingestion recovery boundaries."""

from collections.abc import Mapping
from dataclasses import dataclass
from datetime import datetime
from types import MappingProxyType
from typing import Literal, cast

from pydantic import JsonValue

Bootstrap = Literal["earliest_retained", "recent_only"]


@dataclass(frozen=True, slots=True)
class RecoveryStart:
    last_id: int
    bootstrap: Bootstrap

    def __post_init__(self) -> None:
        if type(self.last_id) is not int or self.last_id < 0:
            raise ValueError("Recovery cursor must be a non-negative integer")
        _validate_bootstrap(self.bootstrap)


@dataclass(frozen=True, slots=True)
class RecoveryProgress:
    channel_id: str
    last_id: int
    bootstrap: Bootstrap
    updated_at: datetime

    def __post_init__(self) -> None:
        if not self.channel_id:
            raise ValueError("Recovery channel ID cannot be empty")
        if type(self.last_id) is not int or self.last_id < 0:
            raise ValueError("Recovery cursor must be a non-negative integer")
        _validate_bootstrap(self.bootstrap)
        if self.updated_at.tzinfo is None or self.updated_at.utcoffset() is None:
            raise ValueError("Recovery update time must be timezone-aware")


@dataclass(frozen=True, slots=True)
class RejectedCapture:
    payload: Mapping[str, JsonValue]
    reason: str

    def __post_init__(self) -> None:
        if not isinstance(self.payload, Mapping):
            raise TypeError("Rejected capture payload must be a mapping")
        object.__setattr__(self, "payload", cast(Mapping[str, JsonValue], _freeze(self.payload)))


def _validate_bootstrap(bootstrap: str) -> None:
    if bootstrap not in {"earliest_retained", "recent_only"}:
        raise ValueError("Unknown recovery bootstrap mode")


def _freeze(value: object) -> JsonValue:
    if isinstance(value, Mapping):
        if any(not isinstance(key, str) for key in value):
            raise TypeError("Rejected capture object keys must be strings")
        return cast(
            JsonValue,
            MappingProxyType({key: _freeze(item) for key, item in value.items()}),
        )
    if isinstance(value, list | tuple):
        return cast(JsonValue, tuple(_freeze(item) for item in value))
    if value is None or isinstance(value, str | int | float | bool):
        return cast(JsonValue, value)
    raise TypeError("Rejected capture payload must contain only JSON values")


def plain_json(value: object) -> JsonValue:
    """Return owned JSON containers for private persistence serialization."""
    if isinstance(value, Mapping):
        return {key: plain_json(item) for key, item in value.items()}
    if isinstance(value, list | tuple):
        return [plain_json(item) for item in value]
    if value is None or isinstance(value, str | int | float | bool):
        return cast(JsonValue, value)
    raise TypeError("Rejected capture payload must contain only JSON values")
