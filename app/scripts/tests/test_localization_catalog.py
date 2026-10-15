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


def test_chinese_calls_a_guru_by_one_name():
    # A guru is 信号源 everywhere; 老师, 导师 and 达人 were tried and rejected by the owner.
    rejected = ("老师", "导师", "达人")
    chinese = load("zh-Hans")
    others = [key for key, value in chinese.items() if any(word in value for word in rejected)]
    assert others == []


def test_chinese_calls_a_call_by_one_name():
    # A guru's call is 喊单; 信号 is kept for the guru (信号源) and the signal's price and age.
    call = re.compile(r"\bcalls?\b", re.IGNORECASE)
    signal = re.compile(r"信号(?!源|价|时|最长)")
    chinese = load("zh-Hans")
    others = [
        key
        for key, value in chinese.items()
        if call.search(key) and "model call" not in key and signal.search(value)
    ]
    assert others == []


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
# A text chosen by a condition: `L10n.string(isSell ? "Sell %@" : "Buy %@", symbol)`.
TERNARY = re.compile(r"L10n\.string\([^\"()\n]*\?\s*" + LITERAL + r"\s*:\s*" + LITERAL)


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
        found |= {
            (path.name, text) for match in TERNARY.finditer(source) for text in match.groups()
        }
    missing = sorted(
        f"{name}: {text}" for name, text in found if "\\(" not in text and text not in english
    )
    assert missing == []


# An error's own words: shown through `AppModel.userMessage(for:)`, which looks them up.
ERROR_TEXT = re.compile(r"var errorDescription: String\? \{\n(.*?)\n    \}\n", re.S)


def test_every_error_the_app_can_show_is_in_the_catalogs():
    english = load("en")
    missing = sorted(
        f"{path.name}: {text}"
        for path in (SOURCES.parent).rglob("*.swift")
        for body in ERROR_TEXT.finditer(path.read_text())
        for text in re.findall(LITERAL, body.group(1))
        if text and "\\(" not in text and text not in english
    )
    assert missing == []
