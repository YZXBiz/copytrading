"""The real engine in this process, reached through the server's own sockets."""

import asyncio
import io
import os
import stat
import tempfile
from pathlib import Path

import pytest

from copytrading_engine.control import wire
from copytrading_engine.control.client import ControlClient, new_request_id
from copytrading_engine.headless import cli
from copytrading_engine.headless.engine import HeadlessEngine
from copytrading_engine.headless.owner import (
    AskStatus,
    CopyingStatus,
    ListProposals,
    Pause,
    Proposals,
)
from copytrading_engine.headless.server import ServerPaths, run_server
from copytrading_engine.headless.sockets import (
    ServerNotRunning,
    UnsafeStateDirectory,
    ask_owner_socket,
    remove_stale_socket,
)

from .test_engine import setup  # noqa: F401 - the fixture is shared


@pytest.fixture
def paths():
    # Unix socket paths are short on macOS; keep the root near the top of the temp folder.
    with tempfile.TemporaryDirectory(prefix="ct-") as root:
        yield ServerPaths(Path(root).resolve() / "state")


@pytest.fixture
async def running(setup, paths, monkeypatch):  # noqa: F811
    async def started(self):
        return None

    # The setup check reaches Discord, the model, and Alpaca; this test is about the server.
    monkeypatch.setattr(HeadlessEngine, "start", started)
    loaded, secrets = setup
    stop = asyncio.Event()
    said: list[str] = []
    task = asyncio.create_task(
        run_server(
            loaded, secrets, paths, say=said.append, stop=stop, install_signal_handlers=False
        )
    )
    for _ in range(200):
        if paths.agent_socket.exists() and paths.owner_socket.exists():
            break
        await asyncio.sleep(0.05)
    yield paths, said
    stop.set()
    await asyncio.wait_for(task, 30)


async def test_the_server_keeps_its_state_private(running):
    paths, _ = running
    for directory in (paths.root, paths.data, paths.support, paths.logs, paths.control):
        assert stat.S_IMODE(os.stat(directory).st_mode) == 0o700
    for socket_path in (paths.agent_socket, paths.owner_socket):
        assert stat.S_IMODE(os.stat(socket_path).st_mode) == 0o600


async def test_the_copytrading_command_reads_the_server(running):
    paths, _ = running

    response = await ControlClient(paths.agent_socket, timeout=10).send(
        wire.GetStatus(request_id=new_request_id())
    )

    assert response.error is None
    assert response.ok is not None


async def test_the_owner_sees_status_and_can_pause(running):
    paths, said = running

    status = await ask_owner_socket(paths.owner_socket, AskStatus())
    paused = await ask_owner_socket(paths.owner_socket, Pause())
    proposals = await ask_owner_socket(paths.owner_socket, ListProposals())

    assert isinstance(status, CopyingStatus)
    assert status.state in {"paused", "stopped"}
    assert isinstance(paused, CopyingStatus)
    assert proposals == Proposals(items=())
    assert "Copying paused." in said


async def test_a_line_outside_the_owner_contract_is_refused(running):
    paths, _ = running
    reader, writer = await asyncio.open_unix_connection(str(paths.owner_socket))
    writer.write(b'{"op":"launch"}\n')
    await writer.drain()

    answer = await reader.readline()
    writer.close()

    assert b'"type":"refused"' in answer


async def test_stopping_removes_the_sockets(setup, paths, monkeypatch):  # noqa: F811
    async def started(self):
        return None

    monkeypatch.setattr(HeadlessEngine, "start", started)
    loaded, secrets = setup
    stop = asyncio.Event()
    said: list[str] = []
    task = asyncio.create_task(
        run_server(
            loaded, secrets, paths, say=said.append, stop=stop, install_signal_handlers=False
        )
    )
    while not paths.owner_socket.exists():
        await asyncio.sleep(0.05)
    stop.set()
    await asyncio.wait_for(task, 30)

    assert not paths.owner_socket.exists()
    assert not paths.agent_socket.exists()
    assert said[-1] == "Stopped."
    with pytest.raises(ServerNotRunning):
        await ask_owner_socket(paths.owner_socket, AskStatus())


