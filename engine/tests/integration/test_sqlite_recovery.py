"""The self-test store survives reopen, rejects other owners, and rolls back failed writes."""

import asyncio
import sqlite3
import threading
from contextlib import closing
from dataclasses import replace
from decimal import Decimal
from fractions import Fraction

import pytest

from copytrading_engine.host.errors import (
    ForeignInstallation,
    IdentityConflict,
    InstallationAlreadyRunning,
    StoreUnavailable,
    UnknownSchemaVersion,
)
from copytrading_engine.host.installation import Installation
from copytrading_engine.host.self_test.model import ParsedSelfTest, Stage, SubmitSelfTest
from copytrading_engine.host.self_test.store import SQLiteSelfTestStore


def test_acceptance_survives_reopen_and_retry(tmp_path):
    path = tmp_path / "application.db"
    command = SubmitSelfTest("sim-1", "Bought AAPL 1/6 at 200", ("self-test-a", "self-test-b"))
    with Installation(path) as installation, SQLiteSelfTestStore(installation) as store:
        accepted = store.accept(command)
    with Installation(path) as installation, SQLiteSelfTestStore(installation) as store:
        retried = store.accept(command)
        assert accepted.newly_accepted
        assert not retried.newly_accepted
        assert retried.workflow == accepted.workflow
        assert store.pending() == ("sim-1",)
        with pytest.raises(IdentityConflict):
            store.accept(replace(command, text="different"))
        assert store.get("sim-1") == accepted.workflow

        with closing(sqlite3.connect(path)) as connection:
            rows = connection.execute(
                "SELECT (SELECT COUNT(*) FROM workflows), "
                "(SELECT COUNT(*) FROM jobs), "
                "(SELECT COUNT(*) FROM audit_events)"
            ).fetchone()
        assert rows == (1, 1, 1)


async def test_accept_async_marks_only_the_transaction_that_inserts_as_new(tmp_path):
    command = SubmitSelfTest(
        "sim-async-acceptance",
        "Bought AAPL 1/6 at 200",
        ("self-test-a",),
    )
    with (
        Installation(tmp_path / "application.db") as installation,
        SQLiteSelfTestStore(installation) as store,
    ):
        first = await store.accept_async(command)
        retry = await store.accept_async(command)
        assert not await store.trace_anchor_exported_async(command.command_id)
        store.mark_trace_anchor_exported(command.command_id)
        assert await store.trace_anchor_exported_async(command.command_id)

    assert first.newly_accepted
    assert not retry.newly_accepted
    assert first.workflow == retry.workflow
    with (
        Installation(tmp_path / "application.db") as installation,
        SQLiteSelfTestStore(installation) as reopened_store,
    ):
        assert await reopened_store.trace_anchor_exported_async(command.command_id)


def test_store_rejects_an_instance_id_that_does_not_own_the_database(tmp_path):
    path = tmp_path / "application.db"
    with (
        Installation(path, instance_id="10000000-0000-4000-8000-000000000001") as installation,
        SQLiteSelfTestStore(installation),
    ):
        pass

    with pytest.raises(ForeignInstallation):
        with (
            Installation(path, instance_id="20000000-0000-4000-8000-000000000002") as installation,
            SQLiteSelfTestStore(installation),
        ):
            pass


def test_store_lock_rejects_a_second_concurrent_owner(tmp_path):
    path = tmp_path / "application.db"
    with Installation(path) as installation, SQLiteSelfTestStore(installation):
        with pytest.raises(InstallationAlreadyRunning):
            with Installation(path) as installation, SQLiteSelfTestStore(installation):
                pass


def test_held_sqlite_writer_lock_fails_without_acknowledging_acceptance(tmp_path):
    path = tmp_path / "application.db"
    command = SubmitSelfTest("sim-1", "Bought AAPL 1/6 at 200", ("self-test-a",))
    with (
        Installation(path, busy_timeout_ms=25) as installation,
        SQLiteSelfTestStore(installation) as store,
    ):
        with closing(sqlite3.connect(path, isolation_level=None)) as connection:
            connection.execute("BEGIN IMMEDIATE")
            with pytest.raises(StoreUnavailable):
                store.accept(command)
            connection.execute("ROLLBACK")

        assert store.pending() == ()


def test_store_refuses_unknown_schema_revision(tmp_path):
    path = tmp_path / "application.db"
    with closing(sqlite3.connect(path)) as connection:
        connection.execute("PRAGMA user_version = 99")

    with pytest.raises(UnknownSchemaVersion):
        with Installation(path) as installation, SQLiteSelfTestStore(installation):
            pass


