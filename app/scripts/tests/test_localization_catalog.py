"""The two Localizable.strings catalogs must stay in step, or 简体中文 shows English text."""

import re
from pathlib import Path

RESOURCES = Path(__file__).resolve().parents[2] / "Sources" / "AppLocalizationCore" / "Resources"
ENTRY = re.compile(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)";\s*$')
SPECIFIER = re.compile(r"%(?:\d+\$)?(?:lld|ld|d|@|f|\.\d+f)")


def load(language: str) -> dict[str, str]:
    entries: dict[str, str] = {}
    path = RESOURCES / f"{language}.lproj" / "Localizable.strings"
    for number, line in enumerate(path.read_text().splitlines(), 1):
        if not line.strip():
            continue
        match = ENTRY.match(line)
        assert match, f"{language} line {number} is not a catalog entry: {line[:80]}"
        assert match.group(1) not in entries, f"{language} repeats {match.group(1)!r}"
        entries[match.group(1)] = match.group(2)
    return entries


def test_both_catalogs_have_the_same_keys():
    english, chinese = load("en"), load("zh-Hans")
    assert sorted(set(english) - set(chinese)) == []
    assert sorted(set(chinese) - set(english)) == []


def test_translations_keep_every_placeholder_of_their_key():
    chinese = load("zh-Hans")
    broken = [
        key
        for key, value in chinese.items()
        if sorted(SPECIFIER.findall(key)) != sorted(SPECIFIER.findall(value))
    ]
    assert broken == []


def test_chinese_text_has_no_doubled_words():
    doubled = [key for key, value in load("zh-Hans").items() if "AI AI" in value]
    assert doubled == []


SOURCES = Path(__file__).resolve().parents[2] / "Sources" / "CopyTrading"
LITERAL = r'"((?:[^"\\]|\\.)*)"'
# The calls that look their text up in the catalogs, with the text written in place.
LOOKUPS = (
    # A single-line text; a triple-quoted one is read by MULTILINE below.
    re.compile(r"L10n\.string\(\s*\"(?!\"\")((?:[^\"\\]|\\.)*)\""),
    re.compile(r"SetupSectionHeader\(\s*title:\s*" + LITERAL),
    re.compile(r"SetupSectionHeader\([^)]*?detail:\s*" + LITERAL, re.S),
)


MULTILINE = re.compile(r'L10n\.string\(\s*"""\n(.*?)"""', re.S)


def multiline_text(raw: str) -> str:
    """A Swift multi-line string's text: indentation dropped, a trailing backslash joins lines."""
    lines = [line.strip() for line in raw.split("\n")]
    return re.sub(r"\\\n", "", "\n".join(lines)).strip()


def test_every_text_the_app_asks_for_is_in_the_catalogs():
    english = load("en")
    found: set[tuple[str, str]] = set()
    for path in SOURCES.rglob("*.swift"):
        source = path.read_text()
        for lookup in LOOKUPS:
            found |= {(path.name, match.group(1)) for match in lookup.finditer(source)}
        found |= {
            (path.name, multiline_text(match.group(1))) for match in MULTILINE.finditer(source)
        }
    missing = sorted(
        f"{name}: {text}" for name, text in found if "\\(" not in text and text not in english
    )
    assert missing == []
