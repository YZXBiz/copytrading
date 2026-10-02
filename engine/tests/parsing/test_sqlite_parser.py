"""The parser store keeps identities, budgets, and delivery cursors across restarts."""

import datetime as dt

import pytest

from copytrading_engine.parsing.application import outcome
from copytrading_engine.parsing.contracts import DestinationRegistration, RequestReservation
from copytrading_engine.parsing.sqlite import SQLiteExtractionStore
from copytrading_engine.shared.raw_message import RawMessage
from copytrading_engine.shared.signals import SourceIdentityConflict


def raw(message_id: int, *, channel: str = "7", text: str = "commentary") -> RawMessage:
    return RawMessage(
        schema_version=1,
        event_type="raw_message",
        source="discord",
        channel_id=channel,
        id=str(message_id),
        timestamp=dt.datetime.now(dt.UTC),
        text=text,
    )


async def test_parser_identity_head_of_line_budget_and_restart(tmp_path):
    path = tmp_path / "app.db"
    store = await SQLiteExtractionStore.open(path)
    first, second, parallel = raw(1), raw(2), raw(3, channel="8")
    for event in first, second, parallel:
        await store.add(event)
    with pytest.raises(SourceIdentityConflict):
        await store.add(first.model_copy(update={"text": "changed"}))
    now = dt.datetime.now(dt.UTC)
    job = await store.next(now)
    assert job is not None
    assert job.key == first.identity
    assert await store.reserve(
        RequestReservation(first.identity, 0, now.date(), 1, now + dt.timedelta(seconds=30))
    )
    assert not await store.reserve(
        RequestReservation(parallel.identity, 0, now.date(), 1, now + dt.timedelta(seconds=30))
    )
    job = await store.next(now)
    assert job is not None
    assert job.key == parallel.identity
    await store.close()

    store = await SQLiteExtractionStore.open(path)
    job = await store.next(now)
    assert job is not None
    assert job.key == parallel.identity
    await store.finish(first.identity, outcome(first, "ignore", "commentary", model="test"))
    await store.finish(parallel.identity, outcome(parallel, "ignore", "commentary", model="test"))
    job = await store.next(now)
    assert job is not None
    assert job.key == second.identity
    assert [item.key for item in await store.claim_pending_signals()] == [
        first.identity,
        parallel.identity,
    ]
    assert [item.key for item in await store.claim_pending_notifications()] == [
        first.identity,
        parallel.identity,
    ]
    await store.close()

    store = await SQLiteExtractionStore.open(path)
    assert [item.key for item in await store.claim_pending_signals()] == [
        first.identity,
        parallel.identity,
    ]
    await store.confirm_signal(first.identity)
    await store.confirm_notification(first.identity)
    assert [item.key for item in await store.claim_pending_signals()] == [parallel.identity]
    assert [item.key for item in await store.claim_pending_notifications()] == [parallel.identity]
    await store.close()


async def test_parser_open_rejects_unsupported_revision(tmp_path):
    import sqlite3
    from contextlib import closing

    path = tmp_path / "app.db"
    store = await SQLiteExtractionStore.open(path)
    await store.close()
    with closing(sqlite3.connect(path)) as db, db:
        db.execute(
            "UPDATE copytrading_engine_schema_revisions SET revision=1 WHERE component='parser'"
        )
    with pytest.raises(RuntimeError, match="Unsupported parser schema revision"):
        await SQLiteExtractionStore.open(path)


async def test_workflow_and_destination_identities_survive_restart_and_retry(tmp_path):
    path = tmp_path / "lineage.db"
    event = raw(901)
    registrations = (
        DestinationRegistration("account-a", "a" * 64),
        DestinationRegistration("account-b", "a" * 64),
    )
    store = await SQLiteExtractionStore.open(path)
    await store.add(event)
    job = await store.next(dt.datetime.now(dt.UTC))
    assert job is not None
    assert job.workflow_id is not None
    assert job.trace_id is not None
    assert job.workflow_id != job.trace_id
    first_destinations = await store.prepare_destinations(event.identity, registrations)
    assert {item.account_id for item in first_destinations} == {"account-a", "account-b"}
    first_attempt = await store.reserve_destination_attempt(event.identity, "account-a")
    assert first_attempt.attempt == 1
    workflow_id, trace_id = job.workflow_id, job.trace_id
    destination_id = first_attempt.destination_id
    await store.close()

    store = await SQLiteExtractionStore.open(path)
    replayed = await store.prepare_destinations(event.identity, registrations)
    assert {item.workflow_id for item in replayed} == {workflow_id}
    assert {item.trace_id for item in replayed} == {trace_id}
    replayed_attempt = await store.reserve_destination_attempt(event.identity, "account-a")
    assert replayed_attempt.destination_id == destination_id
    assert replayed_attempt.attempt == 2
    second_destination = await store.reserve_destination_attempt(event.identity, "account-b")
    assert second_destination.attempt == 1
    assert second_destination.destination_id != destination_id
    await store.close()


async def test_destination_route_mismatch_is_rejected_before_account_receipt(tmp_path):
    store = await SQLiteExtractionStore.open(tmp_path / "route-mismatch.db")
    event = raw(902)
    await store.add(event)
    await store.prepare_destinations(
        event.identity,
        (DestinationRegistration("account-a", "a" * 64),),
    )

    with pytest.raises(SourceIdentityConflict, match="destinations differ"):
        await store.prepare_destinations(
            event.identity,
            (DestinationRegistration("account-b", "b" * 64),),
        )
    await store.close()


async def test_unconfirmed_delivery_count_and_cursor_exceed_first_batch(tmp_path):
    store = await SQLiteExtractionStore.open(tmp_path / "app.db")
    for message_id in range(125):
        event = raw(message_id)
        await store.add(event)
        await store.finish(event.identity, outcome(event, "ignore", "commentary", model="test"))

    assert await store.pending_count() == 0
    assert await store.pending_delivery_count() == 125
    first = await store.claim_pending_signals(limit=100)
    assert len(first) == 100
    assert [item.seq for item in first] == list(range(1, 101))
    later = await store.claim_pending_signals(limit=100, after_seq=first[-1].seq)
    assert len(later) == 25
    assert [item.seq for item in later] == list(range(101, 126))
    assert (await store.claim_pending_signals(limit=100, after_seq=later[-1].seq)) == ()
    assert [item.seq for item in await store.claim_pending_signals(limit=100)] == list(
        range(1, 101)
    )
    await store.confirm_signal(first[0].key)
    assert await store.pending_delivery_count() == 124
    await store.close()