def test_failed_stage_transition_rolls_back_every_write(tmp_path):
    path = tmp_path / "application.db"
    command = SubmitSelfTest("sim-1", "Bought AAPL 1/6 at 200", ("self-test-a",))
    parsed = ParsedSelfTest("AAPL", "buy", Fraction(1, 6), Decimal("200"))
    with Installation(path) as installation, SQLiteSelfTestStore(installation) as store:
        store.accept(command)
        with closing(sqlite3.connect(path)) as connection:
            connection.execute(
                "CREATE TRIGGER reject_parse_audit BEFORE INSERT ON audit_events "
                "WHEN NEW.event_type = 'SelfTestParsed' "
                "BEGIN SELECT RAISE(ABORT, 'injected transition failure'); END"
            )

        with pytest.raises(StoreUnavailable):
            store.advance("sim-1", Stage.CAPTURED, Stage.PARSED, (), parsed=parsed)

        assert store.get("sim-1").stage is Stage.CAPTURED
        assert store.pending() == ("sim-1",)
        with closing(sqlite3.connect(path)) as connection:
            audit_types = connection.execute(
                "SELECT event_type FROM audit_events WHERE command_id = 'sim-1' ORDER BY event_id"
            ).fetchall()
        assert audit_types == [("SelfTestAccepted",)]


def test_uncertain_commit_still_closes_store_and_releases_installation_lock(tmp_path):
    path = tmp_path / "application.db"
    installation = Installation(path).__enter__()
    store = SQLiteSelfTestStore(installation)
    store.__enter__()
    command = SubmitSelfTest("sim-1", "Bought AAPL 1/6 at 200", ("self-test-a",))

    def deny_commit(
        action: int,
        first: str | None,
        second: str | None,
        database: str | None,
        trigger: str | None,
    ) -> int:
        del second, database, trigger
        if action == sqlite3.SQLITE_TRANSACTION and first == "COMMIT":
            return sqlite3.SQLITE_DENY
        return sqlite3.SQLITE_OK

    store._schedule(lambda: store._require_connection().set_authorizer(deny_commit)).result(
        timeout=3
    )
    try:
        with pytest.raises(StoreUnavailable):
            store.accept(command)
        store.close()
    finally:
        installation.__exit__(None, None, None)

    with Installation(path) as installation, SQLiteSelfTestStore(installation):
        pass


def test_store_operations_use_explicit_transactions(tmp_path):
    path = tmp_path / "application.db"
    command = SubmitSelfTest("sim-1", "Bought AAPL 1/6 at 200", ("self-test-a",))
    parsed = ParsedSelfTest("AAPL", "buy", Fraction(1, 6), Decimal("200"))
    with Installation(path) as installation, SQLiteSelfTestStore(installation) as store:
        store.accept(command)
        store.advance("sim-1", Stage.CAPTURED, Stage.PARSED, (), parsed=parsed)
        statements: list[str] = []
        store._schedule(
            lambda: store._require_connection().set_trace_callback(statements.append)
        ).result(timeout=3)

        store.get("sim-1")
        assert statements[0] == "BEGIN"
        assert statements[-1] == "COMMIT"
        statements.clear()

        store.pending()
        assert statements[0] == "BEGIN"
        assert statements[-1] == "COMMIT"
        statements.clear()

        store.load_command("sim-1")
        assert statements[0] == "BEGIN"
        assert statements[-1] == "COMMIT"
        statements.clear()

        store.load_parsed("sim-1")
        assert statements[0] == "BEGIN"
        assert statements[-1] == "COMMIT"
        statements.clear()

        store.counts()
        assert statements[0] == "BEGIN"
        assert statements[-1] == "COMMIT"


async def test_cancelled_database_caller_drains_before_store_close(tmp_path):
    path = tmp_path / "application.db"
    entered = threading.Event()
    release = threading.Event()
    command = SubmitSelfTest("sim-1", "Bought AAPL 1/6 at 200", ("self-test-a",))
    installation = Installation(path).__enter__()
    store = SQLiteSelfTestStore(installation)
    store.__enter__()

    def pause_transaction() -> int:
        entered.set()
        if not release.wait(timeout=3):
            raise RuntimeError("test barrier was not released")
        return 0

    store._schedule(
        lambda: store._require_connection().create_function(
            "pause_transaction", 0, pause_transaction
        )
    ).result(timeout=3)
    with closing(sqlite3.connect(path)) as connection:
        connection.execute(
            "CREATE TRIGGER wait_for_cancellation BEFORE INSERT ON audit_events "
            "BEGIN SELECT pause_transaction(); END"
        )

    operation = asyncio.create_task(store.accept_async(command))
    assert await asyncio.to_thread(entered.wait, 3)
    operation.cancel()
    close = asyncio.create_task(store.aclose())
    done, _ = await asyncio.wait({operation}, timeout=0)
    assert not done
    release.set()
    with pytest.raises(asyncio.CancelledError):
        await operation
    await close
    installation.__exit__(None, None, None)

    with closing(sqlite3.connect(path)) as connection:
        row = connection.execute(
            "SELECT stage, outcomes_json FROM workflows WHERE command_id = 'sim-1'"
        ).fetchone()
    assert row == ("captured", "[]")
