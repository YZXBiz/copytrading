"""A picture a relay posts inside an embed is captured like an attachment, without changing how the
post is read."""

import datetime as dt
from types import SimpleNamespace

import discord
import httpx2

from copytrading_engine.sources.source import adapter_event, attachment_references, envelope
from copytrading_engine.sources.sqlite import SQLiteSourceStore

CDN = "https://cdn.discordapp.com/attachments/1/2/chart.png?ex=1&is=2&hm=3"
LABEL = "赵哥-股票\uff1a"  # the relay's name label, ending in a full-width colon
PROXY = "https://media.discordapp.net/attachments/1/2/chart.png?ex=1&is=2&hm=3"


def message(*embeds: discord.Embed) -> SimpleNamespace:
    return SimpleNamespace(
        id=1564671149546283111,
        content="@everyone",
        channel=SimpleNamespace(id=1517754775674949742),
        author=SimpleNamespace(id=1426229538722938880),
        created_at=dt.datetime(2026, 10, 27, 16, 4, 32, tzinfo=dt.UTC),
        embeds=list(embeds),
        attachments=[],
    )


def relay(image: dict) -> discord.Embed:
    return discord.Embed.from_dict({"type": "rich", "description": LABEL, "image": image})


def test_a_relayed_chart_is_captured_from_discord_and_the_post_reads_the_same():
    post = message(relay({"url": CDN, "proxy_url": PROXY, "width": 1280, "height": 720}))

    (picture,) = attachment_references(post)
    assert picture.attachment_id == "embed-1-image"
    assert picture.filename == "chart.png"
    assert picture.url == CDN
    assert picture.declared_size == 0

    event = adapter_event(post)
    assert event["embeds"] == [
        {
            "type": "rich",
            "title": None,
            "description": LABEL,
            "fields": [],
            "pictures": [{"kind": "image", "width": 1280, "height": 720}],
        }
    ]
    assert "cdn.discordapp.com" not in str(event)

    raw = envelope(post)
    assert raw.text == f"@everyone\n{LABEL}"
    assert raw.image_count == 0


def test_an_outside_picture_is_fetched_through_discords_proxy_or_recorded_as_rejected():
    proxied = message(relay({"url": "https://i.imgur.com/a.png", "proxy_url": PROXY}))
    assert [ref.url for ref in attachment_references(proxied)] == [PROXY]

    outside = message(
        relay(
            {
                "url": "https://i.imgur.com/a.png",
                "proxy_url": "https://images-ext-1.discordapp.net/x",
            }
        )
    )
    assert [ref.url for ref in attachment_references(outside)] == ["https://i.imgur.com/a.png"]


def test_only_an_image_embeds_thumbnail_is_its_picture():
    posted_image = discord.Embed.from_dict({"type": "image", "thumbnail": {"url": CDN}})
    link_preview = discord.Embed.from_dict(
        {"type": "article", "title": "News", "thumbnail": {"url": CDN}}
    )
    assert [ref.attachment_id for ref in attachment_references(message(posted_image))] == [
        "embed-1-thumbnail"
    ]
    assert attachment_references(message(link_preview)) == ()


async def test_a_relayed_chart_lands_in_the_posts_evidence(tmp_path):
    chart = b"\x89PNG chart"

    async def respond(request):
        assert request.url.host == "cdn.discordapp.com"
        return httpx2.Response(200, content=chart, request=request)

    store = await SQLiteSourceStore.open(
        tmp_path / "application.db", attachment_transport=httpx2.MockTransport(respond)
    )
    post = message(relay({"url": CDN, "proxy_url": PROXY, "width": 1280, "height": 720}))
    await store.add(
        envelope(post), source_event=adapter_event(post), attachments=attachment_references(post)
    )

    (evidence,) = await store.attachment_evidence(envelope(post).identity)
    assert evidence.status == "available"
    assert evidence.byte_size == len(chart)
    assert await store.read_attachment(evidence.evidence_id) == chart
    await store.close()
