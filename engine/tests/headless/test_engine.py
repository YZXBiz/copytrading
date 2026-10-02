"""The server starts copying through the same requests the app sends, in the same order."""

import json
from importlib import resources

import pytest

from copytrading_engine.headless.config import load_secrets, load_setup
from copytrading_engine.headless.engine import EngineRefused, HeadlessEngine, SetupNotReady

from .test_config import KEYS

READY = {"activatable": True, "checks": [{"name": "broker", "state": "ready"}]}


class ScriptedServer:
    """Answers each operation from a script and records what was asked."""

    def __init__(self, answers: dict[str, list[dict]]) -> None:
        self.answers = answers
        self.asked: list[dict] = []

    async def handle_line(self, raw: bytes) -> bytes:
        request = json.loads(raw)
        self.asked.append(request)
        answer = self.answers[request["operation"]].pop(0)
        envelope = {"version": 1, "request_id": request["request_id"]} | answer
        return json.dumps(envelope).encode() + b"\n"


@pytest.fixture
def setup(tmp_path):
    path = tmp_path / "copytrading.toml"
    template = resources.files("copytrading_engine.headless").joinpath("template.toml")
    path.write_text(template.read_text(encoding="utf-8"))
    loaded = load_setup(path)
    return loaded, load_secrets(loaded.configuration, KEYS)


def engine_for(server, setup) -> HeadlessEngine:
    async def no_wait(_seconds: float) -> None:
        return None

    loaded, secrets = setup
    return HeadlessEngine(server, loaded, secrets, sleep=no_wait)  # ty: ignore[invalid-argument-type]


def activation(phase: str, error: str | None = None) -> dict:
    return {"ok": {"activation": {"phase": phase, "error_code": error}}}


async def test_start_checks_then_starts_with_the_token_and_waits_until_ready(setup):
    server = ScriptedServer(
        {
            "validate_trading": [{"ok": {"report": READY, "activation_token": "tok"}}],
            "start_trading": [{"ok": {"trading": {}}}],
            "get_trading_activation": [activation("starting"), activation("ready")],
        }
    )

    await engine_for(server, setup).start()

    operations = [request["operation"] for request in server.asked]
    assert operations == [
        "validate_trading",
        "start_trading",
        "get_trading_activation",
        "get_trading_activation",
    ]
    start = server.asked[1]
    assert start["validation_token"] == "tok"
    assert start["secrets"]["brokers"][0]["secret"] == "secret"
    assert start["configuration"] == server.asked[0]["configuration"]
    assert server.asked[2]["activation_id"] == start["activation_id"]


async def test_a_failed_check_never_starts(setup):
    report = {
        "activatable": False,
        "checks": [{"name": "broker", "state": "failed", "reason_code": "unauthorized"}],
    }
    server = ScriptedServer(
        {"validate_trading": [{"ok": {"report": report, "activation_token": None}}]}
    )

    with pytest.raises(SetupNotReady) as not_ready:
        await engine_for(server, setup).start()

    assert not not_ready.value.report.activatable
    assert not_ready.value.report.checks[0].reason_code == "unauthorized"
    assert [request["operation"] for request in server.asked] == ["validate_trading"]


async def test_an_activation_that_fails_is_reported_with_its_reason(setup):
    server = ScriptedServer(
        {
            "validate_trading": [{"ok": {"report": READY, "activation_token": "tok"}}],
            "start_trading": [{"ok": {"trading": {}}}],
            "get_trading_activation": [activation("failed", "broker_unavailable")],
        }
    )

    with pytest.raises(EngineRefused, match="broker_unavailable"):
        await engine_for(server, setup).start()


async def test_agent_lines_carry_the_owners_access_and_the_caller(setup):
    server = ScriptedServer({"control": [{"ok": {"type": "control", "line": "{}"}}]})

    answer = await engine_for(server, setup).relay_agent_line('{"op":"status"}', 4242)

    assert answer == "{}"
    context = server.asked[0]["context"]
    assert context == {
        "access_level": "read_pause",
        "unlocked": True,
        "caller_pid": 4242,
        "caller_path": None,
    }


async def test_agents_get_nothing_when_access_is_off(setup):
    loaded, secrets = setup
    closed = loaded.model_copy(update={"agent_access": "off"})
    server = ScriptedServer({})

    with pytest.raises(EngineRefused, match="access_off"):
        await engine_for(server, (closed, secrets)).relay_agent_line("{}", None)
    assert server.asked == []


async def test_entries_are_switched_with_a_fresh_command(setup):
    server = ScriptedServer(
        {
            "control_account": [
                {"ok": {"control": {"entry_permission": "enabled"}}},
                {"ok": {"control": {"entry_permission": "disabled"}}},
            ]
        }
    )
    engine = engine_for(server, setup)

    enabled = await engine.set_entries("paper-main", enabled=True)
    disabled = await engine.set_entries("paper-main", enabled=False)

    assert (enabled.entry_permission, disabled.entry_permission) == ("enabled", "disabled")
    first, second = (request["command"] for request in server.asked)
    assert (first["action"], second["action"]) == ("resume", "pause")
    assert first["command_id"] != second["command_id"]
