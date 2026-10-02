"""The app shows the engine's step lines and errors in the owner's language from its catalogs."""

import re
from pathlib import Path

import pytest

from copytrading_engine.assistant.service import MESSAGES
from copytrading_engine.assistant.tools import REFUSED_STEP, STEP

CATALOGS = (
    Path(__file__).resolve().parents[3] / "app" / "Sources" / "AppLocalizationCore" / "Resources"
)
ENTRY = re.compile(r'^"((?:[^"\\]|\\.)*)" = "((?:[^"\\]|\\.)*)";$')


def catalog(language: str) -> dict[str, str]:
    lines = (CATALOGS / f"{language}.lproj" / "Localizable.strings").read_text().splitlines()
    return {match[1]: match[2] for line in lines if (match := ENTRY.match(line))}


def app_key(text: str) -> str:
    """The catalog key the app looks a line up by: each `{value}` becomes `%@`."""
    return re.sub(r"\{\w+\}", "%@", text)


@pytest.mark.parametrize("language", ["en", "zh-Hans"])
def test_every_step_line_and_error_is_in_the_app_catalogs(language):
    entries = catalog(language)
    steps = [*STEP.values(), *REFUSED_STEP.values()]
    texts = [app_key(step) for step in steps] + list(MESSAGES.values())
    missing = [text for text in texts if text not in entries]
    assert missing == []


def test_a_step_line_names_at_most_one_value():
    steps = [*STEP.values(), *REFUSED_STEP.values()]
    assert all(len(re.findall(r"\{\w+\}", step)) <= 1 for step in steps)


def test_every_refused_step_answers_a_step():
    assert set(REFUSED_STEP) <= set(STEP)
    assert all(line.startswith("Couldn't ") for line in REFUSED_STEP.values())


APP_TEMPLATES = (
    Path(__file__).resolve().parents[3]
    / "app"
    / "Sources"
    / "CopyTrading"
    / "Features"
    / "Assistant"
    / "AssistantEngineText.swift"
)


def test_every_step_line_naming_a_value_is_an_app_template():
    source = APP_TEMPLATES.read_text()
    steps = [*STEP.values(), *REFUSED_STEP.values()]
    named = [app_key(step) for step in steps if re.search(r"\{\w+\}", step)]
    missing = [key for key in named if f'"{key}"' not in source]
    assert missing == []
