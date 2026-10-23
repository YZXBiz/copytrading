"""`copytrading setup`: every part of the setup from the command line, keys only from stdin or
a file, through the engine's authorization to the app's own setup handler."""

import asyncio
import io
import json
import os

import pytest

from copytrading_engine.control import cli, cli_setup, wire
from copytrading_engine.control.client import ControlClient
from copytrading_engine.shared.route_keys import guru_for_channel

from ..contracts import contract
from .fake_setup_app import apply_facts
from .fakes import running_app, service

DISCORD_TOKEN = "discord-token-do-not-print"
ALPACA_KEY = "PKALPACAKEYDONOTPRINT"
ALPACA_SECRET = "alpaca-secret-do-not-print"


class Terminal(io.StringIO):
    def isatty(self) -> bool:
        return True


async def run(relay, *argv: str, stdin: str = "") -> tuple[int, str, str]:
    stdout, stderr = io.StringIO(), io.StringIO()
    code = await asyncio.to_thread(
        cli.main,
        list(argv),
        stdout=stdout,
        stderr=stderr,
        stdin=io.StringIO(stdin),
        client_factory=lambda: ControlClient(relay.path, timeout=5),
    )
    return code, stdout.getvalue(), stderr.getvalue()


@pytest.fixture
async def app(tmp_path):
    control, _, audit, _ = service()
    async with running_app(tmp_path / "application.db", control) as relay:
        yield relay, audit


async def test_show_names_keys_only_as_saved_or_missing(app):
    relay, _ = app
    code, out, _ = await run(relay, "setup", "show")
    assert code == cli.EXIT_OK
    assert "Discord     channels 111; authors any; token saved" in out
    assert "Account     paper-main (paper); keys saved; after a restart Wait for me" in out
    assert "max order usd 100" in out
    assert out.startswith("Setup       saved; Copying\n")
    code, out, _ = await run(relay, "setup", "show", "--json")
    assert isinstance(wire.Response.model_validate_json(out).ok, wire.SetupView)


async def test_a_token_from_stdin_reaches_the_app_and_is_never_printed(app):
    relay, audit = app
    code, out, err = await run(
        relay,
        "setup",
        "discord",
        "--channels",
        "111, 222",
        "--authors",
        "",
        "--secret-stdin",
        stdin=DISCORD_TOKEN + "\n",
    )
    assert code == cli.EXIT_OK, err
    assert relay.setup.received == [DISCORD_TOKEN]
    assert relay.setup.draft.channels == ["111", "222"]
    assert relay.setup.draft.authors == []
    assert DISCORD_TOKEN not in out + err
    assert "token entered, not saved yet" in out
    assert "Run `copytrading setup apply`" in out
    # The app answers `get_setup` before the token is read, then gets the edit.
    assert [entry.operation for entry in audit.entries] == ["get_setup", "edit_setup_discord"]
    assert DISCORD_TOKEN not in repr(audit.entries)


async def test_account_keys_come_from_a_file_one_per_line(app, tmp_path):
    relay, _ = app
    keys = tmp_path / "keys.txt"
    keys.write_text(f"{ALPACA_KEY}\n{ALPACA_SECRET}\n")
    code, out, err = await run(
        relay,
        "setup",
        "account",
        "add",
        "paper-2",
        "--from-file",
        str(keys),
        "--max-order-usd",
        "250",
        "--overnight",
        "true",
    )
    assert code == cli.EXIT_OK, err
    assert relay.setup.received == [ALPACA_KEY, ALPACA_SECRET]
    limits = relay.setup.draft.accounts["paper-2"]["limits"]
    assert (limits["max_order_usd"], limits["overnight"]) == ("250", "true")
    assert ALPACA_KEY not in out + err
    assert ALPACA_SECRET not in out + err


async def test_a_terminal_asks_for_keys_without_echo(monkeypatch):
    asked: list[str] = []

    def prompt(text: str) -> str:
        asked.append(text)
        return {"Alpaca API key ID: ": ALPACA_KEY, "Alpaca secret key: ": ALPACA_SECRET}[text]

    args = cli._parser().parse_args(["setup", "account", "edit", "paper-main", "--secret-stdin"])
    request = cli_setup.setup_request(args, "r1", Terminal(), prompt)
    assert isinstance(request, wire.EditSetupAccount)
    assert asked == ["Alpaca API key ID: ", "Alpaca secret key: "]
    assert request.key is not None
    assert request.key.get_secret_value() == ALPACA_KEY
    assert ALPACA_KEY not in repr(request)


