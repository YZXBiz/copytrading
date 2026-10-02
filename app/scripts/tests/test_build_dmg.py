from __future__ import annotations

import sys
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
import build_dmg  # noqa: E402 - importable only after the scripts directory is on sys.path


def test_the_image_is_laid_out_by_the_pinned_tool_from_the_checked_in_settings():
    command = build_dmg.dmgbuild_command(Path("/stage/CopyTrading.app"), Path("/out/x.dmg"))
    assert command[:3] == ["uvx", "--quiet", "dmgbuild==1.6.7"]
    assert command[command.index("-s") + 1] == str(build_dmg.SETTINGS)
    assert "app=/stage/CopyTrading.app" in command
    assert f"background={build_dmg.BACKGROUND}" in command
    assert command[-2:] == ["CopyTrading", "/out/x.dmg"]


def test_the_settings_and_their_artwork_ship_with_the_repository():
    settings = build_dmg.SETTINGS.read_text()
    assert build_dmg.BACKGROUND.is_file()
    assert '"Applications": "/Applications"' in settings
    assert '"CopyTrading.app": (165, 196)' in settings


def test_the_image_is_named_after_the_release_it_wraps(tmp_path):
    archive, output = build_dmg.release_paths(tmp_path, "0.1.0-alpha.1")
    assert archive.name == "CopyTrading-v0.1.0-alpha.1-macos-arm64.zip"
    assert output.name == "CopyTrading-0.1.0-alpha.1.dmg"
