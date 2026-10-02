"""Attachment evidence is private, bounded, replay-safe, and fetched from approved origins."""

import datetime as dt
import hashlib
import json
import os
import sqlite3
from contextlib import closing

import httpx2
import pytest

from copytrading_engine.shared.raw_message import RawMessage
from copytrading_engine.sources.application import AttachmentReference
from copytrading_engine.sources.sqlite import SQLiteSourceStore


def raw(message_id: int = 42) -> RawMessage:
    return RawMessage(
        schema_version=1,
        event_type="raw_message",
        source="discord",
        channel_id="7",
        author_id="99",
        id=str(message_id),
        timestamp=dt.datetime.now(dt.UTC),
        text="Review attached chart",
        image_count=1,
    )


def reference(url: str, *, attachment_id: str = "123", declared_size: int = 3):
    return AttachmentReference(
        attachment_id=attachment_id,
        filename="chart.png",
        content_type="image/png",
        declared_size=declared_size,
        url=url,
    )


class RecordingDiagnostics:
    def __init__(self):
        self.payloads = []

    def record_payload(self, **record):
        self.payloads.append(record)


async def test_attachment_evidence_is_source_owned_private_and_replay_safe(tmp_path):
    body = b"png"
    seen = []

    async def respond(request):
        seen.append(request.url.host)
        return httpx2.Response(200, content=body, request=request)

    diagnostics = RecordingDiagnostics()
    store = await SQLiteSourceStore.open(
        tmp_path / "application.db",
        diagnostics=diagnostics,
        attachment_transport=httpx2.MockTransport(respond),
    )
    event = raw()
    signed_url = "https://cdn.discordapp.com/attachments/1/123/chart.png?token=private-value"
    attachment = reference(signed_url)
    source_event = {"discord_message": {"content": event.text, "attachments": [{"id": "123"}]}}

    await store.add(event, source_event=source_event, attachments=(attachment,))
    await store.add(event, source_event=source_event, attachments=(attachment,))

    evidence = await store.attachment_evidence(event.identity)
    assert len(evidence) == 1
    assert evidence[0].status == "available"
    assert evidence[0].byte_size == len(body)
    assert evidence[0].sha256 == hashlib.sha256(body).hexdigest()
    assert evidence[0].managed_path is not None
    evidence_path = tmp_path / evidence[0].managed_path
    assert evidence_path.read_bytes() == body
    assert await store.read_attachment(evidence[0].evidence_id) == body
    with pytest.raises(ValueError, match="attachment_evidence_unavailable"):
        await store.read_attachment("../../application.db")
    assert os.stat(evidence_path).st_mode & 0o777 == 0o600
    assert os.stat(evidence_path.parent.parent).st_mode & 0o777 == 0o700
    assert seen == ["cdn.discordapp.com"]
    assert len(diagnostics.payloads) == 1

    stored = (tmp_path / "application.db").read_bytes()
    secret_offset = stored.find(b"private-value")
    assert secret_offset == -1
    await store.close()


async def test_attachment_redirect_to_unapproved_origin_is_not_fetched(tmp_path):
    requests = []

    async def respond(request):
        requests.append(request.url.host)
        return httpx2.Response(
            302,
            headers={"location": "https://files.evil.example/chart.png"},
            request=request,
        )

    store = await SQLiteSourceStore.open(
        tmp_path / "application.db", attachment_transport=httpx2.MockTransport(respond)
    )
    event = raw()
    await store.add(
        event,
        source_event={"id": event.id},
        attachments=(reference("https://cdn.discordapp.com/attachments/1/123/chart.png"),),
    )

    evidence = await store.attachment_evidence(event.identity)
    assert [item.status for item in evidence] == ["origin_rejected"]
    assert requests == ["cdn.discordapp.com"]
    await store.close()


