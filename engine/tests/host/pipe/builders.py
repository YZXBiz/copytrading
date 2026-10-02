"""Pipe request lines, decoded replies, and trading services for host tests."""

import json
from typing import Any

from copytrading_engine.host.pipe.services import TradingServices


def services(fake: Any) -> TradingServices:
    """One test double plays every trading role the pipe dispatches to."""
    return TradingServices(fake, fake, fake, fake)


def request_line(operation: str, request_id: str, **values: object) -> bytes:
    return json.dumps(
        {"version": 1, "request_id": request_id, "operation": operation, **values}
    ).encode()


def decode(line: bytes) -> dict[str, Any]:
    assert line.endswith(b"\n")
    return json.loads(line)
