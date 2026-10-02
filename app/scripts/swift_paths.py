"""Where `swift build` put its products; the folder differs between Xcode and Command Line Tools."""

from __future__ import annotations

import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def swift_bin_path() -> Path:
    result = subprocess.run(
        [
            "arch",
            "-arm64",
            "swift",
            "build",
            "--package-path",
            str(ROOT / "app"),
            "--show-bin-path",
        ],
        capture_output=True,
        text=True,
        check=True,
    )
    return Path(result.stdout.strip())
