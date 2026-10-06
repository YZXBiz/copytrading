"""SQLite durability at the broker intent and account ownership boundary."""

import asyncio
import datetime as dt
import os
import pwd
import sqlite3
import subprocess
import sys
import threading
from contextlib import closing, contextmanager
from pathlib import Path
from types import SimpleNamespace

import pytest
from pydantic import SecretStr

from copytrading_engine.execution.adapters.alpaca.broker import AlpacaCredentials
from copytrading_engine.execution.adapters.owner import ExecutionOwner
from copytrading_engine.execution.adapters.resources import default_account_lock_root
from copytrading_engine.execution.adapters.sqlite_ledger import Store
from copytrading_engine.execution.application.engine import CopyEngine
from copytrading_engine.execution.domain.events import JournalEvent, SignalRejected
from copytrading_engine.execution.domain.lifecycle import AccountControlCommand
from copytrading_engine.execution.domain.signals import CopyConfig
from copytrading_engine.shared.signals import StockSignal

from .builders import NOW, destination_signal, event, receive
from .fakes import FakeBroker


def _journaled(store):
    """Everything the store journaled, oldest first."""
    return tuple(
        SimpleNamespace(id=seq, event=event) for seq, event in reversed(store.event_page(None, 100))
    )


def _store(path):
    store = Store(path)
    store.bind_identity("paper-demo", "paper")
    return store


def test_default_account_lock_root_ignores_home_override(tmp_path, monkeypatch):
    expected = Path(pwd.getpwuid(os.getuid()).pw_dir) / ".copytrading" / "account-locks"
    monkeypatch.setenv("HOME", str(tmp_path / "alternate-home"))
    assert Path.home() != Path(pwd.getpwuid(os.getuid()).pw_dir)
    assert default_account_lock_root() == expected


def test_snapshot_journal_and_notification_survive_reopen(tmp_path):
    path = tmp_path / "execution.sqlite3"
    store = _store(path)
    broker = FakeBroker()
    engine = CopyEngine(store, broker, CopyConfig(sources=("discord:demo",)))
    engine.bind(NOW)
    signal = StockSignal.model_validate(event())
    receive(engine, signal, NOW)
    engine.process(NOW)
    snapshot = store.load()
    reports = _journaled(store)
    notifications = store.pending_notifications()
    assert snapshot.messages["discord:demo:1"].id == signal.id
    assert snapshot.messages["discord:demo:1"].cash_anchor is not None
    assert reports
    assert notifications
    assert store.db.execute("PRAGMA journal_mode").fetchone()[0] == "wal"
    assert store.db.execute("PRAGMA synchronous").fetchone()[0] == 2
    store.close()

    reopened = _store(path)
    assert reopened.load() == snapshot
    assert _journaled(reopened) == reports
    assert reopened.pending_notifications() == notifications
    reopened.confirm_notification(notifications[0][0])
    assert len(reopened.pending_notifications()) == len(notifications) - 1
    reopened.close()


def test_saved_snapshot_missing_revision_is_refused_not_reset(tmp_path):
    store = _store(tmp_path / "execution.sqlite3")
    CopyEngine(store, FakeBroker(), CopyConfig(sources=["discord:demo"])).bind(NOW)
    store.db.execute("UPDATE snapshot SET data='{}' WHERE singleton=1")
    with pytest.raises(RuntimeError, match="snapshot schema version"):
        store.load()
    store.close()


def test_previous_development_execution_schema_is_refused(tmp_path):
    path = tmp_path / "execution.sqlite3"
    with closing(sqlite3.connect(path)) as db, db:
        db.execute(
            "CREATE TABLE copytrading_engine_schema_revisions "
            "(component TEXT PRIMARY KEY, revision INTEGER NOT NULL)"
        )
        db.execute("INSERT INTO copytrading_engine_schema_revisions VALUES ('execution', 3)")
    with pytest.raises(RuntimeError, match="Unsupported execution schema revision: 3"):
        Store(path)


