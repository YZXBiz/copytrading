from __future__ import annotations

import sys
from pathlib import Path

import pytest

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
import release_notes  # noqa: E402 - importable only after the scripts directory is on sys.path

CHANGELOG = """# Changelog

Intro.

## 0.2.0-alpha.1 — developer preview

New things.

### The app

- A feature.

## 0.1.0-alpha.1 — developer preview

The first one.
"""


def test_the_notes_are_the_versions_section_and_stop_at_the_next_one():
    section = release_notes.changelog_section(CHANGELOG, "0.2.0-alpha.1")
    assert section == "New things.\n\n### The app\n\n- A feature."


def test_the_last_section_runs_to_the_end_of_the_file():
    assert release_notes.changelog_section(CHANGELOG, "0.1.0-alpha.1") == "The first one."


def test_a_release_without_a_changelog_section_is_refused():
    with pytest.raises(release_notes.NotesError, match=r"no section for 0\.3\.0-alpha\.1"):
        release_notes.changelog_section(CHANGELOG, "0.3.0-alpha.1")


def test_a_version_is_not_matched_by_a_longer_one():
    changelog = "## 0.1.0-alpha.10 — preview\n\nTen.\n"
    with pytest.raises(release_notes.NotesError):
        release_notes.changelog_section(changelog, "0.1.0-alpha.1")


def test_the_notes_say_how_to_install_the_dmg_of_that_version():
    notes = release_notes.release_notes(CHANGELOG, "0.2.0-alpha.1")
    assert notes.startswith("New things.\n\n## The app")
    assert "`CopyTrading-0.2.0-alpha.1.dmg`" in notes
    assert "Open Anyway" in notes


def test_the_repository_changelog_has_a_section_for_its_first_release():
    assert release_notes.changelog_section(release_notes.CHANGELOG.read_text(), "0.1.0-alpha.1")