@pytest.mark.parametrize(
    ("argv", "stdin", "message"),
    [
        (
            ["setup", "account", "edit", "paper-main", "--secret-stdin"],
            "only-one-line\n",
            "standard input must hold the Alpaca API key ID and Alpaca secret key, one per line",
        ),
        (["setup", "discord", "--secret-stdin"], "", "must hold the Discord token alone"),
        (["setup", "discord", "--from-file", "/no/such/file"], "", "/no/such/file does not exist"),
        (["setup", "account", "edit", "paper-main"], "", "Name at least one thing to change"),
        (["setup", "account", "add", "bad name"], "", "account_id"),
        (["setup", "discord", "--channels", "general"], "", "channel_ids"),
        (["setup", "model"], "", "Name at least one thing to change"),
    ],
)
async def test_bad_arguments_never_reach_the_app_and_never_echo_a_key(app, argv, stdin, message):
    relay, audit = app
    code, out, err = await run(relay, *argv, stdin=stdin)
    assert code == cli.EXIT_USAGE
    assert message in err
    assert "only-one-line" not in out + err
    assert relay.setup.received == []
    assert {entry.operation for entry in audit.entries} <= {"get_setup"}


async def test_keys_are_never_an_argument():
    with pytest.raises(SystemExit):
        cli._parser().parse_args(["setup", "discord", "--token", DISCORD_TOKEN])


async def test_apply_reports_each_check_and_saves(app):
    relay, _ = app
    await run(relay, "setup", "model", "--model", "deepseek-pro")
    code, out, _ = await run(relay, "setup", "apply")
    assert code == cli.EXIT_OK
    assert out.startswith("Applied: the setup is saved, and copying uses it.")
    assert "  ok      discord" in out
    assert "  ok      paper-main" in out
    assert relay.setup.applied == 1


async def test_a_failed_check_names_the_account_and_what_to_do(app):
    relay, _ = app
    relay.setup.fail_checks = True
    code, out, _ = await run(relay, "setup", "apply")
    assert code == cli.EXIT_NOT_COMPLETED
    assert "Not applied: some connections need attention. Nothing was saved." in out
    assert "  failed  paper-main: Alpaca didn't accept these keys." in out
    assert relay.setup.applied == 0


async def test_making_an_account_live_waits_for_the_owner(app):
    relay, audit = app
    await run(relay, "setup", "account", "edit", "paper-main", "--environment", "live")
    code, out, _ = await run(relay, "setup", "apply", "--json")
    assert code == cli.EXIT_APPROVAL_PENDING
    proposal = wire.Response.model_validate_json(out).ok
    assert isinstance(proposal, wire.ProposalView)
    assert proposal.subject == wire.ApplySetupSubject(
        made_live=("paper-main",),
        new_live_keys=(),
        changed_live=(),
        starts_live=("paper-main",),
    )
    assert relay.setup.applied == 0
    assert (audit.entries[-1].operation, audit.entries[-1].outcome) == ("apply_setup", "proposed")
    _, text, _ = await run(relay, "proposals", "show", proposal.proposal_id)
    assert "apply the setup (makes paper-main live; copies into live paper-main)" in text


async def test_keys_for_a_live_account_wait_for_the_owner(app):
    relay, _ = app
    relay.setup.saved.accounts["paper-main"]["environment"] = "live"
    relay.setup.draft.accounts["paper-main"]["environment"] = "live"
    await run(
        relay,
        "setup",
        "account",
        "edit",
        "paper-main",
        "--secret-stdin",
        stdin=f"{ALPACA_KEY}\n{ALPACA_SECRET}\n",
    )
    code, out, _ = await run(relay, "setup", "apply")
    assert code == cli.EXIT_APPROVAL_PENDING
    assert "saves new keys for paper-main" in out
    assert ALPACA_SECRET not in out


