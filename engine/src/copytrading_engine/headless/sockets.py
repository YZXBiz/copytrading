"""The server's two local sockets: agents (the app's control contract) and the owner.

Both live in an owner-only directory. The agent socket answers exactly what the app's does,
at the access the owner chose. The owner socket carries what the app does after Touch ID:
approving proposals, turning entries on, pausing and resuming. On a server there is no
Touch ID, so the owner socket trusts the operating-system user who started the server.
"""

import asyncio
import contextlib
import os
import socket
import stat
import struct
import sys
from collections.abc import Awaitable, Callable
from pathlib import Path

from pydantic import ValidationError

from copytrading_engine.control.wire import MAX_LINE_BYTES
from copytrading_engine.headless.engine import EngineRefused, HeadlessEngine
from copytrading_engine.headless.owner import (
    OWNER_ANSWER,
    OWNER_REQUEST,
    OwnerAnswer,
    OwnerRequest,
    Refused,
)

MAX_OWNER_LINE_BYTES = 64 * 1024

type OwnerHandler = Callable[[OwnerRequest], Awaitable[OwnerAnswer]]


class UnsafeStateDirectory(Exception):
    """The control directory is not private to this user, so no socket is opened in it."""


def prepare_private_directory(path: Path) -> None:
    """Create the directory owner-only, and refuse one someone else could read or replace."""
    path.mkdir(mode=0o700, parents=True, exist_ok=True)
    entry = os.lstat(path)
    if not stat.S_ISDIR(entry.st_mode) or entry.st_uid != os.getuid():
        raise UnsafeStateDirectory(str(path))
    if entry.st_mode & 0o077:
        os.chmod(path, 0o700)


def remove_stale_socket(path: Path) -> None:
    """Remove a socket left by a server that is no longer running; refuse anything else."""
    try:
        entry = os.lstat(path)
    except FileNotFoundError:
        return
    if not stat.S_ISSOCK(entry.st_mode) or entry.st_uid != os.getuid():
        raise UnsafeStateDirectory(f"{path} exists and is not this server's socket")
    probe = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        probe.connect(str(path))
    except ConnectionRefusedError, FileNotFoundError:
        path.unlink(missing_ok=True)
        return
    finally:
        probe.close()
    raise UnsafeStateDirectory(f"another server is already listening on {path}")


def peer_pid(writer: asyncio.StreamWriter) -> int | None:
    """The connecting process, for the audit trail; None where the system will not say."""
    sock = writer.get_extra_info("socket")
    if sock is None:
        return None
    try:
        if sys.platform == "darwin":
            # SOL_LOCAL, LOCAL_PEERPID
            return int(sock.getsockopt(0, 0x002)) or None
        if hasattr(socket, "SO_PEERCRED"):
            data = sock.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, struct.calcsize("3i"))
            pid, _uid, _gid = struct.unpack("3i", data)
            return pid or None
    except OSError:
        return None
    return None


async def _read_line(reader: asyncio.StreamReader, limit: int) -> bytes | None:
    try:
        line = await asyncio.wait_for(reader.readuntil(b"\n"), timeout=30)
    except asyncio.IncompleteReadError, asyncio.LimitOverrunError, TimeoutError:
        return None
    return line if len(line) <= limit + 1 else None


async def _finish(writer: asyncio.StreamWriter, payload: bytes) -> None:
    with contextlib.suppress(ConnectionError):
        writer.write(payload)
        await writer.drain()
    writer.close()
    with contextlib.suppress(ConnectionError):
        await writer.wait_closed()


def agent_handler(
    engine: HeadlessEngine,
) -> Callable[[asyncio.StreamReader, asyncio.StreamWriter], Awaitable[None]]:
    async def handle(reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        line = await _read_line(reader, MAX_LINE_BYTES)
        if line is None:
            await _finish(writer, b"")
            return
        try:
            answer = await engine.relay_agent_line(line.decode().rstrip("\n"), peer_pid(writer))
        except EngineRefused, UnicodeDecodeError:
            # The client reads an empty answer as "not available".
            await _finish(writer, b"")
            return
        await _finish(writer, answer.encode() + b"\n")

    return handle


def owner_handler(
    handle_request: OwnerHandler,
) -> Callable[[asyncio.StreamReader, asyncio.StreamWriter], Awaitable[None]]:
    async def handle(reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        line = await _read_line(reader, MAX_OWNER_LINE_BYTES)
        if line is None:
            await _finish(writer, b"")
            return
        answer: OwnerAnswer
        try:
            answer = await handle_request(OWNER_REQUEST.validate_json(line))
        except ValidationError:
            answer = Refused(reason="That is not a request this server understands.")
        except EngineRefused as refused:
            answer = Refused(reason=str(refused))
        await _finish(writer, OWNER_ANSWER.dump_json(answer) + b"\n")

    return handle


async def open_socket(
    path: Path,
    handler: Callable[[asyncio.StreamReader, asyncio.StreamWriter], Awaitable[None]],
    *,
    limit: int,
) -> asyncio.Server:
    remove_stale_socket(path)
    server = await asyncio.start_unix_server(handler, path=str(path), limit=limit + 2)
    os.chmod(path, 0o600)
    return server


async def ask_owner_socket(
    path: Path, request: OwnerRequest, *, timeout: float = 180
) -> OwnerAnswer:
    """Send one owner request to a running server and return its checked answer."""
    try:
        reader, writer = await asyncio.wait_for(
            asyncio.open_unix_connection(str(path), limit=8 * 1024 * 1024), timeout=10
        )
    except (ConnectionRefusedError, FileNotFoundError, TimeoutError) as exc:
        raise ServerNotRunning(str(path)) from exc
    try:
        writer.write(OWNER_REQUEST.dump_json(request) + b"\n")
        await writer.drain()
        line = await asyncio.wait_for(reader.readline(), timeout=timeout)
    finally:
        writer.close()
        with contextlib.suppress(ConnectionError):
            await writer.wait_closed()
    if not line:
        raise ServerNotRunning(str(path))
    answer = OWNER_ANSWER.validate_json(line)
    if isinstance(answer, Refused):
        raise OwnerRequestFailed(answer.reason)
    return answer


class ServerNotRunning(Exception):
    """No server answered on the owner socket."""


class OwnerRequestFailed(Exception):
    """The server refused the owner's request."""
