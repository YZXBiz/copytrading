"""The update feed lists the newest release first, once, with Sparkle's signature."""

import sys
import xml.etree.ElementTree as ET
from datetime import UTC, datetime
from pathlib import Path

import pytest

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
from appcast import KEEP, SPARKLE, add_release, parse_signature  # noqa: E402 - needs the path above

LINE = 'sparkle:edSignature="QUJD+/9=" length="57012345"'


def _add(feed, version, build):
    return add_release(
        feed,
        version=version,
        build=build,
        url=f"https://github.com/o/r/releases/download/v{version}/CopyTrading-{version}.dmg",
        notes_url=f"https://github.com/o/r/releases/tag/v{version}",
        signature="QUJD+/9=",
        length=57012345,
        minimum_system="26.0",
        published=datetime(2026, 10, 7, 14, tzinfo=UTC),
    )


def _versions(feed):
    channel = ET.fromstring(feed).find("channel")
    assert channel is not None
    return [item.findtext(f"{{{SPARKLE}}}shortVersionString") for item in channel.findall("item")]


def test_sign_update_output_gives_signature_and_length():
    assert parse_signature(LINE) == ("QUJD+/9=", 57012345)
    with pytest.raises(ValueError, match="no EdDSA signature"):
        parse_signature("sparkle:dsaSignature=old")


def test_a_new_feed_holds_the_release_with_its_signature():
    feed = _add(None, "0.1.0-alpha.4", 120)
    item = ET.fromstring(feed).find("channel/item")
    assert item is not None
    enclosure = item.find("enclosure")
    assert enclosure is not None
    assert item.findtext(f"{{{SPARKLE}}}version") == "120"
    assert enclosure.get(f"{{{SPARKLE}}}edSignature") == "QUJD+/9="
    assert enclosure.get("length") == "57012345"
    assert (enclosure.get("url") or "").endswith("/v0.1.0-alpha.4/CopyTrading-0.1.0-alpha.4.dmg")


def test_releases_are_newest_first_and_a_rerun_replaces_its_entry():
    feed = _add(_add(None, "0.1.0-alpha.4", 120), "0.1.0-alpha.5", 131)
    assert _versions(feed) == ["0.1.0-alpha.5", "0.1.0-alpha.4"]
    assert _versions(_add(feed, "0.1.0-alpha.5", 132)) == ["0.1.0-alpha.5", "0.1.0-alpha.4"]


def test_the_feed_keeps_only_the_newest_releases():
    feed = None
    for n in range(KEEP + 3):
        feed = _add(feed, f"0.1.0-alpha.{n + 1}", 100 + n)
    assert len(_versions(feed)) == KEEP
    assert _versions(feed)[0] == f"0.1.0-alpha.{KEEP + 3}"
