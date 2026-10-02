"""Wrap a release's verified app in the drag-to-install disk image people download."""

from __future__ import annotations

import argparse
import hashlib
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SETTINGS = ROOT / "app/Resources/DMG/settings.py"
BACKGROUND = ROOT / "app/Resources/DMG/background.tiff"
DMGBUILD = "dmgbuild==1.6.7"
VOLUME_NAME = "CopyTrading"


def dmgbuild_command(app: Path, output: Path) -> list[str]:
    """The pinned dmgbuild call that lays out the window from the checked-in settings."""
    return [
        "uvx",
        "--quiet",
        DMGBUILD,
        "-s",
        str(SETTINGS),
        "-D",
        f"app={app}",
        "-D",
        f"background={BACKGROUND}",
        VOLUME_NAME,
        str(output),
    ]


def release_paths(release_dir: Path, version: str) -> tuple[Path, Path]:
    """The release's app archive and the disk image built next to it."""
    return (
        release_dir / f"CopyTrading-v{version}-macos-arm64.zip",
        release_dir / f"CopyTrading-{version}.dmg",
    )


def build(archive: Path, output: Path) -> str:
    """Extract the released app, check its signature, build the image, and record its SHA-256."""
    with tempfile.TemporaryDirectory() as temporary:
        stage = Path(temporary)
        subprocess.run(["ditto", "-x", "-k", str(archive), str(stage)], check=True)
        app = stage / "CopyTrading.app"
        subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
        output.unlink(missing_ok=True)
        subprocess.run(dmgbuild_command(app, output), check=True)
    subprocess.run(["hdiutil", "verify", "-quiet", str(output)], check=True)
    digest = hashlib.sha256(output.read_bytes()).hexdigest()
    output.with_name(f"{output.name}.sha256").write_text(f"{digest}  {output.name}\n")
    return digest


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True, help="prerelease SemVer: 0.1.0-alpha.3")
    parser.add_argument("--release-dir", type=Path, required=True, help="`make release` output")
    args = parser.parse_args()
    archive, output = release_paths(args.release_dir, args.version)
    digest = build(archive, output)
    print(f"built {output} (sha256 {digest})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
