"""Sign local builds with the owner's Apple Development identity to keep Keychain trust.

A rebuilt app may read its own Keychain items without asking only when it carries the same Apple
Team ID. Ad-hoc and self-signed builds have none, so the Keychain pins its trust to one build's
code hash and every rebuild asks for the login password again. Create the identity once in
Xcode → Settings → Accounts → Manage Certificates → + → Apple Development. Without it the finished
bundle receives an ad-hoc resource seal; it does not gain Apple identity or trusted update status.
"""

from __future__ import annotations

import re
import subprocess
from pathlib import Path

BUNDLE_IDENTIFIER = "dev.copytrading.app"
_IDENTITY_LINE = re.compile(r'^\s*\d+\)\s+([0-9A-F]{40})\s+"(Apple Development: [^"]+)"')


def apple_development_identity(valid_identities_output: str) -> str | None:
    """The SHA-1 of the first Apple Development identity in `find-identity -v` output."""
    for line in valid_identities_output.splitlines():
        match = _IDENTITY_LINE.match(line)
        if match:
            return match.group(1)
    return None


def local_identity() -> str | None:
    result = subprocess.run(
        ["/usr/bin/security", "find-identity", "-v", "-p", "codesigning"],
        capture_output=True,
        text=True,
        check=False,
    )
    return apple_development_identity(result.stdout) if result.returncode == 0 else None


def sign_command(
    executable: Path, identity: str, *, identifier: str = BUNDLE_IDENTIFIER
) -> list[str]:
    return [
        "/usr/bin/codesign",
        "--force",
        "--sign",
        identity,
        "--identifier",
        identifier,
        str(executable),
    ]


def sign_if_available(app: Path, *, ad_hoc: bool = False) -> str | None:
    """Seal the assembled app, using the owner's identity unless explicitly ad-hoc."""
    identity = None if ad_hoc else local_identity()
    helper = app / "Contents/Helpers/copytrading"
    if helper.is_file():
        subprocess.run(
            sign_command(helper, identity or "-", identifier=f"{BUNDLE_IDENTIFIER}.cli"),
            check=True,
        )
    subprocess.run(sign_command(app, identity or "-"), check=True)
    return identity
