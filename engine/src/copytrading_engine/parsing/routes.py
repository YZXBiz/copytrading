"""Immutable parsing routes loaded from external JSON configuration."""

from collections.abc import Mapping
from dataclasses import dataclass
from types import MappingProxyType
from typing import Literal


@dataclass(frozen=True, slots=True)
class Route:
    prefix: str = ""
    playbook: str = ""
    guru_id: str | None = None
    profile_revision: str | None = None
    exit_basis: Literal["original_position", "remaining_position"] | None = None

    def __post_init__(self) -> None:
        if (self.guru_id is None) != (self.profile_revision is None):
            raise ValueError("Guru identity and profile revision must be recorded together")
        if self.guru_id is not None and self.exit_basis is None:
            raise ValueError("An active profile route requires an explicit exit basis")


def freeze_routes(routes: Mapping[str, Route]) -> Mapping[str, Route]:
    return MappingProxyType(dict(routes))