async def test_missing_oversize_and_over_count_attachments_are_explicit_and_bounded(tmp_path):
    calls = 0

    async def respond(request):
        nonlocal calls
        calls += 1
        return httpx2.Response(200, content=b"x", request=request)

    store = await SQLiteSourceStore.open(
        tmp_path / "application.db", attachment_transport=httpx2.MockTransport(respond)
    )
    event = raw()
    refs = [
        reference("", attachment_id="missing"),
        reference(
            "https://cdn.discordapp.com/attachments/1/large/chart.png",
            attachment_id="large",
            declared_size=1024 * 1024 + 1,
        ),
        *(reference("", attachment_id=f"extra-{index}") for index in range(12)),
    ]
    await store.add(event, source_event={"id": event.id}, attachments=tuple(refs))

    evidence = await store.attachment_evidence(event.identity)
    by_id = {item.attachment_id: item for item in evidence}
    assert len(evidence) == 11
    assert by_id["missing"].status == "missing"
    assert by_id["large"].status == "oversize"
    omitted = next(item for item in evidence if item.status == "count_exceeded")
    assert omitted.omitted_count == 4
    assert calls == 0
    await store.close()


async def test_attachment_download_failure_does_not_rollback_source_capture(tmp_path):
    async def fail(request):
        raise OSError("local test transport failure")

    store = await SQLiteSourceStore.open(
        tmp_path / "application.db", attachment_transport=httpx2.MockTransport(fail)
    )
    event = raw()
    await store.add(
        event,
        source_event={"id": event.id},
        attachments=(reference("https://cdn.discordapp.com/attachments/1/123/chart.png"),),
    )

    assert (await store.claim_batch())[0].key == event.identity
    evidence = await store.attachment_evidence(event.identity)
    assert [item.status for item in evidence] == ["download_failed"]
    await store.close()


async def test_source_event_evidence_contains_original_operational_payload(tmp_path):
    path = tmp_path / "application.db"
    store = await SQLiteSourceStore.open(path)
    event = raw()
    original = {
        "discord_message": {"content": "Review attached chart", "embeds": [{"title": "ABC"}]}
    }
    await store.add(event, source_event=original, attachments=())
    with closing(sqlite3.connect(path)) as db, db:
        (saved,) = db.execute(
            "SELECT event_payload FROM source_event_evidence WHERE source_id=?",
            (event.identity,),
        ).fetchone()
    assert '"title":"ABC"' in saved
    assert "Review attached chart" in saved
    await store.close()


async def test_source_event_oversize_is_recorded_as_a_gap_without_a_partial_copy(tmp_path):
    path = tmp_path / "application.db"
    store = await SQLiteSourceStore.open(path)
    event = raw()
    original = {"event_type": "discord_message", "content": "x" * (64 * 1024 + 1)}
    await store.add(event, source_event=original, attachments=())
    with closing(sqlite3.connect(path)) as db, db:
        saved, status, size = db.execute(
            "SELECT event_payload,capture_status,payload_bytes "
            "FROM source_event_evidence WHERE source_id=?",
            (event.identity,),
        ).fetchone()
    assert saved is None
    assert status == "oversize"
    assert size == len(json.dumps(original, ensure_ascii=False, separators=(",", ":")).encode())
    await store.close()


async def test_attachment_storage_rejects_symlinked_managed_root(tmp_path):
    outside = tmp_path / "outside"
    outside.mkdir()
    (tmp_path / "attachments").symlink_to(outside, target_is_directory=True)

    async def respond(request):
        return httpx2.Response(200, content=b"png", request=request)

    store = await SQLiteSourceStore.open(
        tmp_path / "application.db", attachment_transport=httpx2.MockTransport(respond)
    )
    event = raw()
    await store.add(
        event,
        source_event={"id": event.id},
        attachments=(reference("https://cdn.discordapp.com/attachments/1/123/chart.png"),),
    )
    evidence = await store.attachment_evidence(event.identity)
    assert evidence[0].status == "download_failed"
    assert not tuple(outside.iterdir())
    await store.close()
