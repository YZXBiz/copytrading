"""The assistant reads engine codes in the app's words, so the two tables must agree."""

import re
from decimal import Decimal
from pathlib import Path

from copytrading_engine.assistant.wording import REASONS, money, plain

REASON_SWIFT = (
    Path(__file__).resolve().parents[3]
    / "app"
    / "Sources"
    / "CopyTrading"
    / "DesignSystem"
    / "Reason.swift"
)


def app_reasons() -> dict[str, str]:
    source = REASON_SWIFT.read_text()
    block = source[source.index("static let known") :]
    block = block[: block.index("\n    ]")]
    return dict(re.findall(r'^\s+"([a-z_]+)": "((?:[^"\\]|\\.)*)",?$', block, re.MULTILINE))


def test_the_assistant_uses_the_apps_words_for_every_reason():
    assert app_reasons() == REASONS


def test_an_unknown_code_never_reads_as_snake_case():
    assert plain("some_new_code") == "some new code"
    assert plain(None) is None


def test_money_reads_as_dollars():
    assert money(Decimal("9428.2")) == "$9,428.20"
    assert money(Decimal("-96.28")) == "-$96.28"
