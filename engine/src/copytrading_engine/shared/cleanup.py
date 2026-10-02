"""Release a resource without letting its close failure hide the operation's own outcome."""

import logging
from collections.abc import Awaitable, Callable


async def close_logged(
    close: Callable[[], Awaitable[object]], *, resource: str, log: logging.Logger
) -> None:
    try:
        await close()
    except Exception as exc:  # noqa: BLE001 - cleanup must not mask the primary outcome
        log.warning("%s_close_failed type=%s", resource, type(exc).__name__)
