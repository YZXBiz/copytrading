from __future__ import annotations

import sys
from pathlib import Path

import pytest

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
import doctor  # noqa: E402 - importable only after the scripts directory is on sys.path


class FakeProbe(doctor.Probe):
    def __init__(
        self,
        *,
        system: str = "Darwin",
        version: str = "26.6.2",
        commands: dict[str, str] | None = None,
        runs: dict[str, tuple[int, str]] | None = None,
    ) -> None:
        self._system = system
        self._version = version
        self._commands = commands if commands is not None else {"uv": "/opt/bin/uv"}
        self._runs = runs if runs is not None else {}

    def system(self) -> str:
        return self._system

    def macos_version(self) -> str:
        return self._version

    def which(self, command: str) -> str | None:
        return self._commands.get(command)

    def run(self, command: list[str]) -> tuple[int, str]:
        return self._runs.get(" ".join(command), (127, ""))


HEALTHY_RUNS = {
    "sysctl -n hw.optional.arm64": (0, "1"),
    f"uv python find {doctor.PYTHON_REQUEST}": (0, "/py/bin/python3"),
    "xcode-select -p": (0, "/Applications/Xcode.app/Contents/Developer"),
    "arch -arm64 swift --version": (0, "Apple Swift version 6.4\nTarget: arm64"),
}


def test_a_ready_mac_passes_every_check() -> None:
    findings = doctor.run_checks(FakeProbe(runs=HEALTHY_RUNS))

    assert [finding.passed for finding in findings] == [True] * 5
    assert "ready to build" in doctor.render(findings)


@pytest.mark.parametrize(
    ("version", "passes"),
    [("26.0", True), ("27.1", True), ("15.5", False), ("", False), ("beta", False)],
)
def test_macos_needs_version_26_or_later(version: str, passes: bool) -> None:
    assert doctor.check_macos(FakeProbe(version=version)).passed is passes


def test_other_operating_systems_are_refused() -> None:
    finding = doctor.check_macos(FakeProbe(system="Linux"))

    assert not finding.passed
    assert finding.fix == "CopyTrading is a macOS app."


def test_intel_macs_are_refused() -> None:
    finding = doctor.check_apple_silicon(FakeProbe(runs={"sysctl -n hw.optional.arm64": (0, "0")}))

    assert not finding.passed


def test_missing_uv_says_how_to_install_it_and_defers_the_python_check() -> None:
    probe = FakeProbe(commands={}, runs=HEALTHY_RUNS)

    assert doctor.check_uv(probe).fix == "Install it: brew install uv"
    assert not doctor.check_python(probe).passed


def test_missing_python_names_the_exact_install_command() -> None:
    finding = doctor.check_python(FakeProbe(runs={}))

    assert finding.fix == f"Install it: uv python install {doctor.PYTHON_REQUEST}"


def test_xcode_fails_when_the_toolchain_or_swift_is_missing() -> None:
    assert not doctor.check_xcode(FakeProbe(runs={})).passed
    assert not doctor.check_xcode(FakeProbe(runs={"xcode-select -p": (0, "/x")})).passed


def test_failures_are_counted_and_reported() -> None:
    findings = doctor.run_checks(FakeProbe(commands={}, runs={}))
    output = doctor.render(findings)

    assert "FAIL" in output
    assert "problems to fix" in output
    assert not all(finding.passed for finding in findings)