def test_destination_terms_commit_before_ack_and_survive_restart(tmp_path):
    path = tmp_path / "execution.sqlite3"
    store = _store(path)
    broker = FakeBroker()
    policy = CopyConfig(
        sources=["discord:demo"],
        max_order_usd=500,
        max_symbol_usd=1000,
        max_total_usd=2000,
    )
    engine = CopyEngine(store, broker, policy)
    engine.bind(NOW)
    signal = StockSignal.model_validate(event(price="33.12"))
    # A 1/6 call into a $3000 full position is $500.
    accepted = destination_signal(signal, full_position_usd="3000", revision="a" * 64)
    engine.receive(accepted, NOW)
    saved = store.load().messages["discord:demo:1"]
    assert saved.destination == accepted.terms
    assert any(
        report.event.payload.kind == "message"
        and report.event.payload.destination == accepted.terms
        for report in _journaled(store)
    )
    assert broker.calls == 0
    store.close()

    reopened = _store(path)
    replay = CopyEngine(reopened, broker, policy)
    replay.bind(NOW)
    replay.receive(accepted, NOW)
    with pytest.raises(ValueError, match="accepted terms"):
        replay.receive(destination_signal(signal, full_position_usd="100", revision="b" * 64), NOW)
    replay.process(NOW)
    order = replay.ledger.orders()[0]
    assert order.qty * order.limit_price <= 500
    assert order.qty * order.limit_price > 499
    assert broker.calls == 1
    reopened.close()


def test_a_call_with_no_size_for_an_account_set_to_wait_is_a_durable_review(tmp_path):
    path = tmp_path / "execution.sqlite3"
    store = _store(path)
    broker = FakeBroker()
    engine = CopyEngine(store, broker, CopyConfig(sources=["discord:demo"]))
    engine.bind(NOW)
    source = event()
    source["instructions"][0]["fraction"] = None
    source["evidence"][0]["fraction"] = None
    signal = StockSignal.model_validate(source)
    engine.receive(destination_signal(signal, full_position_usd="3000", default_fraction=None), NOW)
    message = store.load().messages["discord:demo:1"]
    assert message.status == "review_required"
    assert message.review_reason == "missing_source_fraction"
    assert message.evidence == signal.evidence
    assert message.destination.connection.full_position_usd == 3000
    assert any(
        report.event.payload.kind == "message"
        and report.event.payload.review_reason == "missing_source_fraction"
        for report in _journaled(store)
    )
    engine.process(NOW)
    assert broker.calls == 0
    store.close()
    reopened = _store(path)
    recovered = reopened.load().messages["discord:demo:1"]
    assert recovered.review_reason == "missing_source_fraction"
    assert recovered.destination == message.destination
    assert recovered.evidence == signal.evidence
    reopened.close()


def test_durable_submit_intent_precedes_broker_post(tmp_path):
    store = _store(tmp_path / "execution.sqlite3")
    broker = FakeBroker()
    engine = CopyEngine(store, broker, CopyConfig(sources=("discord:demo",)))
    engine.bind(NOW)
    receive(engine, StockSignal.model_validate(event()), NOW)
    original_submit = broker.submit
    observed = []

    def submit(request):
        persisted = store.load().orders[request.client_order_id]
        anchor = store.load().messages[persisted.message_id].cash_anchor
        observed.append(
            (
                anchor is not None,
                persisted.submit_started_at is not None,
                any(
                    report.event.payload.kind == "submit_started"
                    and report.event.payload.client_id == request.client_order_id
                    for report in _journaled(store)
                ),
            )
        )
        return original_submit(request)

    broker.submit = submit
    engine.process(NOW)
    assert observed == [(True, True, True)]
    store.close()


def test_cash_anchor_commit_failure_leaves_no_order_and_reopens_cleanly(tmp_path):
    path = tmp_path / "execution.sqlite3"
    store = _store(path)
    broker = FakeBroker()
    engine = CopyEngine(store, broker, CopyConfig(sources=["discord:demo"]))
    engine.bind(NOW)
    receive(engine, StockSignal.model_validate(event()), NOW)
    original_save = store.save

    def fail_anchor(snapshot, journal):
        if journal.payload.kind == "cash_anchor_recorded":
            raise RuntimeError("anchor commit failed")
        original_save(snapshot, journal)

    store.save = fail_anchor
    with pytest.raises(RuntimeError, match="anchor commit failed"):
        engine.process(NOW)
    assert broker.calls == 0
    assert store.load().messages["discord:demo:1"].cash_anchor is None
    store.close()

    reopened = _store(path)
    resumed = CopyEngine(reopened, broker, CopyConfig(sources=["discord:demo"]))
    resumed.bind(NOW)
    resumed.process(NOW)
    assert broker.calls == 1
    assert reopened.load().messages["discord:demo:1"].cash_anchor is not None
    assert any(
        report.event.payload.kind == "cash_anchor_recorded" for report in _journaled(reopened)
    )
    reopened.close()


def test_account_and_environment_are_fixed_to_verified_identity(tmp_path):
    path = tmp_path / "execution.sqlite3"
    store = _store(path)
    CopyEngine(store, FakeBroker(), CopyConfig(sources=["discord:demo"])).bind(NOW)
    store.close()
    other = Store(path)
    with pytest.raises(RuntimeError, match="different broker account or environment"):
        other.bind_identity("paper-demo", "live")
    with pytest.raises(RuntimeError, match="different broker account or environment"):
        other.bind_identity("other-account", "paper")
    other.close()


