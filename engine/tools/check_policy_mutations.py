"""Run selected policy mutations only in disposable source/test copies.

This is a focused regression probe, not a repository-wide mutation score. A clean
baseline must pass first; collection errors and timeouts never count as killed mutants.
"""

import argparse
import json
import os
import shutil
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
CONTRACTS = PROJECT.parent / "app" / "Resources" / "Contracts"
EXECUTION_TESTS = (
    "execution/test_order_flow.py",
    "execution/test_sizing.py",
    "execution/test_entry_guards.py",
    "execution/test_risk.py",
    "execution/test_pricing.py",
    "execution/test_ledger.py",
)
SIZING_TESTS = (*EXECUTION_TESTS, "execution/test_sizing_properties.py")
OWNERSHIP_TESTS = (
    "execution/test_external_ownership.py",
    "execution/test_ownership_properties.py",
)
REDACTION_TESTS = ("diagnostics/test_redaction.py", "diagnostics/test_redaction_properties.py")
CONTROL_TESTS = (
    "control/test_policy.py",
    "control/test_proposals.py",
    "control/test_service.py",
)


@dataclass(frozen=True)
class Mutation:
    name: str
    module: str
    before: str
    after: str
    tests: tuple[str, ...] = EXECUTION_TESTS


MUTATIONS = (
    Mutation(
        "agent resume treated as safe",
        "control/policy",
        'case "pause_processing" | "pause_account":',
        'case "pause_processing" | "pause_account" | "propose_resume_account":',
        CONTROL_TESTS,
    ),
    Mutation(
        "locked app serves reads",
        "control/policy",
        """    if not unlocked:
        return Refuse("locked")""",
        """    if False:
        return Refuse("locked")""",
        CONTROL_TESTS,
    ),
    Mutation(
        "approval ignores the shown digest",
        "control/proposals",
        "if approved_digest != proposal.digest:",
        "if False:",
        CONTROL_TESTS,
    ),
    Mutation(
        "approval accepted twice",
        "control/proposals",
        """        if not isinstance(proposal.state, Pending):
            raise ProposalRefused("conflict")
        if approved_digest""",
        """        if False:
            raise ProposalRefused("conflict")
        if approved_digest""",
        CONTROL_TESTS,
    ),
    Mutation(
        "flood blocks pausing",
        "control/service",
        'if kind != "safer" and not self._rate.admit(self._clock()):',
        "if not self._rate.admit(self._clock()):",
        CONTROL_TESTS,
    ),
    Mutation(
        "loss cap equality",
        "execution/domain/risk",
        "<= -config.daily_loss_cap_usd",
        "< -config.daily_loss_cap_usd",
    ),
    Mutation(
        "daily count equality",
        "execution/domain/risk",
        ">= config.max_entries_per_day",
        "> config.max_entries_per_day",
    ),
    Mutation(
        "symbol cap equality",
        "execution/domain/risk",
        "+ budget > config.max_symbol_usd",
        "+ budget >= config.max_symbol_usd",
    ),
    Mutation(
        "total cap equality",
        "execution/domain/risk",
        "+ budget > config.max_total_usd",
        "+ budget >= config.max_total_usd",
    ),
    Mutation("budget minimum", "execution/domain/risk", "budget = min(", "budget = max("),
    Mutation("cash equality", "execution/domain/risk", "if budget > min(", "if budget >= min("),
    Mutation(
        "approval gate dropped",
        "execution/application/engine",
        "if c.approve_orders and not manual:",
        "if False and not manual:",
        ("execution/test_order_approval.py",),
    ),
    Mutation(
        "owner's own order held for approval again",
        "execution/application/engine",
        "if c.approve_orders and not manual:",
        "if c.approve_orders:",
        ("execution/test_lot_sales.py",),
    ),
    Mutation(
        "exit sells above the signal",
        "execution/domain/pricing",
        "floor = signal_price * (Decimal(1) - self.max_below_signal_pct",
        "floor = signal_price * (Decimal(1) + self.max_below_signal_pct",
    ),
    Mutation(
        "review drops the route's guru",
        "parsing/worker",
        "guru_id=route.guru_id if route is not None else None,",
        "guru_id=None,",
        ("trading/runtime/test_isolation.py",),
    ),
    Mutation(
        "cumulative fill delta",
        "execution/application/ledger",
        "delta = update.filled_qty - order.filled_qty",
        "delta = update.filled_qty",
    ),
    Mutation(
        "fraction applied twice",
        "execution/domain/risk",
        "exact = (connection.full_position_usd * fraction)",
        "exact = (connection.full_position_usd * fraction * fraction)",
        SIZING_TESTS,
    ),
    Mutation(
        "default fraction ignored",
        "execution/domain/risk",
        "if source_fraction is not None else connection.default_fraction",
        "if source_fraction is not None else None",
        SIZING_TESTS,
    ),
    Mutation(
        "sizing ignores the fraction",
        "execution/domain/risk",
        "exact = (connection.full_position_usd * fraction)",
        "exact = (connection.full_position_usd)",
        SIZING_TESTS,
    ),
    Mutation(
        "budget rounds up",
        "execution/domain/risk",
        'requested = exact.quantize(Decimal("0.01"), rounding=ROUND_DOWN)',
        'requested = exact.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)',
        SIZING_TESTS,
    ),
    Mutation(
        "resolution conservation",
        "execution/domain/ownership",
        "if self.external_qty + sum(self.lot_remaining.values()) != self.broker_qty:",
        "if False:",
        OWNERSHIP_TESTS,
    ),
    Mutation(
        "invented app shares",
        "execution/application/ledger",
        "if target > before.remaining_qty:",
        "if False:",
        OWNERSHIP_TESTS,
    ),
    Mutation(
        "unpadded url-safe base64 secret form",
        "diagnostics/redaction",
        'base64.urlsafe_b64encode(encoded).decode("ascii").rstrip("="),',
        "",
        REDACTION_TESTS,
    ),
    Mutation("hex secret form", "diagnostics/redaction", "encoded.hex(),", "", REDACTION_TESTS),
    Mutation(
        "lowercase percent secret form",
        "diagnostics/redaction",
        '_lower_percent_escapes(quote(secret, safe="")),',
        "",
        REDACTION_TESTS,
    ),
    Mutation(
        "html secret form",
        "diagnostics/redaction",
        "html.escape(secret, quote=True),",
        "",
        REDACTION_TESTS,
    ),
)


