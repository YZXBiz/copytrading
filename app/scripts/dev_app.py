"""Open a debug CopyTrading on a fresh first launch with Connections already filled in.

The values come from the owner's test-key file: a label line ending in ":" with its value on the
next line (Discord token, Discord channel ID, DeepSeek API key, Anthropic key, Alpaca PAPER API
key and secret). They reach the app in a one-time file under the temporary directory that the
app deletes after reading; nothing here prints them. The debug build skips Touch ID on its
throwaway state root, like the UI journeys, and the next run deletes the last run's state and
the test keys it saved in the login Keychain.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

from ui_journeys import (
    APP_LOG,
    BUNDLE_ID,
    DEBUG_APP,
    _forget_test_keychain,
    build_debug_bundle,
    quit_app,
)

KEY_FILE = Path.home() / "Desktop/copytrading-test-keys.txt"
STATE_PREFIX = "copytrading-dev."
PREFILL_PREFIX = "copytrading-prefill."
MODELS = {"deepseek": "deepseek-flash", "anthropic": "claude-sonnet-5-5"}


def read_labelled(path: Path) -> dict[str, str]:
    """Each "Label:" line and the line under it, keyed by the label's lowercase letters."""
    values: dict[str, str] = {}
    label: str | None = None
    for line in path.read_text(encoding="utf-8").splitlines():
        text = line.strip()
        if not text:
            continue
        if label is not None:
            values[label] = text
            label = None
        elif text.endswith(":"):
            label = re.sub(r"[^a-z]", "", text.lower())
    return values


def prefill(values: dict[str, str], provider: str, guru: str) -> dict[str, str]:
    """The fields the app fills; a missing one is named, never shown."""

    def find(*words: str) -> str:
        for label, value in values.items():
            if all(word in label for word in words):
                return value
        raise SystemExit(f"no value labelled with {' and '.join(words)} in the key file")

    return {
        "channel_id": find("channel"),
        "discord_token": find("discord", "token"),
        "provider": provider,
        "model": MODELS[provider],
        "provider_api_key": find(provider),
        "alpaca_key": find("alpaca", "key"),
        "alpaca_secret": find("alpaca", "secret"),
        "guru_name": guru,
    }


def discard_earlier_runs(temporary: Path) -> None:
    """A run's saved keys live in the login Keychain under its own installation; drop them."""
    for state in temporary.glob(f"{STATE_PREFIX}*"):
        if _forget_test_keychain(state):
            raise SystemExit(f"test keys from {state} remain in the login Keychain")
        shutil.rmtree(state, ignore_errors=True)
    # A launch that never started leaves its one-time file unread.
    for leftover in temporary.glob(f"{PREFILL_PREFIX}*"):
        leftover.unlink(missing_ok=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--keys", type=Path, default=KEY_FILE, help="the test-key file")
    parser.add_argument("--provider", choices=sorted(MODELS), default="deepseek")
    parser.add_argument("--guru", default="Zhao", help="the guru's name on the channel")
    parser.add_argument("--skip-build", action="store_true", help="reuse the last debug bundle")
    args = parser.parse_args()

    if not args.keys.is_file():
        raise SystemExit(f"no key file at {args.keys}")
    fields = prefill(read_labelled(args.keys), args.provider, args.guru)
    if not args.skip_build:
        build_debug_bundle()
    quit_app()
    # /tmp is a symlink, which the app's state checks reject; the per-user directory is not.
    temporary = Path(tempfile.gettempdir())
    discard_earlier_runs(temporary)
    state_root = Path(tempfile.mkdtemp(prefix=STATE_PREFIX, dir=temporary))
    descriptor, name = tempfile.mkstemp(prefix=PREFILL_PREFIX, dir=temporary)
    with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
        json.dump(fields, handle)
    # A first launch starts the setup tour unless an earlier run ended it.
    subprocess.run(
        ["defaults", "delete", BUNDLE_ID, "setupTour.ended"], capture_output=True, check=False
    )
    APP_LOG.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [
            "open",
            "-n",
            "--env",
            "COPYTRADING_UI_TEST_UNLOCK=1",
            "--env",
            f"COPYTRADING_STATE_ROOT={state_root}",
            "--env",
            f"COPYTRADING_DEV_PREFILL={name}",
            "--stderr",
            str(APP_LOG),
            str(DEBUG_APP),
        ],
        check=True,
    )
    print(f"opened {DEBUG_APP.name} on {state_root}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
