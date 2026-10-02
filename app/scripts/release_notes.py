"""Write a GitHub release's notes from its CHANGELOG.md section."""

from __future__ import annotations

import argparse
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CHANGELOG = ROOT / "CHANGELOG.md"
REPOSITORY = "https://github.com/YZXBiz/copytrading"


class NotesError(ValueError):
    """The changelog has no section for the version being released."""


def changelog_section(changelog: str, version: str) -> str:
    """The body under `## <version> …`, up to the next `## ` heading."""
    heading = re.compile(rf"^## {re.escape(version)}(?:\s.*)?$", re.MULTILINE)
    match = heading.search(changelog)
    if match is None:
        raise NotesError(f"CHANGELOG.md has no section for {version}")
    following = re.compile(r"^## ", re.MULTILINE).search(changelog, match.end())
    body = changelog[match.end() : following.start() if following else len(changelog)]
    if not body.strip():
        raise NotesError(f"CHANGELOG.md's section for {version} is empty")
    return body.strip()


def release_notes(changelog: str, version: str) -> str:
    """The changelog section, then how to install and verify the download."""
    section = re.sub(r"^### ", "## ", changelog_section(changelog, version), flags=re.MULTILINE)
    install = (
        f"1. Download `CopyTrading-{version}.dmg`, open it, and drag CopyTrading into "
        "Applications.\n"
        "2. Open CopyTrading. Preview builds are not yet notarized by Apple, so the first time "
        "macOS blocks it: go to **System Settings → Privacy & Security** and choose "
        "**Open Anyway**. You only do this once."
    )
    requirements = (
        "Requires an Apple silicon Mac with macOS 26 or later. The ZIP holds the same app. "
        "Verify downloads with `shasum -a 256 -c SHA256SUMS`, and the DMG with its "
        "`.sha256` file."
    )
    preview = (
        "This is a developer preview: it is not qualified for live trading. See "
        f"[validation]({REPOSITORY}/blob/main/docs/validation.md) for what is and is not proven."
    )
    return f"{section}\n\n## Install\n\n{install}\n\n{requirements}\n\n{preview}\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True, help="release version without v")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.write_text(release_notes(CHANGELOG.read_text(), args.version))
    print(f"wrote {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
