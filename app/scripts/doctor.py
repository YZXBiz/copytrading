"""Check that this Mac can build and run CopyTrading, and say how to fix what it cannot.

Runs on the stock macOS python3 before the pinned Python 3.14 exists, so it uses only the
standard library and syntax that older interpreters accept.
"""

from __future__ import annotations

import platform
import shutil
import subprocess
import sys
from dataclasses import dataclass

MINIMUM_MACOS = 26
PYTHON_REQUEST = "cpython-3.14-macos-aarch64-none"


@dataclass(frozen=True)
class Finding:
    name: str
    detail: str
    fix: str | None = None

    @property
    def passed(self) -> bool:
        return self.fix is None


class Probe:
    """The machine facts the checks read; tests substitute their own."""

    def system(self) -> str:
        return platform.system()

    def macos_version(self) -> str:
        return platform.mac_ver()[0]

    def which(self, command: str) -> str | None:
        return shutil.which(command)

    def run(self, command: list[str]) -> tuple[int, str]:
        try:
            result = subprocess.run(command, capture_output=True, text=True, check=False)
        except OSError:
            return 127, ""
        return result.returncode, result.stdout.strip()


def check_macos(probe: Probe) -> Finding:
    name = "macOS"
    if probe.system() != "Darwin":
        return Finding(name, probe.system() or "unknown", "CopyTrading is a macOS app.")
    version = probe.macos_version()
    major = version.split(".")[0]
    if not major.isdigit() or int(major) < MINIMUM_MACOS:
        return Finding(
            name,
            version or "unknown",
            f"Update to macOS {MINIMUM_MACOS} or later (System Settings → Software Update).",
        )
    return Finding(name, version)


def check_apple_silicon(probe: Probe) -> Finding:
    name = "Apple Silicon"
    code, output = probe.run(["sysctl", "-n", "hw.optional.arm64"])
    if code != 0 or output != "1":
        return Finding(name, "Intel Mac", "CopyTrading needs an Apple Silicon Mac (M1 or later).")
    return Finding(name, "arm64")


def check_uv(probe: Probe) -> Finding:
    name = "uv"
    path = probe.which("uv")
    if path is None:
        return Finding(name, "not found", "Install it: brew install uv")
    return Finding(name, path)


def check_python(probe: Probe) -> Finding:
    name = "Python 3.14 (arm64)"
    if probe.which("uv") is None:
        return Finding(name, "needs uv first", "Install uv, then re-run.")
    code, output = probe.run(["uv", "python", "find", PYTHON_REQUEST])
    if code != 0 or not output:
        return Finding(name, "not found", f"Install it: uv python install {PYTHON_REQUEST}")
    return Finding(name, output)


def check_xcode(probe: Probe) -> Finding:
    name = "Xcode toolchain"
    code, _ = probe.run(["xcode-select", "-p"])
    if code != 0:
        return Finding(name, "not found", "Install it: xcode-select --install")
    code, output = probe.run(["arch", "-arm64", "swift", "--version"])
    if code != 0:
        return Finding(
            name,
            "swift does not run",
            "Install Xcode or the Command Line Tools: xcode-select --install",
        )
    return Finding(name, output.splitlines()[0] if output else "swift")


def run_checks(probe: Probe) -> list[Finding]:
    return [
        check_macos(probe),
        check_apple_silicon(probe),
        check_uv(probe),
        check_python(probe),
        check_xcode(probe),
    ]


def render(findings: list[Finding]) -> str:
    width = max(len(finding.name) for finding in findings)
    lines = []
    for finding in findings:
        mark = "ok  " if finding.passed else "FAIL"
        lines.append(f"  {mark} {finding.name.ljust(width)}  {finding.detail}")
        if finding.fix:
            lines.append(f"       {' ' * width}  → {finding.fix}")
    failed = sum(1 for finding in findings if not finding.passed)
    lines.append("")
    lines.append(
        "This Mac is ready to build CopyTrading."
        if failed == 0
        else f"{failed} problem{'s' if failed != 1 else ''} to fix before building."
    )
    return "\n".join(lines)


def main() -> int:
    findings = run_checks(Probe())
    print(render(findings))
    return 0 if all(finding.passed for finding in findings) else 1


if __name__ == "__main__":
    sys.exit(main())
