"""A real engine process recovers idempotently and owns its installation alone."""

import json
import os
import select
import sqlite3
import subprocess
import sys
from contextlib import closing
from pathlib import Path
from typing import Any

from copytrading_engine.host.pipe.server import MAX_REQUEST_LINE_BYTES

_INSTANCE_ID = "10000000-0000-4000-8000-000000000001"


def _start_engine(
    data_dir: Path,
    instance_id: str = _INSTANCE_ID,
    *,
    extra_pythonpath: Path | None = None,
    pass_fds: tuple[int, ...] = (),
    environment: dict[str, str] | None = None,
) -> subprocess.Popen[bytes]:
    child_environment = os.environ.copy() | {
        "COPYTRADING_DESKTOP_OWNER_SUPPORT_DIR": str(data_dir),
        "COPYTRADING_DESKTOP_DIAGNOSTICS_STATE_DIR": str(data_dir / "diagnostics"),
    }
    if extra_pythonpath is not None:
        inherited_pythonpath = child_environment.get("PYTHONPATH", "")
        child_environment["PYTHONPATH"] = os.pathsep.join(
            part for part in (str(extra_pythonpath), inherited_pythonpath) if part
        )
    if environment is not None:
        child_environment.update(environment)
    return subprocess.Popen(
        [
            sys.executable,
            "-m",
            "copytrading_engine",
            "--data-dir",
            str(data_dir),
            "--instance-id",
            instance_id,
        ],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        bufsize=0,
        env=child_environment,
        pass_fds=pass_fds,
    )


def _send(process: subprocess.Popen[bytes], payload: dict[str, object]) -> None:
    assert process.stdin is not None
    process.stdin.write(json.dumps(payload).encode() + b"\n")
    process.stdin.flush()


def _wait_readable(process: subprocess.Popen[bytes], timeout: float = 8.0) -> None:
    assert process.stdout is not None
    ready, _, _ = select.select([process.stdout], [], [], timeout)
    assert ready, "engine did not produce a response before the deadline"


def _read_response(process: subprocess.Popen[bytes]) -> dict[str, Any]:
    _wait_readable(process)
    assert process.stdout is not None
    return json.loads(process.stdout.readline())


def _submit_request() -> dict[str, object]:
    return {
        "version": 1,
        "request_id": "req-submit",
        "operation": "submit_self_test",
        "command": {
            "command_id": "sim-1",
            "text": "Bought AAPL 1/6 at 200",
            "destination_ids": ["self-test-a", "self-test-b"],
        },
    }


def _stop(process: subprocess.Popen[bytes]) -> None:
    if process.poll() is None:
        process.kill()
        process.wait(timeout=5)
    for stream in (process.stdin, process.stdout, process.stderr):
        if stream is not None:
            stream.close()


def test_kill_after_durable_acceptance_before_response_recovers_idempotently(tmp_path):
    data_dir = tmp_path / "installation data"
    hook_dir = tmp_path / "process-test-hooks"
    hook_dir.mkdir()
    (hook_dir / "sitecustomize.py").write_text(
        "import os\n"
        "from copytrading_engine.host.self_test.service import SelfTestService\n"
        "_submit = SelfTestService.submit\n"
        "async def _pause_after_accept(self, command):\n"
        "    workflow = await _submit(self, command)\n"
        "    if command.command_id == 'sim-1':\n"
        "        os.write(int(os.environ['COPYTRADING_ENGINE_TEST_COMMIT_FD']), b'C')\n"
        "        os.read(int(os.environ['COPYTRADING_ENGINE_TEST_RELEASE_FD']), 1)\n"
        "    return workflow\n"
        "SelfTestService.submit = _pause_after_accept\n",
        encoding="utf-8",
    )
    commit_reader, commit_writer = os.pipe()
    release_reader, release_writer = os.pipe()
    first = _start_engine(
        data_dir,
        extra_pythonpath=hook_dir,
        pass_fds=(commit_writer, release_reader),
        environment={
            "COPYTRADING_ENGINE_TEST_COMMIT_FD": str(commit_writer),
            "COPYTRADING_ENGINE_TEST_RELEASE_FD": str(release_reader),
        },
    )
    os.close(commit_writer)
    os.close(release_reader)
    try:
        _send(first, _submit_request())
        ready, _, _ = select.select([commit_reader], [], [], 8)
        assert ready, "engine did not reach the post-commit response barrier"
        assert os.read(commit_reader, 1) == b"C"
        assert (data_dir / "installation-id").read_text().strip() == _INSTANCE_ID
        # The process hook waits after acceptance commits, before the response can be built.
        first.kill()
        first.wait(timeout=5)
    finally:
        os.close(commit_reader)
        os.close(release_writer)
        _stop(first)

    with closing(sqlite3.connect(data_dir / "application.db")) as connection:
        accepted = connection.execute(
            "SELECT stage, COUNT(*) FROM workflows GROUP BY stage"
        ).fetchall()
        pending = connection.execute(
            "SELECT COUNT(*) FROM jobs WHERE status = 'pending'"
        ).fetchone()[0]
    assert accepted == [("captured", 1)]
    assert pending == 1

    restarted = _start_engine(data_dir)
    try:
        _send(restarted, {"version": 1, "request_id": "req-status", "operation": "get_status"})
        status = _read_response(restarted)
        assert status["ok"]["status"]["instance_id"] == _INSTANCE_ID

        _send(
            restarted,
            {
                "version": 1,
                "request_id": "req-get",
                "operation": "get_workflow",
                "command_id": "sim-1",
            },
        )
        recovered = _read_response(restarted)
        assert recovered["ok"]["workflow"]["stage"] == "completed"
        assert len(recovered["ok"]["workflow"]["outcomes"]) == 2

        retry = _submit_request()
        retry["request_id"] = "req-retry"
        _send(restarted, retry)
        duplicate = _read_response(restarted)
        assert duplicate["ok"]["workflow"]["stage"] == "completed"
        assert len(duplicate["ok"]["workflow"]["outcomes"]) == 2

        _send(restarted, {"version": 1, "request_id": "req-stop", "operation": "stop"})
        stopped = _read_response(restarted)
        assert stopped["ok"]["type"] == "stopping"
        assert restarted.wait(timeout=8) == 0
    finally:
        _stop(restarted)

    with closing(sqlite3.connect(data_dir / "application.db")) as connection:
        persisted_instance = connection.execute(
            "SELECT value FROM engine_metadata WHERE key = 'instance_id'"
        ).fetchone()[0]
        workflows = connection.execute(
            "SELECT COUNT(*), MIN(stage), MIN(outcomes_json) FROM workflows"
        ).fetchone()
        events = connection.execute(
            "SELECT event_type, COUNT(*) FROM audit_events GROUP BY event_type ORDER BY event_type"
        ).fetchall()
    assert workflows[0] == 1
    assert workflows[1] == "completed"
    assert len(json.loads(workflows[2])) == 2
    assert persisted_instance == _INSTANCE_ID
    assert events == [
        ("SelfTestAccepted", 1),
        ("SelfTestCompleted", 1),
        ("SelfTestParsed", 1),
    ]


