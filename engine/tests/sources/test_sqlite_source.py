"""The source store keeps capture and recovery cursors atomic across restarts."""

import datetime as dt
import sqlite3
from contextlib import closing

import pytest
from pydantic import ValidationError

from copytrading_engine.shared.raw_message import RawMessage
from copytrading_engine.sources.recovery import RejectedCapture
from copytrading_engine.sources.sqlite import SQLiteSourceStore


def raw(message_id: int, *, age: int = 0, text: str = "signal") -> RawMessage:
    return RawMessage(
        schema_version=1,
        event_type="raw_message",
        source="discord",
        channel_id="7",
        id=str(message_id),
        timestamp=dt.datetime.now(dt.UTC) - dt.timedelta(seconds=age),
        text=text,
    )


async def test_live_capture_survives_restart_and_identity_is_stable(tmp_path):
    path = tmp_path / "app.db"
    source = await SQLiteSourceStore.open(path)
    event = raw(42, age=3600)
    await source.add(event)
    await source.add(event)
    # An edit after capture keeps the first version and never stops the source.
    await source.add(event.model_copy(update={"text": "different"}))
    await source.close()

    source = await SQLiteSourceStore.open(path)
    deliveries = await source.claim_batch()
    assert len(deliveries) == 1
    assert deliveries[0].mode == "live"  # Delay never reclassifies a live capture.
    assert deliveries[0].key == event.identity
    await source.close()

    source = await SQLiteSourceStore.open(path)
    assert await source.claim_batch() == deliveries
    await source.confirm(event.identity)
    assert await source.claim_batch() == ()
    await source.close()


async def test_recovery_page_and_cursor_are_atomic_and_a_late_post_is_still_read(tmp_path):
    path = tmp_path / "app.db"
    source = await SQLiteSourceStore.open(path)
    start = await source.recovery_start(7, 10)
    assert start.last_id == 10
    # An hour late: its buys are too old, but a sell in it is still copied, so it is read
    # (ADR-0010); the ledger judges each call's age.
    late = raw(11, age=3600)
    rejected = RejectedCapture({"source": "discord", "channel_id": "7", "id": "12"}, "invalid")
    await source.capture_recovery_page(7, [late], [rejected], 12)
    assert (await source.recovery_start(7, 1)).last_id == 12
    assert [delivery.key for delivery in await source.claim_batch()] == [late.identity]
    assert [delivery.mode for delivery in await source.claim_batch()] == ["live"]
    await source.confirm(late.identity)
    assert await source.rejected_count() == 1
    # A post edited after it was captured comes back changed in the next catch-up: the first
    # version stays, the cursor moves past it, and reading carries on.
    after = raw(13, age=3600)
    await source.capture_recovery_page(
        7, [late.model_copy(update={"text": "changed"}), after], [], 13
    )
    assert (await source.recovery_start(7, 1)).last_id == 13
    assert [delivery.key for delivery in await source.claim_batch()] == [after.identity]
    await source.confirm(after.identity)
    await source.close()

    source = await SQLiteSourceStore.open(path)
    assert (await source.recovery_start(7, 1)).last_id == 13
    assert await source.claim_batch() == ()
    with closing(sqlite3.connect(path)) as db:
        stored = db.execute("SELECT payload FROM source_captures WHERE id=?", (late.identity,))
        assert '"signal"' in stored.fetchone()[0]
    await source.close()


async def test_a_post_older_than_a_day_is_captured_but_not_read_back(tmp_path):
    """After a weekend away, only the last day's posts go to the model: an older one is kept as
    history, not read, so a long stop doesn't send every missed post to the reader."""
    source = await SQLiteSourceStore.open(tmp_path / "app.db")
    await source.recovery_start(7, 10)
    recent = raw(11, age=23 * 3600)
    old = raw(12, age=25 * 3600)
    await source.capture_recovery_page(7, [old, recent], [], 12)

    assert [delivery.key for delivery in await source.claim_batch()] == [recent.identity]
    with closing(sqlite3.connect(tmp_path / "app.db")) as db:
        mode = db.execute("SELECT mode FROM source_captures WHERE id=?", (old.identity,))
        assert mode.fetchone()[0] == "historical"
    await source.close()


async def test_recent_recovery_can_enter_live_parser_queue(tmp_path):
    source = await SQLiteSourceStore.open(tmp_path / "app.db")
    await source.recovery_start(7, 10)
    event = raw(11, age=20)
    await source.capture_recovery_page(7, [event], [], 11)
    assert (await source.claim_batch())[0].key == event.identity
    await source.close()


async def test_source_open_rejects_unsupported_existing_schema(tmp_path):
    import sqlite3

    path = tmp_path / "app.db"
    with closing(sqlite3.connect(path)) as db, db:
        db.execute("CREATE TABLE source_captures(id TEXT PRIMARY KEY)")
    with pytest.raises(RuntimeError, match="Incompatible source schema object"):
        await SQLiteSourceStore.open(path)

    path = tmp_path / "revision.db"
    source = await SQLiteSourceStore.open(path)
    await source.close()
    with closing(sqlite3.connect(path)) as db, db:
        db.execute(
            "UPDATE copytrading_engine_schema_revisions SET revision=99 WHERE component='source'"
        )
    with pytest.raises(RuntimeError, match="Unsupported source schema revision"):
        await SQLiteSourceStore.open(path)


async def test_unknown_stored_recovery_bootstrap_is_rejected_not_trusted(tmp_path):
    path = tmp_path / "application.db"
    store = await SQLiteSourceStore.open(path)
    await store.close()
    with closing(sqlite3.connect(path)) as db, db:
        db.execute(
            "INSERT INTO source_cursors(channel_id,last_id,bootstrap,updated_at) "
            "VALUES ('123', 7, 'everything', '2026-09-28T00:00:00+00:00')"
        )
    store = await SQLiteSourceStore.open(path)
    try:
        with pytest.raises(ValidationError):
            await store.recovery_start(123, 0)
        with pytest.raises(ValidationError):
            await store.recovery_progress()
    finally:
        await store.close()