def test_startup_rejects_incompatible_schema_before_bind_or_receive(tmp_path):
    path = tmp_path / "execution.sqlite3"
    with closing(sqlite3.connect(path)) as db, db:
        db.execute("CREATE TABLE notifications(id INTEGER PRIMARY KEY, delivered_at REAL)")
    with pytest.raises(RuntimeError, match="Incompatible execution schema object: notifications"):
        Store(path)
    with closing(sqlite3.connect(path)) as db, db:
        db.execute("BEGIN EXCLUSIVE")  # Startup failure closed its connection.
        db.execute("ROLLBACK")

    valid_path = tmp_path / "revision.sqlite3"
    valid = _store(valid_path)
    valid.close()
    with closing(sqlite3.connect(valid_path)) as db, db:
        db.execute(
            "UPDATE copytrading_engine_schema_revisions SET revision=2 WHERE component='execution'"
        )
    with pytest.raises(RuntimeError, match="Unsupported execution schema revision"):
        Store(valid_path)


def test_failure_before_commit_rolls_back_all_three_records(tmp_path, monkeypatch):
    path = tmp_path / "execution.sqlite3"
    store = _store(path)
    engine = CopyEngine(store, FakeBroker(), CopyConfig(sources=("discord:demo",)))
    engine.bind(NOW)
    before = store.load()
    reports_before = _journaled(store)
    notices_before = store.pending_notifications()

    def fail_notification(*_):
        raise RuntimeError("notification failure")

    monkeypatch.setattr(
        "copytrading_engine.execution.adapters.sqlite_ledger.execution_notification",
        fail_notification,
    )
    with pytest.raises(RuntimeError, match="notification failure"):
        receive(engine, StockSignal.model_validate(event()), NOW)
    assert store.load() == before
    assert _journaled(store) == reports_before
    assert store.pending_notifications() == notices_before
    store.close()


class _CommitThenLoseConfirmation:
    def __init__(self, db: sqlite3.Connection):
        self.db = db

    def execute(self, sql, *args):
        result = self.db.execute(sql, *args)
        if sql == "COMMIT":
            raise OSError("commit confirmation lost")
        return result

    def close(self):
        self.db.close()


def test_uncertain_commit_discards_session_and_requires_reopen(tmp_path):
    path = tmp_path / "execution.sqlite3"
    store = _store(path)
    engine = CopyEngine(store, FakeBroker(), CopyConfig(sources=("discord:demo",)))
    engine.bind(NOW)
    store.db = _CommitThenLoseConfirmation(store.db)
    with pytest.raises(OSError, match="commit confirmation lost"):
        receive(engine, StockSignal.model_validate(event()), NOW)
    assert not store.usable
    with pytest.raises(RuntimeError, match="unusable"):
        store.load()
    reopened = _store(path)
    assert "discord:demo:1" in reopened.load().messages
    reopened.close()


async def test_owner_binds_only_on_explicit_open_and_replays_receive(tmp_path):
    broker = FakeBroker()
    keys = AlpacaCredentials(SecretStr("key"), SecretStr("secret"))
    assert "test-secret" not in repr(keys)
    assert broker.calls == 0
    owner = await ExecutionOwner.open(
        tmp_path / "account-a",
        keys,
        CopyConfig(sources=("discord:demo",)),
        environment="paper",
        broker_factory=lambda *_: broker,
        account_lock_root=tmp_path / "locks",
    )
    try:
        await owner.recover_account(NOW)
        await owner.control_account(
            AccountControlCommand(command_id="enable-a", account_id="account-a", action="resume"),
            NOW,
        )
        signal = StockSignal.model_validate(event())
        await owner.receive(destination_signal(signal), NOW)
        await owner.receive(destination_signal(signal), NOW + dt.timedelta(seconds=1))
        observation = await owner.observation()
        assert len(observation.ledger.messages) == 1
        assert observation.ledger.account_id == "paper-demo"
        with pytest.raises(ValueError, match="reused with different content"):
            await owner.receive(
                destination_signal(signal.model_copy(update={"text": "changed"})), NOW
            )
        with pytest.raises(RuntimeError, match="Another executor owns this broker account"):
            await ExecutionOwner.open(
                tmp_path / "account-b",
                keys,
                CopyConfig(sources=("discord:demo",)),
                environment="paper",
                broker_factory=lambda *_: FakeBroker(),
                account_lock_root=tmp_path / "locks",
            )
    finally:
        await owner.close()


