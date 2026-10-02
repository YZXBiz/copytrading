"""The four assistant operations match the shared fixtures and reach the service."""

import asyncio
import json

import pytest
from pydantic import ValidationError

from copytrading_engine.host.pipe.requests import REQUEST_ADAPTER

from ...contracts import contract


def test_the_ask_fixture_is_a_valid_request():
    request = REQUEST_ADAPTER.validate_python(contract("assistant-ask-request.json"))
    assert request.operation == "assistant_ask"
    assert (request.context.screen, request.context.language) == ("accounts", "en")
    assert request.context.guru_names() == {"guru-1a2b3c4d": "Zhao"}


def test_the_context_carries_the_app_language_and_nothing_else():
    ask = contract("assistant-ask-request.json")
    chinese = ask | {"context": ask["context"] | {"language": "zh-Hans"}}
    assert REQUEST_ADAPTER.validate_python(chinese).context.language == "zh-Hans"
    french = ask | {"context": ask["context"] | {"language": "fr"}}
    with pytest.raises(ValidationError):
        REQUEST_ADAPTER.validate_python(french)


def test_the_turn_fixture_is_a_valid_request():
    request = REQUEST_ADAPTER.validate_python(contract("assistant-turn-request.json"))
    assert (request.operation, request.after) == ("assistant_turn", 0)


def test_text_over_two_thousand_characters_is_refused():
    payload = contract("assistant-ask-request.json") | {"text": "x" * 2001}
    with pytest.raises(ValidationError):
        REQUEST_ADAPTER.validate_python(payload)


def _line(payload: dict) -> bytes:
    return json.dumps(payload).encode()


async def test_a_turn_is_served_in_the_fixture_shape(pipe_with_assistant):
    server, _ = pipe_with_assistant
    started = json.loads(await server.handle_line(_line(contract("assistant-ask-request.json"))))
    assert set(started["ok"]) == set(contract("assistant-ask-response.json")["ok"])
    turn_id = started["ok"]["turn_id"]
    poll = contract("assistant-turn-request.json") | {"turn_id": turn_id}
    reply = json.loads(await server.handle_line(_line(poll)))
    expected = contract("assistant-turn-response.json")["ok"]
    assert set(reply["ok"]) == set(expected)
    assert reply["ok"]["type"] == "assistant_turn"
    assert reply["ok"]["turn_id"] == turn_id
    for event in reply["ok"]["events"]:
        assert set(event) == set(expected["events"][0])


async def test_a_turn_can_be_cancelled_and_everything_reset(pipe_with_assistant):
    server, _ = pipe_with_assistant
    started = json.loads(await server.handle_line(_line(contract("assistant-ask-request.json"))))
    cancel = {"version": 1, "request_id": "c", "operation": "assistant_cancel"}
    cancelled = json.loads(
        await server.handle_line(_line(cancel | {"turn_id": started["ok"]["turn_id"]}))
    )
    assert set(cancelled["ok"]) == set(contract("assistant-cancel-response.json")["ok"])
    reset = json.loads(
        await server.handle_line(
            _line({"version": 1, "request_id": "r", "operation": "assistant_reset"})
        )
    )
    assert reset["ok"] == contract("assistant-reset-response.json")["ok"]


async def test_an_unknown_turn_is_not_found(pipe_with_assistant):
    server, _ = pipe_with_assistant
    poll = contract("assistant-turn-request.json") | {"turn_id": "t-000000000000"}
    reply = json.loads(await server.handle_line(_line(poll)))
    assert reply["error"]["code"] == "not_found"


async def test_without_a_control_service_the_assistant_is_unavailable(pipe_without_assistant):
    reply = json.loads(
        await pipe_without_assistant.handle_line(_line(contract("assistant-ask-request.json")))
    )
    assert reply["error"]["code"] == "unavailable"


class _Sink:
    def write(self, data: bytes) -> None:
        pass

    async def drain(self) -> None:
        pass


async def test_the_pipe_closing_ends_every_turn(pipe_with_assistant):
    server, _ = pipe_with_assistant
    started = json.loads(await server.handle_line(_line(contract("assistant-ask-request.json"))))
    reader = asyncio.StreamReader()
    reader.feed_eof()
    await server.serve(reader, _Sink())
    poll = contract("assistant-turn-request.json") | {"turn_id": started["ok"]["turn_id"]}
    reply = json.loads(await server.handle_line(_line(poll)))
    assert reply["error"]["code"] == "not_found"


@pytest.mark.parametrize("failure", [RuntimeError("boom"), ValueError("bad")])
@pytest.mark.parametrize(
    ("method", "request_payload"),
    [
        ("ask", lambda: contract("assistant-ask-request.json")),
        ("turn", lambda: contract("assistant-turn-request.json")),
        (
            "cancel",
            lambda: {
                "version": 1,
                "request_id": "c",
                "operation": "assistant_cancel",
                "turn_id": "t-0123456789ab",
            },
        ),
        ("reset", lambda: {"version": 1, "request_id": "r", "operation": "assistant_reset"}),
    ],
)
async def test_an_assistant_failure_is_unavailable_and_the_pipe_keeps_serving(
    pipe_with_assistant, monkeypatch, failure, method, request_payload
):
    server, svc = pipe_with_assistant

    def broken(*args, **kwargs):
        raise failure

    monkeypatch.setattr(svc, method, broken)
    reply = json.loads(await server.handle_line(_line(request_payload())))
    assert reply["error"]["code"] == "unavailable"
    status = {"version": 1, "request_id": "s", "operation": "get_status"}
    assert "ok" in json.loads(await server.handle_line(_line(status)))
