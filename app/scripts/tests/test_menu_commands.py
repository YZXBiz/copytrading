"""No two menu commands do the same thing under different names or shortcuts."""

import re
from pathlib import Path

SHELL = Path(__file__).resolve().parents[2] / "Sources" / "CopyTrading" / "Shell"
# `Button(L10n.string("Find…")) { … }` and `Button(L10n.string("Show Tips Again"), action: f)`.
CLOSURE = re.compile(r'Button\(L10n\.string\("([^"]+)"\)\)\s*\{([^{}]*)\}')
NAMED = re.compile(r'Button\(L10n\.string\("([^"]+)"\),\s*action:\s*([\w.]+)\)')
ASSIGNMENT = re.compile(r"model\.(\w+)\s*=\s*([^\n]+)")
TOGGLE = re.compile(r"model\.(\w+)\.toggle\(\)")


def effect(body: str) -> frozenset[str]:
    """What a command's closure changes; toggling a flag counts as setting it, as it opens."""
    changes = {f"{name} = {value.strip()}" for name, value in ASSIGNMENT.findall(body)}
    changes |= {f"{name} = true" for name in TOGGLE.findall(body)}
    return frozenset(changes)


def menu_effects(source: str) -> list[tuple[str, frozenset[str]]]:
    found = [(title, effect(body)) for title, body in CLOSURE.findall(source)]
    found += [(title, frozenset({f"calls {action}"})) for title, action in NAMED.findall(source)]
    return found


def duplicates(source: str) -> list[tuple[str, str]]:
    seen: dict[frozenset[str], str] = {}
    repeated = []
    for title, changes in menu_effects(source):
        if changes in seen:
            repeated.append((seen[changes], title))
        seen.setdefault(changes, title)
    return repeated


def test_no_two_menu_commands_do_the_same_thing():
    source = "\n".join(path.read_text() for path in sorted(SHELL.glob("*Commands.swift")))
    assert any(title == "Find…" for title, _ in menu_effects(source))
    assert duplicates(source) == []


def test_a_second_name_for_the_same_command_is_caught():
    source = """
        Button(L10n.string("Find…")) { model.isShowingPalette.toggle() }
        Button(L10n.string("Find a Post…")) { model.isShowingPalette = true }
    """
    assert duplicates(source) == [("Find…", "Find a Post…")]
