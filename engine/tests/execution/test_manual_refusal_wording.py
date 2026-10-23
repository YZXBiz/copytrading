"""Every refusal the by-hand flow can send reads as one plain line, in both languages.

The engine's codes are collected from its own source, so a new refusal fails here until the app
has words for it.
"""

import ast
import re
from pathlib import Path
from typing import get_args

import pytest

from copytrading_engine.execution.domain.manual_commands import (
    MANUAL_REFUSAL_REASONS,
    ManualCommandResult,
)

ROOT = Path(__file__).resolve().parents[3]
SRC = ROOT / "engine" / "src" / "copytrading_engine"
WORDING = (
    ROOT / "app" / "Sources" / "CopyTrading" / "Features" / "Activity" / "ManualRefusalText.swift"
)
CATALOGS = ROOT / "app" / "Sources" / "AppLocalizationCore" / "Resources"
ENTRY = re.compile(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)";$')
CJK = re.compile(r"[一-鿿]")

# Not a refusal the flow shows: a success, a warning it does not show, the hold for approval
# that a copy by hand has already passed, and a preview's note that a call names no size (the
# flow sizes it with the account's largest single buy).
NOT_A_REFUSAL = {"ready", "plan_unavailable", "approval_required", "unsized_buy"}
# Codes the engine derives where they are read, not where they are written down.
DERIVED = {"not_sent", "broker_rejected", "uncertain", "record_failed", "account_unavailable"}


def table() -> dict[str, str]:
    source = WORDING.read_text()
    block = source[source.index("private static let known") :]
    return dict(re.findall(r'^\s+"([a-z_]+)": "((?:[^"\\]|\\.)*)",$', block, re.MULTILINE))


def catalog(language: str) -> dict[str, str]:
    path = CATALOGS / f"{language}.lproj" / "Localizable.strings"
    return {m[1]: m[2] for line in path.read_text().splitlines() if (m := ENTRY.match(line))}


def strings(node: ast.AST) -> set[str]:
    return {
        n.value
        for n in ast.walk(node)
        if isinstance(n, ast.Constant)
        and isinstance(n.value, str)
        and re.fullmatch(r"[a-z_]+", n.value)
    }


def returned(node: ast.AST | None) -> set[str]:
    """The words a `return` can hand back: a literal, or either side of a conditional."""
    if isinstance(node, ast.IfExp):
        return returned(node.body) | returned(node.orelse)
    if isinstance(node, ast.Constant):
        return strings(node)
    return set()


def written_in(relative: str, functions: set[str]) -> set[str]:
    """The reason words a function returns, appends, or passes to a decision."""
    tree = ast.parse((SRC / relative).read_text())
    found: set[str] = set()
    for fn in ast.walk(tree):
        if not isinstance(fn, ast.FunctionDef | ast.AsyncFunctionDef) or fn.name not in functions:
            continue
        for node in ast.walk(fn):
            if isinstance(node, ast.Return):
                found |= returned(node.value)
            elif isinstance(node, ast.Call):
                name = getattr(node.func, "id", getattr(node.func, "attr", ""))
                if name in {"TradeDecision", "BudgetDecision"} and len(node.args) > 1:
                    found |= strings(node.args[1])
                elif name == "append" and node.args and isinstance(node.args[0], ast.Constant):
                    found |= strings(node.args[0])
                for keyword in node.keywords:
                    if keyword.arg == "reason":
                        found |= strings(keyword.value)
            elif isinstance(node, ast.Assign) and any(
                getattr(target, "id", "") in {"quote_reason", "decision_failure"}
                for target in node.targets
            ):
                found |= strings(node.value)
    return found


def emitted() -> set[str]:
    codes = set(MANUAL_REFUSAL_REASONS) | DERIVED
    codes |= written_in(
        "execution/application/manual_commands.py", {"_confirmation_block", "_evaluate"}
    )
    codes |= written_in("execution/application/engine.py", {"decide", "_market_bid"})
    codes |= written_in(
        "execution/domain/risk.py", {"entry_budget", "requested_entry_budget", "_asked"}
    )
    # Built from the scope that was breached.
    codes |= {"symbol_exposure_cap", "total_exposure_cap", "symbol_and_total_exposure_cap"}
    codes |= written_in("execution/domain/ownership.py", {"account_activity_reason"})
    codes |= written_in("execution/domain/pricing.py", {"quote_problem"})
    codes |= written_in("execution/adapters/resources.py", {"entry_block_reason"})
    return codes - NOT_A_REFUSAL


def test_every_code_the_flow_can_send_has_a_line():
    assert sorted(emitted() - set(table())) == []


def test_no_line_words_a_code_the_flow_cannot_send():
    assert sorted(set(table()) - emitted()) == []


@pytest.mark.parametrize("language", ["en", "zh-Hans"])
def test_every_line_is_in_the_catalogs(language):
    entries = catalog(language)
    assert sorted(text for text in table().values() if text not in entries) == []


def test_every_line_is_translated_and_fits_one_line():
    chinese = catalog("zh-Hans")
    untranslated = [text for text in table().values() if not CJK.search(chinese[text])]
    assert untranslated == []
    assert [text for text in table().values() if len(text) > 72] == []
    assert [text for text in table().values() if len(chinese[text]) > 42] == []


def test_a_line_says_what_to_do_unless_nothing_can_be_done():
    final = {"waiting_expired", "post_ignored", "quote_above_limit"}
    advice = (
        *("Try", "Review", "Close", "Check", "Start", "Wait", "Settle", "Raise", "Turn"),
        *("Lower", "Change", "Name", "Let", "Resume", "See"),
    )
    plain = [
        code
        for code, text in table().items()
        if code not in final and not any(word in text for word in advice)
    ]
    assert plain == []


@pytest.mark.parametrize("language", ["en", "zh-Hans"])
def test_every_order_status_the_sheet_names_is_in_the_catalogs(language):
    """The status beside an order reads as its humanized code, looked up in the catalog."""
    statuses = get_args(ManualCommandResult.model_fields["status"].annotation)
    words = {status.replace("_", " ").capitalize() for status in statuses} | {"Pending", "Failed"}
    entries = catalog(language)
    assert sorted(word for word in words if word not in entries) == []
