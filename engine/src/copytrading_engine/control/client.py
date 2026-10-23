"""Find the app's or the headless server's control socket and exchange one request line."""

import asyncio
import contextlib
import json
import os
import stat
import sys
from collections.abc import Mapping
from pathlib import Path
from typing import Final
from uuid import uuid4

from pydantic import ValidationError

from copytrading_engine.control import wire

DEFAULT_TIMEOUT: Final = 30.0
MAX_RESPONSE_BYTES: Final = 8 * 1024 * 1024


class AppUnavailable(Exception):
    """Neither the app nor the server is running, or agent access is off."""


class UnsafeSocket(Exception):
    """The socket path was not created by the owner's app, so it is never used."""


OLDER_CLIENT: Final = (
    "this copytrading CLI is older than the app; use the one inside CopyTrading.app"
)


class ProtocolMismatch(Exception):
    """The app answered with something outside the contract."""


class NoAnswer(AppUnavailable):
    """The request was sent, but no answer came in time; what it did is not known."""


class RequestTooLarge(Exception):
    """The request line is over the contract's limit, so it is never sent."""


def app_state_root() -> Path:
    """Where the Mac app keeps its state."""
    return Path.home() / "Library" / "Application Support" / "CopyTrading"


def server_state_root(
    environ: Mapping[str, str] = os.environ, platform: str = sys.platform
) -> Path:
    """Where the headless server keeps its state by default; never the app's folder."""
    if platform == "darwin":
        return Path.home() / "Library" / "Application Support" / "CopyTrading Server"
    base = environ.get("XDG_STATE_HOME") or str(Path.home() / ".local" / "state")
    return Path(base) / "copytrading-server"


def state_root(environ: Mapping[str, str] = os.environ, platform: str = sys.platform) -> Path:
    """An explicit state root; else the app's when its socket exists; else the server's."""
    value = environ.get("COPYTRADING_STATE_ROOT")
    if value:
        return Path(value)
    candidates = [server_state_root(environ, platform)]
    if platform == "darwin":
        candidates.insert(0, app_state_root())
    for root in candidates:
        if os.path.lexists(root / "control" / "cli.sock"):
            return root
    return candidates[0]


def is_server_socket(environ: Mapping[str, str] = os.environ, platform: str = sys.platform) -> bool:
    """The socket found is a headless server's, not the Mac app's. An explicit state root is the
    owner's choice; setup then relies on the app being the one that answers `get_setup`."""
    if environ.get("COPYTRADING_STATE_ROOT"):
        return False
    return state_root(environ, platform) == server_state_root(environ, platform)


def socket_path(environ: Mapping[str, str] = os.environ) -> Path:
    return state_root(environ) / "control" / "cli.sock"


def check_socket(path: Path) -> None:
    """Accept only an owner socket inside an owner-only directory, never through a symlink."""
    try:
        directory = os.lstat(path.parent)
        entry = os.lstat(path)
    except FileNotFoundError:
        raise AppUnavailable from None
    uid = os.getuid()
    if (
        not stat.S_ISDIR(directory.st_mode)
        or directory.st_uid != uid
        or directory.st_mode & 0o077
        or not stat.S_ISSOCK(entry.st_mode)
        or entry.st_uid != uid
    ):
        raise UnsafeSocket(str(path))


def new_request_id() -> str:
    return uuid4().hex


class ControlClient:
    def __init__(self, path: Path, *, timeout: float = DEFAULT_TIMEOUT) -> None:
        self._path = path
        self._timeout = timeout

    async def send(self, request: wire.Request) -> wire.Response:
        """Send one request on a fresh connection and return its single response."""
        line = wire.REQUEST.dump_json(request) + b"\n"
        if len(line) > wire.MAX_LINE_BYTES:
            raise RequestTooLarge(len(line))
        check_socket(self._path)
        try:
            reader, writer = await asyncio.wait_for(
                asyncio.open_unix_connection(self._path, limit=MAX_RESPONSE_BYTES),
                self._timeout,
            )
        except (ConnectionRefusedError, FileNotFoundError, TimeoutError) as exc:
            raise AppUnavailable from exc
        try:
            writer.write(line)
            await writer.drain()
        except (ConnectionError, TimeoutError) as exc:
            raise AppUnavailable from exc
        try:
            line = await asyncio.wait_for(reader.readline(), self._timeout)
        except TimeoutError as exc:
            raise NoAnswer(self._timeout) from exc
        except (ConnectionError, asyncio.LimitOverrunError) as exc:
            raise AppUnavailable from exc
        finally:
            writer.close()
            with contextlib.suppress(ConnectionError):
                await writer.wait_closed()
        if not line:
            raise AppUnavailable
        try:
            response = wire.Response.model_validate_json(line)
        except ValidationError as exc:
            raise ProtocolMismatch(_mismatch(line)) from exc
        if response.request_id not in ("", request.request_id):
            raise ProtocolMismatch("response answers a different request")
        return response


def _mismatch(line: bytes) -> str:
    """Why a response could not be read. The CLI and the app ship together, so a well-formed
    answer this client cannot read comes from a newer app (see the compatibility rule)."""
    try:
        payload = json.loads(line)
    except ValueError, RecursionError:
        return "response is outside the control contract"
    if isinstance(payload, dict) and isinstance(payload.get("schema_version"), int):
        if payload.get("ok") is not None or payload.get("error") is not None:
            return OLDER_CLIENT
    return "response is outside the control contract"