async def test_a_second_server_on_the_same_state_is_refused(running):
    paths, _ = running

    with pytest.raises(UnsafeStateDirectory, match="already listening"):
        remove_stale_socket(paths.owner_socket)


def test_a_leftover_socket_from_a_crash_is_cleared(paths):
    import socket

    paths.control.mkdir(parents=True, mode=0o700)
    leftover = socket.socket(socket.AF_UNIX)
    leftover.bind(str(paths.owner_socket))
    leftover.close()

    remove_stale_socket(paths.owner_socket)

    assert not paths.owner_socket.exists()


def test_a_file_where_the_socket_goes_is_never_deleted(paths):
    paths.control.mkdir(parents=True, mode=0o700)
    paths.owner_socket.write_text("not a socket")

    with pytest.raises(UnsafeStateDirectory):
        remove_stale_socket(paths.owner_socket)
    assert paths.owner_socket.read_text() == "not a socket"


async def test_owner_commands_print_plain_text(running):
    paths, _ = running
    out, err = io.StringIO(), io.StringIO()

    code = await asyncio.to_thread(
        cli.main, ["--state-dir", str(paths.root), "status"], out=out, err=err
    )

    assert code == cli.EXIT_OK, err.getvalue()
    assert "Copying" in out.getvalue()
    assert "paper-main" not in err.getvalue()


def test_owner_commands_say_when_no_server_runs(paths):
    out, err = io.StringIO(), io.StringIO()

    code = cli.main(["--state-dir", str(paths.root), "proposals"], out=out, err=err)

    assert code == cli.EXIT_NOT_RUNNING
    assert "copytrading-server run" in err.getvalue()


def test_init_writes_the_template_once(tmp_path):
    target = tmp_path / "copytrading.toml"
    out, err = io.StringIO(), io.StringIO()

    assert cli.main(["init", str(target)], out=out, err=err) == cli.EXIT_OK
    assert "[[gurus]]" in target.read_text()
    assert cli.main(["init", str(target)], out=out, err=err) == cli.EXIT_FAILED
    assert "already exists" in err.getvalue()


def test_config_problems_exit_as_usage_errors(tmp_path):
    out, err = io.StringIO(), io.StringIO()

    code = cli.main(["check", "--config", str(tmp_path / "missing.toml")], out=out, err=err)

    assert code == cli.EXIT_USAGE
    assert "copytrading-server init" in err.getvalue()


async def cli_run(paths, *argv: str) -> tuple[int, str, str]:
    out, err = io.StringIO(), io.StringIO()
    code = await asyncio.to_thread(
        cli.main, ["--state-dir", str(paths.root), *argv], out=out, err=err
    )
    return code, out.getvalue(), err.getvalue()


async def test_pause_and_an_empty_approval_queue_read_plainly(running):
    paths, _ = running

    paused = await cli_run(paths, "pause")
    waiting = await cli_run(paths, "proposals")

    assert paused[0] == cli.EXIT_OK
    assert paused[1].startswith("Copying ")
    assert waiting == (cli.EXIT_OK, "Nothing is waiting for your approval.\n", "")


async def test_approving_something_that_is_not_waiting_changes_nothing(running):
    paths, _ = running

    code, out, err = await cli_run(paths, "approve", "p-0123456789ab", "--yes")

    assert code == cli.EXIT_FAILED
    assert "is not waiting for approval" in err
    assert "Approve:" not in out


async def test_rejecting_an_unknown_proposal_is_refused(running):
    paths, _ = running

    code, _, err = await cli_run(paths, "reject", "p-0123456789ab")

    assert code == cli.EXIT_FAILED
    assert err.startswith("✗")


async def test_an_account_id_outside_the_rules_never_reaches_the_server(running):
    paths, said = running

    code, _, err = await cli_run(paths, "entries", "enable", "not an id!")

    assert code == cli.EXIT_USAGE
    assert err.startswith("✗ account:")
    assert not any("Entries" in line for line in said)
