"""The self-test parses its fixture, records each outcome, and resumes after reopen."""

import sqlite3
from contextlib import closing
from decimal import Decimal
from fractions import Fraction

import pytest

from copytrading_engine.host.errors import InvalidCommand, UnsupportedSelfTest
from copytrading_engine.host.installation import Installation
from copytrading_engine.host.self_test.model import ParsedSelfTest, Stage, SubmitSelfTest
from copytrading_engine.host.self_test.parser import SelfTestParser
from copytrading_engine.host.self_test.service import SelfTestService
from copytrading_engine.host.self_test.store import SQLiteSelfTestStore


def test_parser_extracts_the_published_simulation_fixture():
    parsed = SelfTestParser().parse("Bought AAPL 1/6 at 200")

    assert parsed == ParsedSelfTest(
        symbol="AAPL",
        action="buy",
        quantity=Fraction(1, 6),
        unit_price=Decimal("200"),
    )


def test_parser_rejects_unsupported_text_as_a_domain_error():
    with pytest.raises(UnsupportedSelfTest):
        SelfTestParser().parse("Sell AAPL tomorrow")


def test_simulation_command_rejects_destinations_outside_the_contract_allowlist():
    with pytest.raises(InvalidCommand):
        SubmitSelfTest("sim-1", "Bought AAPL 1/6 at 200", ("live-account",))


async def test_service_records_one_simulated_outcome_per_selected_destination(tmp_path):
    path = tmp_path / "application.db"
    command = SubmitSelfTest("sim-1", "Bought AAPL 1/6 at 200", ("self-test-a", "self-test-b"))
    with Installation(path) as installation, SQLiteSelfTestStore(installation) as store:
        service = SelfTestService(store, SelfTestParser())
        accepted = await service.submit(command)
        assert accepted.stage is Stage.CAPTURED

        await service.process_pending()

        completed = await store.get_async("sim-1")
        assert completed.stage is Stage.COMPLETED
        assert tuple((outcome.account_id, outcome.result) for outcome in completed.outcomes) == (
            ("self-test-a", "simulated"),
            ("self-test-b", "simulated"),
        )
        assert completed.trace_id == accepted.trace_id

    with closing(sqlite3.connect(path)) as connection, connection:
        audit_rows = connection.execute(
            "SELECT event_type FROM audit_events WHERE command_id = 'sim-1' ORDER BY event_id"
        ).fetchall()
    assert audit_rows == [
        ("SelfTestAccepted",),
        ("SelfTestParsed",),
        ("SelfTestCompleted",),
    ]


async def test_unsupported_text_fails_atomically_with_typed_parse_rejection(tmp_path):
    path = tmp_path / "application.db"
    command = SubmitSelfTest("sim-1", "Sell AAPL tomorrow", ("self-test-a",))
    with Installation(path) as installation, SQLiteSelfTestStore(installation) as store:
        service = SelfTestService(store, SelfTestParser())
        await service.submit(command)
        await service.process_pending()

        failed = await store.get_async("sim-1")
        assert failed.stage is Stage.FAILED
        assert failed.outcomes == ()
        assert await store.pending_async() == ()

    with closing(sqlite3.connect(path)) as connection, connection:
        row = connection.execute(
            "SELECT event_type, payload_json FROM audit_events "
            "WHERE command_id = 'sim-1' ORDER BY event_id DESC LIMIT 1"
        ).fetchone()
        job_status = connection.execute(
            "SELECT status FROM jobs WHERE command_id = 'sim-1'"
        ).fetchone()[0]
    assert row == (
        "ParseRejected",
        '{"command_id":"sim-1","reason":"unsupported_self_test"}',
    )
    assert job_status == "completed"


async def test_reopen_resumes_from_durable_parsed_evidence(tmp_path):
    path = tmp_path / "application.db"
    command = SubmitSelfTest("sim-1", "Bought AAPL 1/6 at 200", ("self-test-a",))
    parsed = ParsedSelfTest("AAPL", "buy", Fraction(1, 6), Decimal("200"))
    with Installation(path) as installation, SQLiteSelfTestStore(installation) as store:
        store.accept(command)
        store.advance("sim-1", Stage.CAPTURED, Stage.PARSED, (), parsed=parsed)

    with Installation(path) as installation, SQLiteSelfTestStore(installation) as store:
        service = SelfTestService(store, SelfTestParser())
        await service.process_pending()
        completed = await store.get_async("sim-1")

    assert completed.stage is Stage.COMPLETED
    assert tuple(outcome.account_id for outcome in completed.outcomes) == ("self-test-a",)
    with closing(sqlite3.connect(path)) as connection, connection:
        audit_rows = connection.execute(
            "SELECT event_type FROM audit_events WHERE command_id = 'sim-1' ORDER BY event_id"
        ).fetchall()
    assert audit_rows == [("SelfTestAccepted",), ("SelfTestParsed",), ("SelfTestCompleted",)]
