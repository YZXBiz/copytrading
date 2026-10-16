"""Words drawn in capitals are spoken as written.

VoiceOver reads what a text draws. `String.uppercased()` hands it "READ AS" and "5 S", and even
`.textCase(.uppercase)` reaches it as capitals for a heading or a lone label, so each text drawn in
capitals names itself with `.accessibilityLabel` (or is hidden behind an element that does)."""

import re
from pathlib import Path

SOURCES = Path(__file__).resolve().parents[2] / "Sources" / "CopyTrading"
UPPERCASED_TEXT = re.compile(r"\bText\([^\n]*\.uppercased\(\)\s*\)")


def chains(source: str):
    """Each `.textCase(.uppercase)` with the modifier chain around it, as text."""
    lines = source.split("\n")
    for number, line in enumerate(lines):
        if ".textCase(.uppercase)" not in line:
            continue
        start = number
        while start > 0 and lines[start].lstrip().startswith("."):
            start -= 1
        end = number
        while end + 1 < len(lines) and lines[end + 1].lstrip().startswith("."):
            end += 1
        yield number + 1, "\n".join(lines[start : end + 1])


def unspoken(source: str) -> list[str]:
    found = [
        f"line {source[: m.start()].count(chr(10)) + 1}: uppercased()"
        for m in UPPERCASED_TEXT.finditer(source)
    ]
    for number, chain in chains(source):
        if ".accessibilityLabel(" not in chain and ".accessibilityHidden(true)" not in chain:
            found.append(f"line {number}: textCase without a spoken label")
    return found


def test_capitals_are_spoken_as_written():
    problems = sorted(
        f"{path.relative_to(SOURCES)} {problem}"
        for path in SOURCES.rglob("*.swift")
        for problem in unspoken(path.read_text())
    )
    assert problems == []


def test_the_check_finds_capitals_without_words():
    source = (
        "Text(title.uppercased())\n"
        "Text(title)\n    .textCase(.uppercase)\n    .font(.caption)\n"
        "Text(title)\n    .accessibilityLabel(title)\n    .textCase(.uppercase)\n"
        "Label(done)\n    .textCase(.uppercase)\n    .accessibilityHidden(true)\n"
    )
    assert unspoken(source) == ["line 1: uppercased()", "line 3: textCase without a spoken label"]
