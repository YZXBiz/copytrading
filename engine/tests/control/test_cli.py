"""The CLI end to end: socket, app relay, pipe server, and control service."""

import asyncio
import datetime as dt
import io
import json
import os
import typing
from decimal import Decimal
from types import SimpleNamespace

import pytest

from copytrading_engine.control import cli, wire
from copytrading_engine.control.client import ControlClient
from copytrading_engine.execution.presentation.operator_views import AccountUnavailable

from .fakes import running_app, service


async def run(relay, *argv: str) -> tuple[int, str, str]:
    stdout, stderr = io.StringIO(), io.StringIO()
    code = await asyncio.to_thread(
        cli.main,
        list(argv),
        stdout=stdout,
        stderr=stderr,
        client_factory=lambda: ControlClient(relay.path, timeout=5),
    )
    return code, stdout.getvalue(), stderr.getvalue()


@pytest.fixture
async def app(tmp_path):
    control, engine, *_ = service()
    async with running_app(tmp_path / "application.db", control) as relay:
        yield relay, control, engine


async def test_status_prints_readable_text(app):
    relay, *_ = app
    code, out, _ = await run(relay, "status")
    assert code == cli.EXIT_OK
    assert "Engine      running" in out
    assert "paper" in out


async def test_json_prints_the_contract_response(app):
    relay, *_ = app
    code, out, _ = await run(relay, "accounts", "--json")
    assert code == cli.EXIT_OK
    response = wire.Response.model_validate_json(out)
    assert isinstance(response.ok, wire.AccountsPage)


async def test_accounts_list_each_lot_under_its_position(app):
    relay, *_ = app
    code, out, _ = await run(relay, "accounts")
    assert code == cli.EXIT_OK
    assert "  ABC  app 2, external 3" in out
    assert "    lot copy-0123456789abcdef0123456789abcdef01234567  2 of 2 at $25.10" in out
    assert "from alex  (discord:demo:1)" in out


async def test_an_earlier_versions_account_reads_as_kept_history(app, monkeypatch):
    relay, _, engine = app
    page = await engine.account_overviews(None, 50)
    kept = (AccountUnavailable(account_id="archive", reason="earlier_version"),)

    async def overviews(before_account_id, limit):
        return page.model_copy(update={"unavailable_accounts": kept})

    monkeypatch.setattr(engine, "account_overviews", overviews)
    code, out, _ = await run(relay, "accounts")
    assert code == cli.EXIT_OK
    assert "archive: history kept from an earlier version of CopyTrading" in out


async def test_activity_marks_source_text_untrusted(app):
    relay, *_ = app
    code, out, _ = await run(relay, "activity")
    assert code == cli.EXIT_OK
    assert "Source text (untrusted):\n  │ Bought ABC" in out
    assert "  Understood as: buy ABC at $12.34" in out


async def test_pause_works_while_locked(app):
    relay, *_ = app
    relay.unlocked = False
    code, out, _ = await run(relay, "accounts", "pause", "paper")
    assert code == cli.EXIT_OK
    assert "copying off" in out
    assert await run(relay, "status") == (
        cli.EXIT_LOCKED,
        "",
        "Unlock CopyTrading first.\n",
    )


async def test_resume_waits_for_the_owner(app):
    relay, _, engine = app
    code, out, _ = await run(relay, "accounts", "resume", "paper")
    assert code == cli.EXIT_APPROVAL_PENDING
    assert out.startswith("Waiting for approval in CopyTrading: start copying into paper.")
    assert engine.actions() == []


async def test_proposals_are_forbidden_at_read_and_pause_access(app):
    relay, *_ = app
    relay.access = "read_pause"
    code, _, err = await run(relay, "accounts", "recovery", "paper", "automatic")
    assert code == cli.EXIT_REFUSED
    assert "proposals are not enabled" in err


@pytest.mark.parametrize(("decision", "expected"), [("approve", 0), ("reject", 7)])
async def test_wait_reports_the_owners_decision(app, monkeypatch, decision, expected):
    relay, control, engine = app
    monkeypatch.setattr(cli, "WAIT_INTERVAL_SECONDS", 0.05)
    _, out, _ = await run(relay, "accounts", "resume", "paper", "--json")
    proposal = wire.Response.model_validate_json(out).ok
    assert isinstance(proposal, wire.ProposalView)

    waiting = asyncio.create_task(run(relay, "proposals", "wait", proposal.proposal_id))
    await asyncio.sleep(0.2)
    if decision == "approve":
        await control.approve(proposal.proposal_id, proposal.digest)
    else:
        await control.reject(proposal.proposal_id)
    code, _, _ = await waiting
    assert code == expected
    assert len(engine.actions()) == (1 if decision == "approve" else 0)


async def test_missing_app_exits_with_a_clear_message(tmp_path):
    code, _, err = await run(type("Relay", (), {"path": tmp_path / "none.sock"}), "status")
    assert code == cli.EXIT_APP_UNAVAILABLE
    assert "not running" in err


async def test_a_socket_in_a_shared_directory_is_refused(app):
    relay, *_ = app
    os.chmod(relay.path.parent, 0o755)
    try:
        code, _, err = await run(relay, "status")
    finally:
        os.chmod(relay.path.parent, 0o700)
    assert code == cli.EXIT_FAILURE
    assert "not the app's private socket" in err


