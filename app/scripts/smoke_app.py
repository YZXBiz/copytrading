"""Exercise a relocated app launch and the native packaged-runtime harness."""

from __future__ import annotations

import argparse
import os
import shutil
import signal
import sqlite3
import stat
import subprocess
import sys
import tempfile
import time
import uuid
from contextlib import closing
from pathlib import Path

from verify_bundle import verify

ROOT = Path(__file__).resolve().parents[2]


def _operational_database(state: Path) -> bool:
    try:
        state_info = state.lstat()
        if not stat.S_ISDIR(state_info.st_mode) or state_info.st_uid != os.getuid():
            return False

        pointer = state / "active-generation"
        descriptor = os.open(pointer, os.O_RDONLY | os.O_NOFOLLOW)
        try:
            pointer_info = os.fstat(descriptor)
            if (
                not stat.S_ISREG(pointer_info.st_mode)
                or pointer_info.st_uid != os.getuid()
                or pointer_info.st_size <= 0
                or pointer_info.st_size > 64
            ):
                return False
            raw_identifier = os.read(descriptor, 65)
        finally:
            os.close(descriptor)
        if not raw_identifier or len(raw_identifier) > 64:
            return False
        identifier = raw_identifier.decode("ascii")
        if identifier.endswith("\n"):
            identifier = identifier[:-1]
        if not identifier or "\n" in identifier or str(uuid.UUID(identifier)).lower() != identifier:
            return False

        generations = state / "generations"
        generations_info = generations.lstat()
        if not stat.S_ISDIR(generations_info.st_mode) or generations_info.st_uid != os.getuid():
            return False
        generation = generations / identifier
        generation_info = generation.lstat()
        if (
            not stat.S_ISDIR(generation_info.st_mode)
            or generation_info.st_uid != os.getuid()
            or generation_info.st_mode & 0o077
        ):
            return False

        database = generation / "application.db"
        database_info = database.lstat()
        if not stat.S_ISREG(database_info.st_mode) or database_info.st_uid != os.getuid():
            return False
    except OSError, UnicodeDecodeError, ValueError:
        return False
    try:
        with closing(
            sqlite3.connect(database.as_uri() + "?mode=ro", uri=True, timeout=1)
        ) as connection:
            tables = connection.execute(
                "SELECT name FROM sqlite_master WHERE type='table' AND name IN "
                "('engine_metadata', 'workflows', 'jobs', 'audit_events')"
            ).fetchall()
            return len(tables) == 4 and connection.execute("PRAGMA quick_check").fetchone() == (
                "ok",
            )
    except sqlite3.Error:
        return False


