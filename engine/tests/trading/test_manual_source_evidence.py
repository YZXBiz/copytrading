"""Manual source evidence is read-only and needs a confirmed live review."""

import datetime as dt

import pytest

from copytrading_engine.parsing.application import outcome
from copytrading_engine.parsing.sqlite import SQLiteExtractionStore
from copytrading_engine.shared.raw_message import RawMessage
from copytrading_engine.sources.sqlite import SQLiteSourceStore
from copytrading_engine.trading.adapters.operator_queries import manual_source_evidence


async def test_manual_source_evidence_is_read_only_and_requires_confirmed_live_review(tmp_path):
    database = tmp_path / "application.db"
    source = await SQLiteSourceStore.open(database)
    parser = await SQLiteExtractionStore.open(database)
    raw = RawMessage(
        schema_version=1,
        event_type="raw_message",
        source="discord",
        channel_id="demo",
        id="message-1",
        timestamp=dt.datetime(2026, 1, 5, 15, tzinfo=dt.UTC),
        text="ambiguous trade",
    )
    await source.add(raw)
    await parser.add(raw)
    await parser.finish(raw.identity, outcome(raw, "review", "ambiguous", model="fixture"))

    with pytest.raises(ValueError, match="manual_source_unavailable"):
        manual_source_evidence(database, raw.identity)

    assert (await source.claim_batch())[0].key == raw.identity
    await source.confirm(raw.identity)
    before = database.stat().st_mtime_ns
    evidence = manual_source_evidence(database, raw.identity)
    after = database.stat().st_mtime_ns

    assert evidence.source_id == raw.identity
    assert evidence.source_revision == 1
    assert evidence.text == raw.text
    assert evidence.accepted_interpretation.decision == "review"
    assert after == before
    await parser.close()
    await source.close()
