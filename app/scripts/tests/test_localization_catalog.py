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
# Other views that take a catalog key as an argument, with the text written in place.
LOOKUPS = (
    re.compile(r"SetupSectionHeader\(\s*title:\s*" + LITERAL),
    re.compile(r"SetupSectionHeader\([^)]*?detail:\s*" + LITERAL, re.S),
)
CALL = re.compile(r"\bL10n\.(string|sentence)\(")
OPENERS, CLOSERS = "([{", ")]}"


def multiline_text(raw: str) -> str:
    """A Swift multi-line string's text: indentation dropped, a trailing backslash joins lines."""
    lines = [line.strip() for line in raw.split("\n")]
    return re.sub(r"\\\n", "", "\n".join(lines)).strip()


def skip_string(source: str, index: int) -> tuple[int, str | None]:
    """The end of the string literal starting at `index`, and its text (None if it interpolates)."""
    if source.startswith('"""', index):
        end = source.index('"""', index + 3)
        raw = source[index + 3 : end]
        return end + 3, None if "\\(" in raw else multiline_text(raw.lstrip("\n"))
    position, depth, interpolates = index + 1, 0, False
    while True:
        char = source[position]
        if depth == 0 and char == "\\":
            if source[position + 1] == "(":
                interpolates, depth, position = True, 1, position + 2
                continue
            position += 2
            continue
        if depth > 0:
            if char == '"':
                position, _ = skip_string(source, position)
                continue
            depth += {"(": 1, ")": -1}.get(char, 0)
            position += 1
            continue
        if char == '"':
            return position + 1, None if interpolates else source[index + 1 : position]
        position += 1


Literal = tuple[int, str | None, int, int]  # bracket depth, text, start, end


def scan(source: str, start: int, stop: str) -> tuple[int, list[Literal]]:
    """From `start`, the index where `stop` ends the expression at depth zero (a top-level comma
    or the closing paren for an argument; a newline for a statement), and every string literal on
    the way with its bracket depth. Strings and comments never end it."""
    position, depth, literals = start, 0, []
    while position < len(source):
        char = source[position]
        if source.startswith("//", position):
            position = source.index("\n", position)
            continue
        if source.startswith("/*", position):
            position = source.index("*/", position) + 2
            continue
        if char == '"':
            end, text = skip_string(source, position)
            literals.append((depth, text, position, end))
            position = end
            continue
        if depth == 0 and (char in stop or (char == ")" and ")" in stop)):
            return position, literals
        if char in OPENERS:
            depth += 1
        elif char in CLOSERS:
            depth -= 1
        position += 1
    return position, literals


def initializer(source: str, name: str) -> tuple[int, list[Literal]]:
    """The literals a local `let` or `var` of this name is set to, through any choice or switch."""
    found: list[Literal] = []
    for match in re.finditer(r"\b(?:let|var)\s+" + re.escape(name) + r"\b[^=\n{]*=(?!=)", source):
        found += chosen(source, match.end(), scan(source, match.end(), "\n"))
    return 0, found


def chosen(source: str, start: int, scanned: tuple[int, list[Literal]]) -> list[Literal]:
    """The literals an expression can evaluate to: its branches, never a condition it tests
    (`text == "true" ? …`) or a piece it joins (`singular + "s"`)."""
    end, literals = scanned
    expression = source[start:end]
    # The ternary's `?` at depth zero, not `??`; literals before it are the condition.
    question = None
    depth, position = 0, 0
    while position < len(expression):
        char = expression[position]
        if char == '"':
            position = skip_string(expression, position)[0]
            continue
        if char in OPENERS:
            depth += 1
        elif char in CLOSERS:
            depth -= 1
        elif (
            char == "?"
            and depth == 0
            and expression[position + 1 : position + 2] != "?"
            and (position == 0 or expression[position - 1] != "?")
        ):
            question = start + position
            break
        position += 1
    kept = []
    for literal in literals:
        _, _, first, last = literal
        before = source[start:first].rstrip()
        after = source[last:end].lstrip()
        if question is not None and first < question:
            continue
        if before.endswith(("==", "!=", "+")) or after.startswith(("==", "!=", "+")):
            continue
        kept.append(literal)
    return kept


def asked_texts(source: str) -> tuple[set[str], set[str]]:
    """Every text that can reach a catalog lookup (`L10n.string`'s first argument, written in place,
    chosen by a condition, or held in a local variable), and every literal handed to
    `L10n.sentence`, which adds a full stop and looks nothing up."""
    asked: set[str] = set()
    sentences: set[str] = set()
    for match in CALL.finditer(source):
        scanned = scan(source, match.end(), ",)")
        argument = source[match.end() : scanned[0]].strip()
        if re.fullmatch(r"[A-Za-z_]\w*", argument):
            literals = initializer(source, argument)[1]
        else:
            literals = chosen(source, match.end(), scanned)
        # Literals inside a nested call belong to that call, not to this lookup.
        texts = {text for depth, text, _, _ in literals if depth == 0 and text}
        (asked if match.group(1) == "string" else sentences).update(texts)
    for lookup in LOOKUPS:
        asked |= {match.group(1) for match in lookup.finditer(source)}
    return asked, sentences


def test_every_text_the_app_asks_for_is_in_the_catalogs():
    english, chinese = load("en"), load("zh-Hans")
    missing = sorted(
        f"{path.name}: {text}"
        for path in SOURCES.rglob("*.swift")
        for text in asked_texts(path.read_text())[0]
        if text not in english or text not in chinese
    )
    assert missing == []


def test_a_sentence_is_made_from_text_already_looked_up():
    # `L10n.sentence` only adds "." or "。"; a literal handed to it is never translated.
    raw = sorted(
        f"{path.name}: {text}"
        for path in SOURCES.rglob("*.swift")
        for text in asked_texts(path.read_text())[1]
    )
    assert raw == []


def test_the_extraction_reads_choices_variables_and_long_strings():
    source = (
        'L10n.string(isOne(count) ? "Holding %@ in 1 stock" : "Holding %@ in %lld stocks", x)\n'
        'L10n.string(\n    target.asksForOwner ? "Sell %@ with Touch ID" : "Sell %@", a)\n'
        'let title = flag ? "Chosen" : "Other"\n'
        "L10n.string(title)\n"
        'L10n.string(Humanize.code("not_a_key"))\n'
        'L10n.string(text == "true" ? "on" : "off")\n'
        'let noun = one ? singular : plural ?? singular + "s"\n'
        "L10n.string(noun)\n"
        'L10n.string(titles[field] ?? "Ledger entry")\n'
        'L10n.string("Hello \\(name)")\n'
        'L10n.string("""\n    A long\n    text\n    """)\n'
        'L10n.sentence("Raw words")\n'
    )
    asked, sentences = asked_texts(source)
    assert asked == {
        "Holding %@ in 1 stock",
        "Holding %@ in %lld stocks",
        "Sell %@ with Touch ID",
        "Sell %@",
        "Chosen",
        "Other",
        "A long\ntext",
        "on",
        "off",
        "Ledger entry",
    }
    assert sentences == {"Raw words"}


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