def run_tests(directory: Path, tests: tuple[str, ...]) -> subprocess.CompletedProcess[str]:
    env = os.environ | {"PYTHONPATH": str(directory / "src"), "PYTHONDONTWRITEBYTECODE": "1"}
    return subprocess.run(
        [
            str(PROJECT / ".venv/bin/python"),
            "-m",
            "pytest",
            "-q",
            "--tb=short",
            "-p",
            "no:cacheprovider",
        ]
        + [str(directory / "tests" / name) for name in tests],
        cwd=directory,
        env=env,
        capture_output=True,
        text=True,
        timeout=300,
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, help="Optional JSON evidence file")
    args = parser.parse_args()
    results = []
    with tempfile.TemporaryDirectory(prefix="copier-mutations-") as temporary:
        # Mirror the repository layout so tests find the app's contract fixtures.
        directory = Path(temporary) / "engine"
        shutil.copytree(CONTRACTS, Path(temporary) / CONTRACTS.relative_to(PROJECT.parent))
        for name in ("src", "tests"):
            shutil.copytree(
                PROJECT / name, directory / name, ignore=shutil.ignore_patterns("__pycache__")
            )
        shutil.copy2(PROJECT / "pyproject.toml", directory / "pyproject.toml")
        baseline = run_tests(
            directory, tuple(sorted({test for mutation in MUTATIONS for test in mutation.tests}))
        )
        if baseline.returncode:
            print("Baseline failed; mutation results would be invalid.")
            print(baseline.stdout + baseline.stderr)
            return 2
        print("Baseline passed", flush=True)
        for mutation in MUTATIONS:
            path = directory / "src/copytrading_engine" / f"{mutation.module}.py"
            original = path.read_text()
            if original.count(mutation.before) != 1:
                raise RuntimeError(f"Mutation anchor changed: {mutation.name}")
            path.write_text(original.replace(mutation.before, mutation.after))
            try:
                outcome = run_tests(directory, mutation.tests)
            finally:
                path.write_text(original)
            status = {0: "survived", 1: "killed"}.get(outcome.returncode, "error")
            results.append(
                {"name": mutation.name, "status": status, "exit_code": outcome.returncode}
            )
            print(f"{status}: {mutation.name}", flush=True)
            if status == "error":
                print(outcome.stdout + outcome.stderr)
    if args.output:
        args.output.write_text(
            json.dumps({"baseline": "passed", "mutations": results}, indent=2) + "\n"
        )
    return int(any(result["status"] != "killed" for result in results))


if __name__ == "__main__":
    raise SystemExit(main())
