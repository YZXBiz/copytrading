"""Immutable parsing routes loaded from external JSON configuration."""

from collections.abc import Mapping
from dataclasses import dataclass
from types import MappingProxyType


@dataclass(frozen=True, slots=True)
class Route:
    """How one guru's posts are read: the owner's playbook, which guru and profile revision the
    reading belongs to, and how long a re-post of one of the guru's calls counts as the same call
    (None: never). The guru's trading habits live in the playbook (ADR-0010)."""

    playbook: str = ""
    guru_id: str | None = None
    profile_revision: str | None = None
    repeat_window_minutes: int | None = None

    def __post_init__(self) -> None:
        if (self.guru_id is None) != (self.profile_revision is None):
            raise ValueError("Guru identity and profile revision must be recorded together")


def freeze_routes(routes: Mapping[str, Route]) -> Mapping[str, Route]:
    return MappingProxyType(dict(routes))