async def test_setup_changes_need_the_propose_level(app):
    relay, _ = app
    relay.access = "read_pause"
    code, _, err = await run(relay, "setup", "show")
    assert code == cli.EXIT_OK
    code, _, err = await run(relay, "setup", "discard")
    assert code == cli.EXIT_REFUSED
    assert "Read, pause, and ask for approval" in err


async def test_a_locked_app_refuses_setup(app):
    relay, _ = app
    relay.unlocked = False
    code, _, err = await run(relay, "setup", "show")
    assert (code, err) == (cli.EXIT_LOCKED, "Unlock CopyTrading first.\n")


async def test_import_sends_the_file_and_lists_names_only(app, tmp_path):
    relay, _ = app
    setup = tmp_path / "setup.txt"
    setup.write_text(f"Discord token:\n{DISCORD_TOKEN}\n")
    code, out, err = await run(relay, "setup", "import", str(setup))
    assert code == cli.EXIT_OK, err
    assert out.startswith("Filled from the file: Discord token\nStill needed: A guru\n")
    assert relay.setup.received == [f"Discord token:\n{DISCORD_TOKEN}\n"]
    assert DISCORD_TOKEN not in out + err


async def test_after_a_restart_is_set_in_the_account_sheets_words(app):
    relay, _ = app
    code, out, err = await run(
        relay, "setup", "account", "edit", "paper-main", "--after-restart", "carry-on"
    )
    assert code == cli.EXIT_OK, err
    assert "Account     paper-main (paper); keys saved; after a restart Carry on by itself" in out
    assert relay.setup.draft.accounts["paper-main"]["recovery_preference"] == "automatic"
    code, out, _ = await run(relay, "setup", "show", "--json")
    view = wire.Response.model_validate_json(out).ok
    assert isinstance(view, wire.SetupView)
    assert view.accounts[0].recovery_preference == "automatic"
    code, _, _ = await run(relay, "setup", "account", "edit", "paper-main", "--after-restart", "x")
    assert code == cli.EXIT_USAGE


async def test_a_large_file_is_refused_before_sending(app, tmp_path):
    relay, _ = app
    big = tmp_path / "big.txt"
    big.write_text("x" * (cli_setup.MAX_SECRET_FILE_BYTES + 1))
    code, _, err = await run(relay, "setup", "import", str(big))
    assert code == cli.EXIT_USAGE
    assert "larger than a setup file can be" in err


async def test_guru_and_alerts_and_discard(app):
    relay, _ = app
    code, out, _ = await run(
        relay, "setup", "guru", "add", "Alex", "--channel", "111", "--account", "paper-main"
    )
    assert code == cli.EXIT_OK
    # The guru's ID is the one their channel gives them, the engine's own.
    alex = guru_for_channel("discord", "111")
    assert f"Guru        Alex ({alex}); channel 111, author any, account paper-main" in out
    code, out, _ = await run(relay, "setup", "alerts", "--on")
    assert "Alerts      telegram; token missing" in out
    code, out, _ = await run(relay, "setup", "guru", "remove", "Alex")
    assert "Guru        none" in out
    code, out, _ = await run(relay, "setup", "discard")
    assert code == cli.EXIT_OK
    assert "Alerts      off" in out


def test_secrets_serialize_only_on_the_wire():
    request = wire.EditSetupDiscord(request_id="r", token=DISCORD_TOKEN)  # ty: ignore[invalid-argument-type]
    assert DISCORD_TOKEN not in repr(request)
    assert DISCORD_TOKEN not in str(request.model_dump())
    assert json.loads(wire.REQUEST.dump_json(request))["token"] == DISCORD_TOKEN
    with pytest.raises(ValueError, match="together") as error:
        wire.EditSetupAccount(request_id="r", action="edit", account_id="a", key=ALPACA_KEY)  # ty: ignore[invalid-argument-type]
    assert ALPACA_KEY not in str(error.value)


@pytest.mark.parametrize(
    "case", contract("agent-setup-apply-facts.json")["cases"], ids=lambda case: case["name"]
)
def test_the_stand_in_app_finds_the_same_live_facts_as_the_app(case):
    """The Swift `agent setup from the command line` check runs the app on these cases too."""
    facts = apply_facts(
        case["saved"], case["draft"], copying=case["copying"], start=case.get("start", False)
    )
    assert facts == case["facts"]