def _runtime_processes(runtime: Path) -> set[int]:
    result = subprocess.run(
        ["/bin/ps", "-axo", "pid=,command="],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError("could not inspect relocated runtime processes")
    executable = str(runtime / "cpython/python/bin/python3.14")
    return {
        int(parts[0])
        for line in result.stdout.splitlines()
        if (parts := line.strip().split(maxsplit=1))
        and len(parts) == 2
        and parts[0].isdecimal()
        and parts[1].startswith(executable)
    }


def _stop_relocated_runtime(
    app_process: subprocess.Popen[bytes] | None,
    runtime: Path | None,
    owned: set[int],
) -> str | None:
    if app_process is not None and app_process.poll() is None:
        try:
            app_process.terminate()
            try:
                app_process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                app_process.kill()
                app_process.wait(timeout=5)
        except OSError, subprocess.TimeoutExpired:
            return "relocated app process did not stop"

    if runtime is None:
        return None
    try:
        live = _runtime_processes(runtime)
    except OSError, RuntimeError:
        return "could not inspect relocated runtime processes for cleanup"
    targets = live | owned

    def still_running() -> set[int]:
        try:
            return _runtime_processes(runtime) & targets
        except OSError, RuntimeError:
            return targets

    remaining = live & targets
    for pid in remaining:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        except OSError:
            return "could not stop an owned relocated runtime process"
    deadline = time.monotonic() + 10
    while remaining and time.monotonic() < deadline:
        time.sleep(0.1)
        remaining = still_running()
    if remaining:
        for pid in remaining:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            except OSError:
                return "could not stop an owned relocated runtime process"
        deadline = time.monotonic() + 5
        while remaining and time.monotonic() < deadline:
            time.sleep(0.1)
            remaining = still_running()
    if remaining:
        return "owned relocated runtime processes did not stop"
    return None


def _finish_smoke_workspace(
    temporary: Path,
    runtime: Path | None,
    owned: set[int],
    app_process: subprocess.Popen[bytes] | None,
    primary_error: BaseException | None,
) -> None:
    cleanup_error = _stop_relocated_runtime(app_process, runtime, owned)
    if cleanup_error is None:
        try:
            shutil.rmtree(temporary)
        except OSError:
            cleanup_error = "could not remove the private smoke workspace"
    if cleanup_error is None:
        return
    if primary_error is not None:
        print("desktop smoke cleanup incomplete; private state was retained", file=sys.stderr)
        return
    raise RuntimeError(cleanup_error)


def smoke(app: Path) -> None:
    problems = verify(app)
    if problems:
        raise RuntimeError("bundle verification failed: " + "; ".join(problems))
    temporary = Path(tempfile.mkdtemp(prefix="CopyTrading Relocation "))
    state = temporary / "Private State With Spaces"
    runtime: Path | None = None
    app_process: subprocess.Popen[bytes] | None = None
    owned: set[int] = set()
    try:
        relocated = temporary / "Application With Spaces" / app.name
        relocated.parent.mkdir()
        shutil.copytree(app, relocated, symlinks=True)
        if verify(relocated):
            raise RuntimeError("relocated bundle failed validation")
        resources = relocated / "Contents/Resources"
        runtime = resources / "Runtime"
        env = os.environ.copy()
        for name in tuple(env):
            if name.startswith(("UV_", "DYLD_")) or name in {
                "PYTHONPATH",
                "VIRTUAL_ENV",
                "COPYTRADING_RUNTIME_ROOT",
                "COPYTRADING_ENGINE_ROOT",
                "COPYTRADING_PYTHON_LIBRARY_PATH",
            }:
                env.pop(name, None)
        env["PATH"] = "/usr/bin:/bin"
        env["COPYTRADING_STATE_ROOT"] = str(state)
        app_process = subprocess.Popen(
            [str(relocated / "Contents/MacOS/CopyTrading")],
            env=env,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        deadline = time.monotonic() + 80
        while time.monotonic() < deadline:
            owned.update(_runtime_processes(runtime))
            if app_process.poll() is not None:
                raise RuntimeError(f"relocated app exited during startup: {app_process.returncode}")
            if _operational_database(state) and len(owned) >= 1:
                break
            time.sleep(0.25)
        else:
            raise RuntimeError("relocated app did not start its engine and SQLite")
        print("relocated app launched with private state and its engine")
        contender_log = temporary / "second-owner.stderr"
        with contender_log.open("w") as error_stream:
            contender = subprocess.Popen(
                [str(relocated / "Contents/MacOS/CopyTrading")],
                env=env,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=error_stream,
            )
            try:
                deadline = time.monotonic() + 8
                while time.monotonic() < deadline:
                    if "already running" in contender_log.read_text().lower():
                        break
                    time.sleep(0.1)
                else:
                    raise RuntimeError("second app launch did not report the installation lock")
                current_children = _runtime_processes(runtime)
                if len(current_children) != 2:
                    raise RuntimeError(
                        "second app launch changed the runtime child count: "
                        f"before={sorted(owned)}, after={sorted(current_children)}"
                    )
                print("second app launch rejected duplicate ownership")
            finally:
                contender.terminate()
                try:
                    contender.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    contender.kill()
                    contender.wait(timeout=5)

        cleanup_error = _stop_relocated_runtime(app_process, runtime, owned)
        if cleanup_error is not None:
            raise RuntimeError(cleanup_error)
        harness_env = os.environ.copy()
        harness_env.update(
            {
                "COPYTRADING_RUNTIME_ROOT": str(resources / "Runtime"),
                "COPYTRADING_ENGINE_ROOT": str(resources / "Engine"),
                "COPYTRADING_PYTHON_LIBRARY_PATH": str(
                    resources / "Runtime/cpython/python/lib/python3.14/site-packages"
                ),
            }
        )
        subprocess.run(
            [
                "arch",
                "-arm64",
                "swift",
                "test",
                "--package-path",
                str(ROOT / "app"),
                "--filter",
                "managedNativeRuntime",
            ],
            env=harness_env,
            check=True,
            timeout=600,
        )
        print("relocated runtime completed a two-destination self-test and owned Stop")
    finally:
        _finish_smoke_workspace(
            temporary,
            runtime,
            owned,
            app_process,
            sys.exc_info()[1],
        )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True)
    arguments = parser.parse_args()
    try:
        smoke(arguments.app.resolve())
    except (
        OSError,
        RuntimeError,
        subprocess.CalledProcessError,
        subprocess.TimeoutExpired,
    ) as error:
        print(f"desktop smoke failed: {error}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