async def test_account_lock_blocks_other_process_with_different_state_parent(tmp_path):
    child_code = """
import asyncio, sys
from pathlib import Path
from pydantic import SecretStr
from copytrading_engine.execution.adapters.alpaca.broker import AlpacaCredentials
from copytrading_engine.execution.domain.signals import CopyConfig
from copytrading_engine.execution.adapters.owner import ExecutionOwner
from copytrading_engine.execution.adapters.alpaca.models import decode_account

class Broker:
    def account(self):
        return decode_account({
            "id": "paper-demo", "status": "ACTIVE", "cash": "5000", "equity": "5000",
            "last_equity": "5000", "buying_power": "5000", "currency": "USD",
            "trading_blocked": False,
            "account_blocked": False, "trade_suspended_by_user": False,
        })
    def positions(self): return ()
    def open_orders(self): return ()
    def close(self): pass

async def main():
    owner = await ExecutionOwner.open(
        Path(sys.argv[1]), AlpacaCredentials(SecretStr("key"), SecretStr("secret")),
        CopyConfig(sources=("discord:demo",)), environment="paper",
        broker_factory=lambda *_: Broker(), account_lock_root=Path(sys.argv[2]),
    )
    print("READY", flush=True)
    await asyncio.to_thread(sys.stdin.readline)
    await owner.close()

asyncio.run(main())
"""
    lock_root = tmp_path / "shared-locks"
    keys = AlpacaCredentials(SecretStr("key"), SecretStr("secret"))
    env = os.environ | {"PYTHONPATH": str(Path(__file__).resolve().parents[2] / "src")}
    child = subprocess.Popen(
        [
            sys.executable,
            "-u",
            "-c",
            child_code,
            str(tmp_path / "first" / "account"),
            str(lock_root),
        ],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        env=env,
    )
    try:
        assert child.stdout is not None
        assert await asyncio.to_thread(child.stdout.readline) == "READY\n"
        with pytest.raises(RuntimeError, match="Another executor owns this broker account"):
            await ExecutionOwner.open(
                tmp_path / "second" / "account",
                keys,
                CopyConfig(sources=("discord:demo",)),
                environment="paper",
                broker_factory=lambda *_: FakeBroker(),
                account_lock_root=lock_root,
            )
    finally:
        if child.poll() is None:
            assert child.stdin is not None
            child.stdin.write("release\n")
            child.stdin.flush()
        output, _ = await asyncio.to_thread(child.communicate, timeout=10)
        assert child.returncode == 0, output

    owner = await ExecutionOwner.open(
        tmp_path / "second" / "account",
        keys,
        CopyConfig(sources=("discord:demo",)),
        environment="paper",
        broker_factory=lambda *_: FakeBroker(),
        account_lock_root=lock_root,
    )
    await owner.close()


async def test_owner_uses_injected_observer_on_worker(tmp_path):
    thread_ids = []
    spans = []
    events = []

    class Observer:
        @contextmanager
        def span(self, name, message_id):
            thread_ids.append(threading.get_ident())
            spans.append((name, message_id))
            yield

        def event(self, name):
            thread_ids.append(threading.get_ident())
            events.append(name)

    keys = AlpacaCredentials(SecretStr("key"), SecretStr("secret"))
    owner = await ExecutionOwner.open(
        tmp_path / "account",
        keys,
        CopyConfig(sources=("discord:demo",)),
        environment="paper",
        broker_factory=lambda *_: FakeBroker(),
        account_lock_root=tmp_path / "locks",
        observer=Observer(),
    )
    try:
        await owner.recover_account(NOW)
        await owner.control_account(
            AccountControlCommand(
                command_id="enable-observed", account_id="account", action="resume"
            ),
            NOW,
        )
        await owner.receive(destination_signal(StockSignal.model_validate(event())), NOW)
        await owner._submit(lambda resource: resource.engine.process(NOW))
        assert "account_inventoried" in events
        assert "submit_started" in events
        assert any(name == "order_submission" for name, _ in spans)
        assert thread_ids
        assert set(thread_ids) == {owner._executor._threads.copy().pop().ident}
        assert threading.get_ident() not in thread_ids
    finally:
        await owner.close()


def test_rejected_signal_is_durable_without_notification(tmp_path):
    store = _store(tmp_path / "execution.sqlite3")
    engine = CopyEngine(store, FakeBroker(), CopyConfig(sources=("discord:demo",)))
    engine.bind(NOW)
    engine.ledger.record(
        JournalEvent(at=NOW, payload=SignalRejected(payload_hash="a" * 64, reason="bad source"))
    )
    assert len(_journaled(store)) == 2
    assert not store.pending_notifications()
    store.close()
