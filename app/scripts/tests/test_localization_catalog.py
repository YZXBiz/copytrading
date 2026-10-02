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
