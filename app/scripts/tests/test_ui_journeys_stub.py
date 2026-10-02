from __future__ import annotations

import json
import sys
import urllib.request
from pathlib import Path
from typing import Any

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
import ui_journeys  # noqa: E402 - importable only after the scripts directory is on sys.path


def post(url: str, body: dict[str, Any]) -> tuple[str, bytes]:
    request = urllib.request.Request(
        f"{url}/chat/completions",
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(request, timeout=10) as response:
        return response.headers["Content-Type"], response.read()


def chunks(payload: bytes) -> list[dict[str, Any]]:
    lines = [line for line in payload.decode().split("\n\n") if line]
    assert lines[-1] == "data: [DONE]"
    assert all(line.startswith("data: ") for line in lines)
    return [json.loads(line.removeprefix("data: ")) for line in lines[:-1]]


def test_first_request_calls_the_status_tool_then_text_answers() -> None:
    with ui_journeys.ScriptedModelServer() as stub:
        kind, first = post(stub.base_url, {"model": "scripted", "messages": []})
        assert kind == "application/json"
        choice = json.loads(first)["choices"][0]
        assert choice["finish_reason"] == "tool_calls"
        call = choice["message"]["tool_calls"][0]
        assert call["function"] == {"name": "get_status", "arguments": "{}"}

        for _ in range(2):
            _, later = post(stub.base_url, {"model": "scripted", "messages": []})
            choice = json.loads(later)["choices"][0]
            assert choice["finish_reason"] == "stop"
            assert choice["message"]["content"] == ui_journeys.ASSISTANT_ANSWER
        assert len(stub.requests) == 3


def test_streamed_requests_get_server_sent_chunks() -> None:
    with ui_journeys.ScriptedModelServer() as stub:
        kind, first = post(stub.base_url, {"model": "scripted", "stream": True})
        assert kind == "text/event-stream"
        events = chunks(first)
        call = events[0]["choices"][0]["delta"]["tool_calls"][0]
        assert call["function"] == {"name": "get_status", "arguments": "{}"}
        assert events[-1]["choices"][0]["finish_reason"] == "tool_calls"

        _, later = post(stub.base_url, {"model": "scripted", "stream": True})
        events = chunks(later)
        text = "".join(e["choices"][0]["delta"].get("content") or "" for e in events)
        assert text == ui_journeys.ASSISTANT_ANSWER
        assert events[-1]["choices"][0]["finish_reason"] == "stop"