def test_model_services_match_the_engines():
    from typing import get_args

    from copytrading_engine.shared.model_providers import MODEL_PROVIDERS

    assert get_args(wire.ModelService.__value__) == MODEL_PROVIDERS


class Recorder(io.StringIO):
    """Standard input that remembers whether anything read it."""

    def __init__(self, text: str) -> None:
        super().__init__(text)
        self.reads = 0

    def read(self, size: int | None = -1) -> str:
        self.reads += 1
        return super().read(size)


async def test_keys_are_never_read_when_a_server_answers(app, monkeypatch):
    relay, _ = app
    server_refusal = wire.Response(
        request_id="",
        error=wire.ErrorBody(code="unavailable", message="This CopyTrading has no app."),
    ).model_dump_json()

    async def as_a_server(line, context):
        return server_refusal

    monkeypatch.setattr(relay.setup, "handle", as_a_server)
    stdin = Recorder(DISCORD_TOKEN + "\n")
    stdout, stderr = io.StringIO(), io.StringIO()
    code = await asyncio.to_thread(
        cli.main,
        ["setup", "discord", "--secret-stdin"],
        stdout=stdout,
        stderr=stderr,
        stdin=stdin,
        client_factory=lambda: ControlClient(relay.path, timeout=5),
    )
    assert code == cli.EXIT_NOT_COMPLETED
    assert stdin.reads == 0
    assert "no app" in stderr.getvalue()


def test_setup_refuses_a_servers_socket_before_reading_keys(monkeypatch):
    monkeypatch.setattr(cli, "is_server_socket", lambda: True)
    stdin = Recorder(DISCORD_TOKEN + "\n")
    stderr = io.StringIO()
    code = cli.main(
        ["setup", "discord", "--secret-stdin"], stdout=io.StringIO(), stderr=stderr, stdin=stdin
    )
    assert code == cli.EXIT_APP_UNAVAILABLE
    assert stdin.reads == 0
    assert "only the app may receive keys" in stderr.getvalue()


def test_a_server_socket_is_told_apart_from_the_apps(tmp_path, monkeypatch):
    from copytrading_engine.control import client

    monkeypatch.setenv("HOME", str(tmp_path))
    monkeypatch.delenv("COPYTRADING_STATE_ROOT", raising=False)
    server = client.server_state_root(platform="darwin") / "control"
    server.mkdir(parents=True)
    (server / "cli.sock").touch()
    assert client.is_server_socket(platform="darwin")
    app_socket = client.app_state_root() / "control"
    app_socket.mkdir(parents=True)
    (app_socket / "cli.sock").touch()
    assert not client.is_server_socket(platform="darwin")
    monkeypatch.setenv("COPYTRADING_STATE_ROOT", str(tmp_path / "chosen"))
    assert not client.is_server_socket(platform="darwin")


@pytest.mark.parametrize("kind", ["fifo", "device"])
async def test_a_key_file_that_is_not_a_regular_file_is_refused(app, tmp_path, kind):
    relay, _ = app
    if kind == "fifo":
        path = tmp_path / "keys"
        os.mkfifo(path)
    else:
        path = "/dev/zero"
    code, _, err = await asyncio.wait_for(
        run(relay, "setup", "discord", "--from-file", str(path)), timeout=10
    )
    assert code == cli.EXIT_USAGE
    assert "is not a regular file" in err
    assert relay.setup.received == []


async def test_a_request_over_the_limit_is_refused_before_sending(app, tmp_path):
    relay, _ = app
    setup = tmp_path / "setup.txt"
    # Under the file limit, but every quote doubles once the request is JSON.
    setup.write_text("Discord token:\n" + '"' * 40_000 + "\n")
    code, _, err = await run(relay, "setup", "import", str(setup))
    assert code == cli.EXIT_USAGE
    assert "The request is too large" in err
    assert relay.setup.received == []


def test_the_assistant_names_a_live_account_whose_limits_change():
    from copytrading_engine.assistant.results import proposal

    response = contract("agent-proposal-response.json")["ok"]["proposal"]
    response["subject"] = {
        "kind": "apply_setup",
        "made_live": [],
        "new_live_keys": [],
        "changed_live": ["live-main"],
        "starts_live": [],
    }
    view = wire.ProposalView.model_validate_json(json.dumps(response))
    assert "live-main" in proposal(view)["asks_to"]