def test_schema_command_prints_the_published_contract(capsys):
    assert cli.main(["schema"]) == cli.EXIT_OK
    assert json.loads(capsys.readouterr().out)["schema_version"] == wire.SCHEMA_VERSION


# The exit codes docs/agent-control.md publishes, so scripts can rely on them.
DOCUMENTED_ERROR_EXITS = {
    "access_off": 3,
    "locked": 4,
    "invalid_request": 2,
    "forbidden": 5,
    "busy": 5,
    "cooling_down": 5,
    "proposal_limit": 5,
    "conflict": 5,
    "not_found": 6,
    "unavailable": 6,
    "expired": 7,
    "rejected": 7,
}
DOCUMENTED_PROPOSAL_EXITS = {
    "pending": 10,
    "running": 10,
    "succeeded": 0,
    "failed": 6,
    "outcome_unknown": 6,
    "rejected": 7,
    "expired": 7,
    "discarded": 7,
}


def test_every_error_code_exits_as_documented():
    codes = typing.get_args(wire.ErrorCode.__value__)
    assert set(codes) == set(DOCUMENTED_ERROR_EXITS)
    assert {code: cli.error_exit_code(code) for code in codes} == DOCUMENTED_ERROR_EXITS


def test_every_proposal_state_exits_as_documented():
    states = typing.get_args(wire.ProposalView.model_fields["state"].annotation)
    assert set(states) == set(DOCUMENTED_PROPOSAL_EXITS)
    for state in states:
        proposal = SimpleNamespace(state=state)
        assert cli.proposal_exit_code(proposal) == DOCUMENTED_PROPOSAL_EXITS[state]  # ty: ignore[invalid-argument-type]


async def test_a_bad_argument_is_a_usage_error(app):
    relay, *_ = app
    code, _, _ = await run(relay, "accounts", "--limit", "not-a-number")
    assert code == cli.EXIT_USAGE


async def test_limits_are_proposed_in_plain_words_and_wait_for_the_owner(app):
    relay, _, engine = app
    code, out, _ = await run(
        relay, "accounts", "limits", "paper", "--max-order-usd", "300", "--overnight", "true"
    )
    assert code == cli.EXIT_APPROVAL_PENDING
    assert "change paper: max order usd = 300, overnight = true" in out
    assert engine.actions() == []


async def test_limits_need_a_setting_and_a_valid_value(app):
    relay, *_ = app
    code, _, err = await run(relay, "accounts", "limits", "paper")
    assert (code, "Name at least one setting" in err) == (cli.EXIT_USAGE, True)
    code, _, _ = await run(relay, "accounts", "limits", "paper", "--max-order-usd", "-5")
    assert code == cli.EXIT_USAGE


def test_activity_says_the_size_a_post_asked_for_and_why_a_call_placed_nothing():
    """From the live pass: "Bought $100 of $SOFI" read as "buy SOFI", a sixth as 16.666…%, and a
    refused call as "done"."""
    at = dt.datetime(2026, 10, 15, 20, 38, tzinfo=dt.UTC)

    def item(sequence, text, steps, outcomes):
        return wire.ActivityItem(
            sequence=sequence,
            source_id=f"discord:demo:{sequence}",
            source_at=at,
            captured_at=at,
            parse_status="complete",
            delivery_status="delivered",
            decision="trade",
            parser_reason=None,
            guru_id="guru-1",
            untrusted_source_text=text,
            understood_as=tuple(
                wire.InstructionItem(action=a, symbol=s, price=p, fraction=f, usd_amount=u)
                for a, s, p, f, u in steps
            ),
            destinations=(
                wire.DestinationView(
                    account_id="zhap",
                    environment="paper",
                    status="done",
                    instruction_outcomes=outcomes,
                    orders=(),
                ),
            ),
        )

    sixth, third = Decimal(1) / Decimal(6), Decimal(1) / Decimal(3)
    page = wire.ActivityPage(
        items=(
            item(
                1,
                "Bought $100 of $SOFI at 15.04",
                [("buy", "SOFI", Decimal("15.04"), None, Decimal("100"))],
                ("duplicate",),
            ),
            item(
                2,
                "buy 1/6 t at 23.46",
                [("buy", "T", Decimal("23.46"), sixth, None)],
                ("order_linked",),
            ),
            item(
                3,
                "Trimmed 1/3 $BAC 51.74, Sold all $VZ at 44.48",
                [
                    ("reduce", "BAC", Decimal("51.74"), third, None),
                    ("close", "VZ", Decimal("44.48"), Decimal(1), None),
                ],
                ("order_linked", "lot_unavailable"),
            ),
        ),
        rejected=(),
        next_before_seq=None,
        unavailable=(),
    )

    out = cli._render_activity(page)

    assert "  Understood as: buy $100.00 of SOFI at $15.04" in out
    assert "  → zhap: done (call 1: duplicate)" in out
    assert "  Understood as: buy 1/6 of T at $23.46" in out
    assert "  → zhap: done\n" in out
    assert "  Understood as: sell 1/3 of BAC at $51.74" in out
    assert "  Understood as: sell all VZ at $44.48" in out
    assert "(call 2: lot unavailable)" in out
