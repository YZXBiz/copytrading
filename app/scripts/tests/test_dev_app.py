from __future__ import annotations

import sys
from pathlib import Path

import pytest

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
import dev_app  # noqa: E402 - importable only after the scripts directory is on sys.path

KEYS = """CopyTrading test keys (paper only). Delete this file after you're done.

Discord token:
discord-token-value

Discord channel ID:
1234567890123456789

Model service: DeepSeek, model deepseek-flash
DeepSeek API key:
deepseek-key-value

Alpaca PAPER API key:
alpaca-key-value

Alpaca PAPER API secret:
alpaca-secret-value

Anthropic-key:
anthropic-key-value"""


def test_every_field_comes_from_its_label(tmp_path: Path) -> None:
    keys = tmp_path / "keys.txt"
    keys.write_text(KEYS)

    fields = dev_app.prefill(dev_app.read_labelled(keys), "anthropic", "Zhao")

    assert fields == {
        "channel_id": "1234567890123456789",
        "discord_token": "discord-token-value",
        "provider": "anthropic",
        "model": "claude-sonnet-5-5",
        "provider_api_key": "anthropic-key-value",
        "alpaca_key": "alpaca-key-value",
        "alpaca_secret": "alpaca-secret-value",
        "guru_name": "Zhao",
    }


def test_a_missing_value_is_named_never_shown(tmp_path: Path) -> None:
    keys = tmp_path / "keys.txt"
    keys.write_text(KEYS.replace("Alpaca PAPER API secret:\nalpaca-secret-value", ""))

    with pytest.raises(SystemExit, match="alpaca and secret") as failure:
        dev_app.prefill(dev_app.read_labelled(keys), "deepseek", "Zhao")
    assert "-value" not in str(failure.value)
