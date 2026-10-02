"""Messages from unconfigured authors are audited but never delivered."""

import datetime as dt
import json
import sqlite3
from contextlib import closing
from types import SimpleNamespace

import discord
import httpx2

from copytrading_engine.parsing.sqlite import SQLiteExtractionStore
from copytrading_engine.sources import session
from copytrading_engine.sources.sqlite import SQLiteSourceStore
from copytrading_engine.trading.adapters.operator_queries import source_page


async def test_unconfigured_author_is_audited_but_not_delivered(tmp_path):
    path = tmp_path / "app.db"
    requests = []

    async def respond(request):
        requests.append(request.url.host)
        return httpx2.Response(200, content=b"should not be fetched", request=request)

    class FailedDiagnostics:
        def record_payload(self, **record):
            raise OSError("diagnostics unavailable")

    store = await SQLiteSourceStore.open(
        path,
        diagnostics=FailedDiagnostics(),
        attachment_transport=httpx2.MockTransport(respond),
    )
    now = dt.datetime.now(dt.UTC)
    message = SimpleNamespace(
        content="25买入ABC",
        id=discord.utils.time_snowflake(now),
        channel=SimpleNamespace(id=7),
        author=SimpleNamespace(id=99),
        created_at=now,
        attachments=[
            SimpleNamespace(
                id=123,
                filename="chart.png",
                content_type="image/png",
                size=3,
                url="https://cdn.discordapp.com/attachments/1/123/chart.png?token=private-value",
            )
        ],
        embeds=[
            SimpleNamespace(
                title="Observed alert",
                description="Original rejection evidence",
                fields=[SimpleNamespace(name="Ticker", value="ABC", inline=False)],
            )
        ],
    )
    await session.capture_message(message, store, authors={42})
    assert await store.rejected_count() == 1
    assert await store.claim_batch() == ()
    rejected_id = f"discord:7:{message.id}"
    first_evidence = await store.attachment_evidence(rejected_id)
    assert len(first_evidence) == 1
    assert first_evidence[0].status == "skipped_rejected"
    assert first_evidence[0].evidence_id
    await session.capture_message(message, store, authors={42})
    replayed_evidence = await store.attachment_evidence(rejected_id)
    assert [item.evidence_id for item in replayed_evidence] == [
        item.evidence_id for item in first_evidence
    ]
    with closing(sqlite3.connect(path)) as db, db:
        serialized, accepted = db.execute(
            "SELECT event_payload,accepted FROM source_event_evidence WHERE source_id=?",
            (f"discord:7:{message.id}",),
        ).fetchone()
    saved = json.loads(serialized)
    assert accepted == 0
    assert saved["content"] == "25买入ABC"
    assert saved["embeds"][0]["title"] == "Observed alert"
    assert saved["attachments"][0]["filename"] == "chart.png"
    stored = path.read_bytes()
    assert stored.find(b"private-value") == -1
    assert requests == []
    await store.close()
    parser = await SQLiteExtractionStore.open(path)
    await parser.close()

    page = source_page(path, before_seq=None, limit=10, destinations={})
    assert len(page.rejected_items) == 1
    rejected = page.rejected_items[0]
    assert rejected.source_id == rejected_id
    assert rejected.reason == "author_not_configured"
    assert rejected.source_event.attachments[0].status == "skipped_rejected"
    assert rejected.source_event.attachments[0].evidence_id == first_evidence[0].evidence_id
    assert "private-value" not in page.model_dump_json()


async def test_invalid_rejected_message_attachment_is_explicit_without_fetch(tmp_path):
    path = tmp_path / "app.db"
    requests = []

    async def respond(request):
        requests.append(request.url.host)
        return httpx2.Response(200, content=b"should not be fetched", request=request)

    store = await SQLiteSourceStore.open(
        path,
        attachment_transport=httpx2.MockTransport(respond),
    )
    now = dt.datetime.now(dt.UTC)
    message = SimpleNamespace(
        content="x" * 10_001,
        id=discord.utils.time_snowflake(now),
        channel=SimpleNamespace(id=7),
        author=SimpleNamespace(id=99),
        created_at=now,
        attachments=[
            SimpleNamespace(
                id=456,
                filename="invalid.png",
                content_type="image/png",
                size=3,
                url="https://cdn.discordapp.com/attachments/1/456/invalid.png?sig=invalid-secret",
            )
        ],
        embeds=[],
    )

    await session.capture_message(message, store, authors=None)
    source_id = f"discord:7:{message.id}"
    evidence = await store.attachment_evidence(source_id)
    assert len(evidence) == 1
    assert evidence[0].status == "skipped_rejected"
    assert requests == []
    await store.close()
    parser = await SQLiteExtractionStore.open(path)
    await parser.close()

    page = source_page(path, before_seq=None, limit=10, destinations={})
    assert page.rejected_items[0].reason == "text_too_long"
    assert page.rejected_items[0].source_event.attachments[0].status == "skipped_rejected"
    stored = path.read_bytes()
    assert b"invalid-secret" not in stored