async def test_start_on_a_paused_paper_setup_starts_copying(app):
    relay, _ = app
    relay.setup.copying = False
    code, out, _ = await run(relay, "setup", "apply", "--start")
    assert code == cli.EXIT_OK
    assert out.startswith("Applied")
    assert relay.setup.started == 1


async def test_start_with_a_live_account_waits_for_the_owner(app):
    relay, _ = app
    relay.setup.copying = False
    relay.setup.saved.accounts["paper-main"]["environment"] = "live"
    relay.setup.draft.accounts["paper-main"]["environment"] = "live"
    paused, out, _ = await run(relay, "setup", "apply")
    assert paused == cli.EXIT_OK, out
    code, out, _ = await run(relay, "setup", "apply", "--start")
    assert code == cli.EXIT_APPROVAL_PENDING
    assert "copies into live paper-main" in out
    assert relay.setup.started == 0


async def test_setup_changes_need_the_owners_separate_permission(app):
    relay, audit = app
    relay.setup_changes = False
    code, out, _ = await run(relay, "setup", "show")
    assert code == cli.EXIT_OK, out
    code, _, err = await run(relay, "setup", "model", "--model", "other")
    assert code == cli.EXIT_REFUSED
    assert "Allow setup changes from the command line" in err
    assert "Settings → Agent Access" in err
    code, _, err = await run(relay, "setup", "apply")
    assert code == cli.EXIT_REFUSED
    assert relay.setup.draft.model == "deepseek-flash"
    refused = [entry for entry in audit.entries if entry.outcome == "forbidden"]
    assert [entry.operation for entry in refused] == ["edit_setup_model", "apply_setup"]
    assert all(entry.caller_path == "/usr/bin/agent" and entry.caller_pid for entry in refused)


async def test_every_setup_request_records_its_caller(app):
    relay, audit = app
    await run(relay, "setup", "show")
    await run(relay, "setup", "alerts", "--on")
    await run(relay, "setup", "apply")
    setup = [entry for entry in audit.entries if entry.operation in wire.SETUP_OPERATIONS]
    assert [entry.operation for entry in setup] == ["get_setup", "edit_setup_alerts", "apply_setup"]
    assert all(entry.caller_pid and entry.caller_path == "/usr/bin/agent" for entry in setup)


async def answering(reply):
    """A socket that answers every request with `reply(line)`."""
    from .fakes import app_socket

    async def forward(line, context):
        return await reply(line)

    return app_socket(forward)


async def test_an_answer_from_a_newer_app_says_to_use_the_bundled_cli():
    async def newer(line):
        request_id = json.loads(line)["request_id"]
        return json.dumps(
            {"schema_version": 1, "request_id": request_id, "ok": {"type": "setup_from_the_future"}}
        )

    async with await answering(newer) as relay:
        code, _, err = await run(relay, "setup", "show")
    assert code == cli.EXIT_FAILURE
    assert "this copytrading CLI is older than the app; use the one inside CopyTrading.app" in err


async def test_garbage_is_still_reported_as_outside_the_contract():
    async def garbage(line):
        return "not json"

    async with await answering(garbage) as relay:
        code, _, err = await run(relay, "status")
    assert code == cli.EXIT_FAILURE
    assert "outside the control contract" in err


async def test_an_apply_with_no_answer_says_the_outcome_is_unknown_and_retrying_is_safe():
    async def silent(line):
        await asyncio.sleep(5)
        return ""

    async with await answering(silent) as relay:
        stdout, stderr = io.StringIO(), io.StringIO()
        code = await asyncio.to_thread(
            cli.main,
            ["setup", "apply"],
            stdout=stdout,
            stderr=stderr,
            stdin=io.StringIO(),
            client_factory=lambda: ControlClient(relay.path, timeout=0.3),
        )
    assert code == cli.EXIT_NOT_COMPLETED
    message = stderr.getvalue()
    assert "whether the setup was applied is not known" in message
    assert "`copytrading setup show`" in message
    assert "again is safe" in message
