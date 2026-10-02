"""Which configured route a source message follows; parsing and delivery must pick the same one."""

from collections.abc import Mapping
from dataclasses import dataclass

AMBIGUOUS_SOURCE_PROFILE = "ambiguous_source_profile"


def route_key(source: str, channel_id: str, author_id: str | None) -> str:
    """A route is bound to one author, or to every author in the channel (`*`)."""
    return f"{source}:{channel_id}:{author_id or '*'}"


@dataclass(frozen=True, slots=True)
class RouteChoice[T]:
    route: T | None
    error: str | None = None


def choose_route[T](
    routes: Mapping[str, T], source: str, channel_id: str, author_id: str | None
) -> RouteChoice[T]:
    """The author's own route, else the channel's; configuring both for one author is ambiguous."""
    exact = routes.get(route_key(source, channel_id, author_id)) if author_id is not None else None
    wildcard = routes.get(route_key(source, channel_id, None))
    if exact is not None and wildcard is not None:
        return RouteChoice(None, AMBIGUOUS_SOURCE_PROFILE)
    return RouteChoice(exact if exact is not None else wildcard)