async def test_live_capture_preserves_attachment_metadata_without_persisting_url(tmp_path):
    path = tmp_path / "app.db"

    class RecordingDiagnostics:
        def __init__(self):
            self.records = []

        def record_payload(self, **record):
            self.records.append(record)

    diagnostics = RecordingDiagnostics()
    store = await SQLiteSourceStore.open(path, diagnostics=diagnostics)
    now = dt.datetime.now(dt.UTC)
    message = SimpleNamespace(
        content="Review attached chart",
        id=discord.utils.time_snowflake(now),
        channel=SimpleNamespace(id=7),
        author=SimpleNamespace(id=99),
        created_at=now,
        attachments=[
            SimpleNamespace(
                id=123,
                filename="chart.png",
                content_type="image/png",
                size=3,
                url="https://files.example/attachments/1/123/chart.png?token=private-value",
            )
        ],
        embeds=[
            SimpleNamespace(
                title="Trade alert",
                description="Original embed text",
                fields=[SimpleNamespace(name="Ticker", value="ABC", inline=True)],
            )
        ],
    )

    await session.capture_message(message, store, authors={99})

    evidence = await store.attachment_evidence(f"discord:7:{message.id}")
    assert len(evidence) == 1
    assert evidence[0].filename == "chart.png"
    assert evidence[0].status == "origin_rejected"
    stored = (tmp_path / "app.db").read_bytes()
    assert stored.find(b"private-value") == -1
    diagnostic_payload = diagnostics.records[0]["payload"]
    assert diagnostic_payload["content"] == "Review attached chart"
    assert diagnostic_payload["embeds"][0]["title"] == "Trade alert"
    assert diagnostic_payload["attachments"][0]["filename"] == "chart.png"
    await store.close()

    parser = await SQLiteExtractionStore.open(path)
    try:
        page = source_page(path, before_seq=None, limit=10, destinations={})
        source = page.items[0]
        assert source.source_event.content == "Review attached chart"
        assert source.source_event.embeds[0].title == "Trade alert"
        assert source.source_event.embeds[0].fields[0].value == "ABC"
        assert source.source_event.attachments[0].status == "origin_rejected"
        assert source.source_event.attachments[0].filename == "chart.png"
        assert source.source_event.capture_status == "complete"
        assert "managed_path" not in source.model_dump_json()
        assert source.source_event.attachments[0].evidence_id
    finally:
        await parser.close()


async def test_recovery_advances_cursor_for_unconfigured_author(tmp_path, monkeypatch):
    path = tmp_path / "app.db"
    requests = []

    async def respond(request):
        requests.append(request.url.host)
        return httpx2.Response(200, content=b"should not be fetched", request=request)

    store = await SQLiteSourceStore.open(
        path,
        attachment_transport=httpx2.MockTransport(respond),
    )
    now = dt.datetime.now(dt.UTC)
    message = SimpleNamespace(
        content="25买入ABC",
        id=discord.utils.time_snowflake(now - dt.timedelta(seconds=60)),
        channel=SimpleNamespace(id=7),
        author=SimpleNamespace(id=99),
        created_at=now - dt.timedelta(seconds=60),
        attachments=[
            SimpleNamespace(
                id=789,
                filename="history.png",
                content_type="image/png",
                size=3,
                url="https://cdn.discordapp.com/attachments/1/789/history.png?sig=history-secret",
            )
        ],
        embeds=[],
    )

    class Source:
        async def history(self, *, after, before, oldest_first, limit):
            if after.id < message.id < before.id:
                yield message

    class Client:
        def get_channel(self, channel_id):
            return Source()

    monkeypatch.setattr(session, "require_history_channel", lambda channel: channel)
    await session.recover_recent_messages(Client(), {7}, store, now=now, authors={42})
    assert (await store.recovery_start(7, 0)).last_id == message.id
    assert await store.rejected_count() == 1
    assert await store.claim_batch() == ()
    evidence = await store.attachment_evidence(f"discord:7:{message.id}")
    assert len(evidence) == 1
    assert evidence[0].status == "skipped_rejected"
    assert requests == []
    assert b"history-secret" not in path.read_bytes()
    await store.close()
