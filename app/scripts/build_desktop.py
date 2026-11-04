"""Build the Electron CopyTrading.app: the React shell, the pinned CPython, and the engine."""

from __future__ import annotations

import argparse
import json
import plistlib
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from build_app import (
    build_number,
    described_release,
    local_version,
    pinned_manifest,
    run,
    stage_engine,
)
from local_signing import sign_frameworks, sign_if_available
from verify_bundle import bundle_inventory
from verify_desktop_bundle import verify

ROOT = Path(__file__).resolve().parents[2]
DESKTOP = ROOT / "desktop"
BUILT_APP = DESKTOP / "dist/package/mac-arm64/CopyTrading.app"
REPOSITORY = ("YZXBiz", "copytrading")


def update_config() -> str:
    """electron-updater's app-update.yml: where an installed copy looks for its next release."""
    owner, repo = REPOSITORY
    return (
        f"provider: github\nowner: {owner}\nrepo: {repo}\n"
        f"updaterCacheDirName: copytrading-updater\n"
    )


def stamp_info(info_path: Path, version: str) -> None:
    """Show the full version and the commit count as the build number."""
    with info_path.open("rb") as stream:
        info = plistlib.load(stream)
    info["CFBundleShortVersionString"] = version
    info["CFBundleVersion"] = build_number()
    with info_path.open("wb") as stream:
        plistlib.dump(info, stream)


def build(app: Path, prepared: Path, version: str | None = None, *, ad_hoc: bool = False) -> None:
    manifest = pinned_manifest(prepared)
    shown = version or local_version(described_release()) or "0.0.0"
    run("npm", "run", "package", "--", f"-c.extraMetadata.version={shown}", cwd=DESKTOP)
    app.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="desktop-build-", dir=app.parent) as temporary:
        staged = Path(temporary) / app.name
        shutil.copytree(BUILT_APP, staged, symlinks=True)
        contents = staged / "Contents"
        resources = contents / "Resources"
        stamp_info(contents / "Info.plist", shown)
        (resources / "app-update.yml").write_text(update_config())
        stage_engine(resources, manifest)
        # Nested code first: signing rewrites those files, the inventory records their final bytes.
        sign_frameworks(staged, ad_hoc=ad_hoc)
        (resources / "Runtime/bundle-files.json").write_text(
            json.dumps(bundle_inventory(contents), sort_keys=True) + "\n"
        )
        # The app's own seal covers the finished inventory. The owner's Team ID keeps Keychain trust
        # across local rebuilds.
        signed_by = sign_if_available(staged, ad_hoc=ad_hoc)
        problems = verify(staged)
        if problems:
            raise ValueError("bundle verification failed: " + "; ".join(problems))
        if app.exists():
            shutil.rmtree(app)
        staged.rename(app)
    signature = "signed with Apple Development" if signed_by else "ad-hoc signed"
    print(f"built desktop app {shown} ({signature}): {app}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, default=ROOT / "dist/CopyTrading.app")
    parser.add_argument("--runtime", type=Path, default=ROOT / "dist/desktop-runtime/prepared")
    parser.add_argument("--version", help="the release version to show, such as 0.1.0-alpha.4")
    parser.add_argument(
        "--ad-hoc", action="store_true", help="seal ad hoc, never with the owner's identity"
    )
    arguments = parser.parse_args()
    try:
        build(
            arguments.app.resolve(),
            arguments.runtime.resolve(),
            arguments.version,
            ad_hoc=arguments.ad_hoc,
        )
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"desktop build failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
