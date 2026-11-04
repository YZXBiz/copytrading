"""Launch a relocated copy of the built app on a throwaway data folder and see its engine answer."""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from verify_desktop_bundle import verify

TIMEOUT_SECONDS = 120


def smoke_command(app: Path) -> list[str]:
    return [str(app / "Contents/MacOS/CopyTrading")]


def smoke_environment(state_root: Path) -> dict[str, str]:
    """Only the throwaway folder is named, so the app can never reach the owner's data."""
    return {**os.environ, "COPYTRADING_STATE_ROOT": str(state_root), "COPYTRADING_SMOKE": "1"}


def smoke(app: Path) -> str:
    problems = verify(app)
    if problems:
        raise ValueError("bundle verification failed: " + "; ".join(problems))
    with tempfile.TemporaryDirectory(prefix="copytrading-smoke-") as temporary:
        root = Path(temporary)
        relocated = root / app.name
        subprocess.run(["ditto", str(app), str(relocated)], check=True)
        state = root / "state"
        state.mkdir(mode=0o700)
        result = subprocess.run(
            smoke_command(relocated),
            env=smoke_environment(state),
            capture_output=True,
            text=True,
            timeout=TIMEOUT_SECONDS,
            check=False,
        )
        shutil.rmtree(relocated)
    if result.returncode != 0 or "smoke ok" not in result.stdout:
        raise ValueError(
            f"the app did not start (exit {result.returncode}): {result.stderr.strip()[-500:]}"
        )
    return result.stdout.strip()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", required=True, type=Path)
    arguments = parser.parse_args()
    try:
        print(smoke(arguments.app.resolve()))
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(f"desktop smoke failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
