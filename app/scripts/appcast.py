"""Add a release to the Sparkle update feed (appcast.xml) the app reads (ADR-0009).

The release workflow signs the DMG with Sparkle's `sign_update`, then runs this to put the new
release first in the feed it fetched from the `appcast` branch. The feed keeps the newest
releases; Sparkle offers the newest one with a higher build number than the installed app.
"""

from __future__ import annotations

import argparse
import re
import sys
import xml.etree.ElementTree as ET
from datetime import UTC, datetime
from email.utils import format_datetime
from pathlib import Path

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
KEEP = 20
_SIGNATURE = re.compile(r'sparkle:edSignature="([A-Za-z0-9+/=]+)"\s+length="([0-9]+)"')

ET.register_namespace("sparkle", SPARKLE)


def _sparkle(name: str) -> str:
    return f"{{{SPARKLE}}}{name}"


def parse_signature(sign_update_output: str) -> tuple[str, int]:
    """The EdDSA signature and byte length from `sign_update`'s single line of output."""
    match = _SIGNATURE.search(sign_update_output)
    if match is None:
        raise ValueError("sign_update output has no EdDSA signature and length")
    return match.group(1), int(match.group(2))


def add_release(
    feed: str | None,
    *,
    version: str,
    build: int,
    url: str,
    notes_url: str,
    signature: str,
    length: int,
    minimum_system: str,
    published: datetime,
) -> str:
    """The feed with this release first; an earlier entry for the same version is replaced."""
    if build < 1 or length < 1:
        raise ValueError("a release needs a positive build number and file length")
    if feed:
        root = ET.fromstring(feed)
        channel = root.find("channel")
        if root.tag != "rss" or channel is None:
            raise ValueError("the existing feed is not an RSS channel")
    else:
        root = ET.Element("rss", {"version": "2.0"})
        channel = ET.SubElement(root, "channel")
        ET.SubElement(channel, "title").text = "CopyTrading"
    for item in channel.findall("item"):
        if item.findtext(_sparkle("shortVersionString")) == version:
            channel.remove(item)

    item = ET.Element("item")
    ET.SubElement(item, "title").text = f"CopyTrading {version}"
    ET.SubElement(item, "pubDate").text = format_datetime(published.astimezone(UTC))
    ET.SubElement(item, _sparkle("version")).text = str(build)
    ET.SubElement(item, _sparkle("shortVersionString")).text = version
    ET.SubElement(item, _sparkle("minimumSystemVersion")).text = minimum_system
    ET.SubElement(item, _sparkle("releaseNotesLink")).text = notes_url
    ET.SubElement(
        item,
        "enclosure",
        {
            "url": url,
            "length": str(length),
            "type": "application/octet-stream",
            _sparkle("edSignature"): signature,
        },
    )
    first = next((i for i, child in enumerate(channel) if child.tag == "item"), len(channel))
    channel.insert(first, item)
    for extra in channel.findall("item")[KEEP:]:
        channel.remove(extra)
    ET.indent(root)
    return '<?xml version="1.0" encoding="utf-8"?>\n' + ET.tostring(root, encoding="unicode") + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--feed", type=Path, required=True, help="read if present, then written")
    parser.add_argument("--version", required=True)
    parser.add_argument("--build", type=int, required=True)
    parser.add_argument("--url", required=True)
    parser.add_argument("--notes-url", required=True)
    parser.add_argument("--signature-line", required=True, help="sign_update's output")
    parser.add_argument("--minimum-system", default="26.0")
    arguments = parser.parse_args()
    try:
        signature, length = parse_signature(arguments.signature_line)
        existing = arguments.feed.read_text() if arguments.feed.is_file() else None
        arguments.feed.write_text(
            add_release(
                existing,
                version=arguments.version,
                build=arguments.build,
                url=arguments.url,
                notes_url=arguments.notes_url,
                signature=signature,
                length=length,
                minimum_system=arguments.minimum_system,
                published=datetime.now(UTC),
            )
        )
    except (OSError, ValueError, ET.ParseError) as error:
        print(f"appcast: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
