"""What VoiceOver speaks and a tooltip shows is looked up in the catalogs like every other text.

SwiftUI's own lookup reads the app bundle, but the app's words live in AppLocalizationCore, so a
literal handed straight to `.accessibilityLabel` or `.help` stays English in 简体中文."""

import re
from pathlib import Path

SOURCES = Path(__file__).resolve().parents[2] / "Sources" / "CopyTrading"
SPOKEN = re.compile(r"\.(accessibilityLabel|accessibilityValue|accessibilityHint|help)\(")
INTERPOLATION = re.compile(r"\\\((?:[^()]|\([^()]*\))*\)")


def argument(source: str, start: int) -> str:
    """The argument from `start` to its closing paren, with nested calls blanked out."""
    depth, kept, position = 0, [], start
    while position < len(source):
        char = source[position]
        if char == '"':
            end = position + 1
            while source[end] != '"':
                end += 2 if source[end] == "\\" else 1
            if depth == 0:
                kept.append(source[position : end + 1])
            position = end + 1
            continue
        if char == "(":
            depth += 1
        elif char == ")":
            if depth == 0:
                return "".join(kept)
            depth -= 1
        position += 1
    return "".join(kept)


def raw_words(source: str) -> list[str]:
    """Literals spoken as written: words outside any lookup call or interpolation."""
    found = []
    for match in SPOKEN.finditer(source):
        for literal in re.findall(r'"((?:[^"\\]|\\.)*)"', argument(source, match.end())):
            if re.search(r"[A-Za-z]", INTERPOLATION.sub("", literal)):
                found.append(literal)
    return found


def test_spoken_text_is_looked_up():
    raw = sorted(
        f"{path.name}: {text}"
        for path in SOURCES.rglob("*.swift")
        for text in raw_words(path.read_text())
    )
    assert raw == []


def test_the_check_reads_choices_and_skips_lookups():
    source = (
        '.accessibilityLabel(flag ? "Start" : "Previous close")\n'
        '.accessibilityLabel(L10n.string(flag ? "Shown" : "Hidden"))\n'
        '.accessibilityValue(Humanize.count(days, "day"))\n'
        '.accessibilityLabel("\\(index + 1). \\(L10n.string(title))")\n'
        '.help("Refresh now")\n'
    )
    assert raw_words(source) == ["Start", "Previous close", "Refresh now"]
