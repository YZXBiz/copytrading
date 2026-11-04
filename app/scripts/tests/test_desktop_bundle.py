from __future__ import annotations

import importlib.util
import plistlib
import sys
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))


def _load(name: str):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / f"{name}.py")
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


build_desktop = _load("build_desktop")
verify_desktop_bundle = _load("verify_desktop_bundle")


def test_the_update_feed_is_the_github_releases_of_the_repository() -> None:
    feed = build_desktop.update_config()
    assert feed.startswith("provider: github\nowner: YZXBiz\nrepo: copytrading\n")
    assert verify_desktop_bundle._FEED.match(feed)


def test_the_app_shows_its_version_and_a_build_number(tmp_path: Path, monkeypatch) -> None:
    info = tmp_path / "Info.plist"
    info.write_bytes(
        plistlib.dumps({"CFBundleShortVersionString": "0.0.0", "CFBundleVersion": "0.0.0"})
    )
    monkeypatch.setattr(build_desktop, "build_number", lambda: "32")

    build_desktop.stamp_info(info, "0.1.0-alpha.2")

    stamped = plistlib.loads(info.read_bytes())
    assert stamped["CFBundleShortVersionString"] == "0.1.0-alpha.2"
    assert stamped["CFBundleVersion"] == "32"


def test_an_empty_bundle_is_reported_without_running_anything(tmp_path: Path) -> None:
    app = tmp_path / "CopyTrading.app"
    (app / "Contents").mkdir(parents=True)
    (app / "Contents/Info.plist").write_bytes(
        plistlib.dumps(
            {"CFBundleIdentifier": "dev.copytrading.app", "CFBundleExecutable": "CopyTrading"}
        )
    )

    problems = verify_desktop_bundle.verify(app, inspect_macho=False)

    assert "the app shows no real version" in problems
    assert "missing resource: Resources/app-update.yml" in problems
    assert "missing resource: Resources/Engine/src/copytrading_engine/__main__.py" in problems


def test_the_smoke_run_names_only_a_throwaway_state_root(tmp_path: Path) -> None:
    smoke_desktop = _load("smoke_desktop")

    environment = smoke_desktop.smoke_environment(tmp_path)

    assert environment["COPYTRADING_STATE_ROOT"] == str(tmp_path)
    assert environment["COPYTRADING_SMOKE"] == "1"