def test_second_process_cannot_own_the_same_installation(tmp_path):
    data_dir = tmp_path / "installation"
    first = _start_engine(data_dir)
    second: subprocess.Popen[bytes] | None = None
    try:
        _send(first, {"version": 1, "request_id": "req-ready", "operation": "get_status"})
        assert _read_response(first)["ok"]["type"] == "status"

        second = _start_engine(data_dir)
        assert second.wait(timeout=8) != 0
        assert second.stdout is not None
        assert second.stdout.read() == b""

        _send(first, {"version": 1, "request_id": "req-stop", "operation": "stop"})
        assert _read_response(first)["ok"]["type"] == "stopping"
        assert first.wait(timeout=8) == 0
    finally:
        _stop(first)
        if second is not None:
            _stop(second)


def test_overlong_line_is_rejected_and_the_next_request_still_works(tmp_path):
    process = _start_engine(tmp_path / "installation")
    try:
        assert process.stdin is not None
        process.stdin.write(b"x" * (MAX_REQUEST_LINE_BYTES + 1) + b"\n")
        process.stdin.write(b'{"version":1,"request_id":"req-status","operation":"get_status"}\n')
        process.stdin.flush()

        invalid = _read_response(process)
        status = _read_response(process)
        assert invalid["error"]["code"] == "invalid_request"
        assert status["ok"]["type"] == "status"
        assert status["ok"]["status"]["accepted"] == 0

        _send(process, {"version": 1, "request_id": "req-stop", "operation": "stop"})
        _read_response(process)
        assert process.wait(timeout=8) == 0
    finally:
        _stop(process)


def test_data_directory_refuses_a_different_persisted_identity(tmp_path):
    data_dir = tmp_path / "installation"
    first = _start_engine(data_dir)
    try:
        _send(first, {"version": 1, "request_id": "req-ready", "operation": "get_status"})
        _read_response(first)
        _send(first, {"version": 1, "request_id": "req-stop", "operation": "stop"})
        _read_response(first)
        assert first.wait(timeout=8) == 0
    finally:
        _stop(first)

    foreign = _start_engine(data_dir, "20000000-0000-4000-8000-000000000002")
    try:
        assert foreign.wait(timeout=8) != 0
        assert foreign.stdout is not None
        assert foreign.stdout.read() == b""
    finally:
        _stop(foreign)


def test_unexpected_service_error_is_fatal_without_an_ipc_error_response(tmp_path):
    hook_dir = tmp_path / "process-test-hooks"
    hook_dir.mkdir()
    (hook_dir / "sitecustomize.py").write_text(
        "from copytrading_engine.host.self_test.service import SelfTestService\n"
        "async def _fail(self, command):\n"
        "    raise RuntimeError('private internal detail')\n"
        "SelfTestService.submit = _fail\n",
        encoding="utf-8",
    )
    process = _start_engine(tmp_path / "installation", extra_pythonpath=hook_dir)
    try:
        _send(process, _submit_request())
        _wait_readable(process)
        assert process.stdout is not None
        assert process.stdout.readline() == b""
        assert process.wait(timeout=8) != 0
        assert process.stderr is not None
        diagnostics = process.stderr.read()
        assert diagnostics.strip().endswith(b"engine failed code=internal_error")
        assert b"private internal detail" not in diagnostics
    finally:
        _stop(process)
