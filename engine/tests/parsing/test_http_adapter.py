"""Provider adapters use schema output, obey deadlines, and capture wire payloads redacted."""

import asyncio
import json

import httpx2 as httpx
import pytest
from anthropic import AsyncAnthropic
from openai import AsyncOpenAI

from copytrading_engine.parsing.extraction import DecodeError
from copytrading_engine.parsing.providers.anthropic import build_decoder as build_anthropic_decoder
from copytrading_engine.parsing.providers.deepseek import build_decoder as build_deepseek_decoder
from copytrading_engine.parsing.providers.transport import DiagnosticHTTPTransport
from copytrading_engine.parsing.routes import Route
from copytrading_engine.shared.correlation import WorkflowAttempt, bind_workflow_attempt
from copytrading_engine.shared.model_providers import ProviderConfig

from ..diagnostics.telemetry.builders import journal_events, journal_sink


async def test_anthropic_reads_with_the_schema_in_its_instructions_and_no_tools():
    requests = []
    payload = {"reading": {"kind": "commentary", "summary": "Commentary"}}

    def handler(request):
        requests.append(json.loads(request.content))
        return httpx.Response(
            200,
            json={
                "id": "msg_test",
                "type": "message",
                "role": "assistant",
                "model": "claude-haiku-4-5-20251001",
                "content": [{"type": "text", "text": json.dumps(payload)}],
                "stop_reason": "end_turn",
                "stop_sequence": None,
                "usage": {"input_tokens": 10, "output_tokens": 10},
            },
        )

    client = AsyncAnthropic(
        api_key="test-only",
        max_retries=0,
        http_client=httpx.AsyncClient(transport=httpx.MockTransport(handler)),
    )
    decoder = build_anthropic_decoder(
        ProviderConfig(api_key="test-only", model="claude-haiku-4-5-20251001", timeout=20),
        client,
    )
    try:
        result = await decoder.decode("Market commentary", Route(playbook="苹果 means AAPL"))
        assert result.kind == "commentary"
        assert len(requests) == 1
        # Anthropic compiles a strict output schema into a grammar too large for the reading, so
        # the schema rides in the instructions and the answer is validated like any other.
        assert "output_config" not in requests[0]
        assert not requests[0].get("tools")
        assert "schema" in json.dumps(requests[0]["system"]).lower()
        assert "account" not in requests[0]["messages"][0]["content"][0].get("text", "").lower()
        # The playbook is trusted guidance: it rides in the system prompt, never in the post.
        assert "苹果 means AAPL" in json.dumps(requests[0]["system"], ensure_ascii=False)
        assert "苹果" not in json.dumps(requests[0]["messages"], ensure_ascii=False)
    finally:
        await decoder.close()


async def test_deepseek_stalled_response_obeys_total_deadline_without_sdk_retries():
    from openai import AsyncOpenAI

    requests = []
    stalled_request_started = asyncio.Event()

    async def handler(request):
        requests.append(request)
        if len(requests) == 1:
            return httpx.Response(
                200,
                json={
                    "id": "warmup",
                    "object": "chat.completion",
                    "created": 1,
                    "model": "deepseek-flash",
                    "choices": [
                        {
                            "index": 0,
                            "finish_reason": "stop",
                            "message": {
                                "role": "assistant",
                                "content": json.dumps(
                                    {"reading": {"kind": "commentary", "summary": "Commentary"}}
                                ),
                            },
                        }
                    ],
                    "usage": {"prompt_tokens": 10, "completion_tokens": 10, "total_tokens": 20},
                },
            )
        stalled_request_started.set()
        await asyncio.sleep(60)
        return httpx.Response(200, json={})

    client = AsyncOpenAI(
        api_key="test-only",
        base_url="https://api.deepseek.com",
        max_retries=0,
        http_client=httpx.AsyncClient(transport=httpx.MockTransport(handler)),
    )
    decoder = build_deepseek_decoder(
        ProviderConfig(api_key="test-only", model="deepseek-flash", timeout=20), client
    )
    try:
        assert (await decoder.decode("Warm up the SDK", Route())).kind == "commentary"
        decoder.timeout = 2
        started_at = asyncio.get_running_loop().time()
        with pytest.raises(DecodeError) as failure:
            await decoder.decode("Market commentary", Route())
        elapsed = asyncio.get_running_loop().time() - started_at
        assert failure.value.reason == "provider_timeout"
        assert failure.value.retryable
        assert stalled_request_started.is_set()
        assert len(requests) == 2  # one warmup request, one stalled request, no SDK retry
        assert elapsed < 5  # the decoder deadline, not the 60-second transport stall
    finally:
        await decoder.close()


async def test_deepseek_uses_json_mode_without_executable_tools():
    requests = []

    def handler(request):
        requests.append(json.loads(request.content))
        return httpx.Response(
            200,
            json={
                "id": "chat-test",
                "object": "chat.completion",
                "created": 1,
                "model": "deepseek-flash",
                "choices": [
                    {
                        "index": 0,
                        "finish_reason": "stop",
                        "message": {
                            "role": "assistant",
                            "content": json.dumps(
                                {"reading": {"kind": "commentary", "summary": "Commentary"}}
                            ),
                        },
                    }
                ],
                "usage": {"prompt_tokens": 10, "completion_tokens": 10, "total_tokens": 20},
            },
        )

    client = AsyncOpenAI(
        api_key="test-only",
        base_url="https://api.deepseek.com",
        max_retries=0,
        http_client=httpx.AsyncClient(transport=httpx.MockTransport(handler)),
    )
    decoder = build_deepseek_decoder(
        ProviderConfig(api_key="test-only", model="deepseek-flash", timeout=20), client
    )
    try:
        result = await decoder.decode("Market commentary", Route())
        assert result.kind == "commentary"
        assert len(requests) == 1
        assert requests[0]["response_format"] == {"type": "json_object"}
        assert requests[0]["thinking"] == {"type": "disabled"}
        assert not requests[0].get("tools")
    finally:
        await decoder.close()


async def test_provider_transport_captures_actual_serialized_wire_payloads_redacted(tmp_path):
    secret = "wire-secret-0123456789"
    requests = []

    def handler(request):
        requests.append(request)
        return httpx.Response(
            200,
            json={
                "id": "chat-wire",
                "object": "chat.completion",
                "created": 1,
                "model": "deepseek-flash",
                "choices": [
                    {
                        "index": 0,
                        "finish_reason": "stop",
                        "message": {
                            "role": "assistant",
                            "content": json.dumps(
                                {"reading": {"kind": "commentary", "summary": secret}}
                            ),
                        },
                    }
                ],
                "usage": {"prompt_tokens": 10, "completion_tokens": 10, "total_tokens": 20},
            },
        )

    sink = journal_sink(
        tmp_path / "diagnostics", secrets=(secret, "provider-header-must-not-be-captured")
    )
    transport = DiagnosticHTTPTransport(httpx.MockTransport(handler), sink, provider="deepseek")
    client = AsyncOpenAI(
        api_key="provider-header-must-not-be-captured",
        base_url="https://api.deepseek.com",
        max_retries=0,
        http_client=httpx.AsyncClient(transport=transport),
    )
    decoder = build_deepseek_decoder(
        ProviderConfig(
            api_key="provider-header-must-not-be-captured",
            model="deepseek-flash",
            timeout=20,
        ),
        client,
    )
    context = WorkflowAttempt(
        workflow_id="4f0f5f8d9b0f4c2e8b3a7c6d5e4f3210",
        trace_id="4f0f5f8d9b0f4c2e8b3a7c6d5e4f3210",
        destination_id=None,
        attempt=2,
    )
    try:
        with bind_workflow_attempt(context):
            result = await decoder.decode("Market " + secret, Route())
        assert result.kind == "commentary"
        assert len(requests) == 1
        assert sink.flush(timeout_seconds=5)
        assert [record.capture_kind for record in journal_events(tmp_path / "diagnostics")] == [
            "model_request",
            "model_response",
        ]
        request_record, response_record = journal_events(tmp_path / "diagnostics")
        assert request_record.capture_status == response_record.capture_status == "complete"
        assert request_record.trace_id == context.trace_id
        assert request_record.attempt == 2
        assert secret not in json.dumps(request_record.payload)
        assert secret not in json.dumps(response_record.payload)
        assert "provider-header-must-not-be-captured" not in json.dumps(
            [record.payload for record in journal_events(tmp_path / "diagnostics")]
        )
        assert request_record.payload["path"].endswith("/chat/completions")
        assert "response_format" in request_record.payload["body"]
    finally:
        await decoder.close()
        sink.close(timeout_seconds=5)


async def test_anthropic_provider_transport_captures_sdk_wire_request_and_response(tmp_path):
    secret = "anthropic-wire-secret-123456"
    request_bodies = []

    def handler(request):
        request_bodies.append(json.loads(request.content))
        return httpx.Response(
            200,
            json={
                "id": "msg-wire",
                "type": "message",
                "role": "assistant",
                "model": "claude-haiku-4-5-20251001",
                "content": [
                    {
                        "type": "text",
                        "text": json.dumps({"reading": {"kind": "commentary", "summary": secret}}),
                    }
                ],
                "stop_reason": "end_turn",
                "stop_sequence": None,
                "usage": {"input_tokens": 10, "output_tokens": 10},
            },
        )

    sink = journal_sink(
        tmp_path / "diagnostics", secrets=(secret, "anthropic-header-must-not-be-captured")
    )
    client = AsyncAnthropic(
        api_key="anthropic-header-must-not-be-captured",
        max_retries=0,
        http_client=httpx.AsyncClient(
            transport=DiagnosticHTTPTransport(
                httpx.MockTransport(handler), sink, provider="anthropic"
            )
        ),
    )
    decoder = build_anthropic_decoder(
        ProviderConfig(
            api_key="anthropic-header-must-not-be-captured",
            model="claude-haiku-4-5-20251001",
            timeout=20,
        ),
        client,
    )
    try:
        with bind_workflow_attempt(
            WorkflowAttempt(
                workflow_id="6f0f5f8d9b0f4c2e8b3a7c6d5e4f3211",
                trace_id="6f0f5f8d9b0f4c2e8b3a7c6d5e4f3211",
                destination_id=None,
                attempt=1,
            )
        ):
            result = await decoder.decode("Commentary " + secret, Route())
        assert result.kind == "commentary"
        assert len(request_bodies) == 1
        assert "output_config" not in request_bodies[0]
        assert sink.flush(timeout_seconds=5)
        assert [event.capture_kind for event in journal_events(tmp_path / "diagnostics")] == [
            "model_request",
            "model_response",
        ]
        request_event, response_event = journal_events(tmp_path / "diagnostics")
        assert request_event.provider == response_event.provider == "anthropic"
        assert request_event.capture_status == response_event.capture_status == "complete"
        assert "anthropic-header-must-not-be-captured" not in json.dumps(
            [event.payload for event in journal_events(tmp_path / "diagnostics")]
        )
        assert secret not in json.dumps(
            [event.payload for event in journal_events(tmp_path / "diagnostics")]
        )
    finally:
        await decoder.close()
        sink.close(timeout_seconds=5)


@pytest.mark.parametrize(
    ("status", "body", "reason"),
    [
        # DeepSeek's answer to a model name it does not have, as its API sent it on 2026-10-04.
        (
            400,
            {
                "error": {
                    "message": "The supported API model names are deepseek-flash, deepseek-v4-pro,"
                    " but you passed dpeeseek-flash.",
                    "type": "invalid_request_error",
                    "param": None,
                    "code": "invalid_request_error",
                }
            },
            "provider_model_not_found",
        ),
        (
            401,
            {"error": {"message": "Authentication Fails", "type": "authentication_error"}},
            "provider_key_rejected",
        ),
    ],
)
async def test_deepseek_answers_name_a_missing_model_or_a_rejected_key(status, body, reason):
    """The real OpenAI client and PydanticAI carry the provider's answer to the classification."""

    def handler(request):
        return httpx.Response(status, json=body)

    client = AsyncOpenAI(
        api_key="test-only",
        base_url="https://api.deepseek.com",
        max_retries=0,
        http_client=httpx.AsyncClient(transport=httpx.MockTransport(handler)),
    )
    decoder = build_deepseek_decoder(
        ProviderConfig(api_key="test-only", model="dpeeseek-flash", timeout=20), client
    )
    try:
        with pytest.raises(DecodeError) as failure:
            await decoder.decode("Commentary", Route())
        assert failure.value.reason == reason
    finally:
        await decoder.close()


async def test_provider_http_error_body_is_captured_without_masking_safe_decode_error(tmp_path):
    secret = "provider-error-secret-9f6b"

    def handler(request):
        return httpx.Response(401, json={"error": {"message": secret}})

    sink = journal_sink(tmp_path / "diagnostics", secrets=(secret,))
    client = AsyncOpenAI(
        api_key="test-only",
        base_url="https://api.deepseek.com",
        max_retries=0,
        http_client=httpx.AsyncClient(
            transport=DiagnosticHTTPTransport(
                httpx.MockTransport(handler), sink, provider="deepseek"
            )
        ),
    )
    decoder = build_deepseek_decoder(
        ProviderConfig(api_key="test-only", model="deepseek-flash", timeout=20), client
    )
    try:
        with pytest.raises(DecodeError) as failure:
            await decoder.decode("Commentary", Route())
        assert failure.value.reason == "provider_key_rejected"
        assert "provider-error-secret-9f6b" not in str(failure.value)
        assert sink.flush(timeout_seconds=5)
        assert [event.capture_status for event in journal_events(tmp_path / "diagnostics")] == [
            "complete",
            "complete",
        ]
        response_event = journal_events(tmp_path / "diagnostics")[1]
        assert response_event.payload["status_code"] == 401
        assert "provider-error-secret-9f6b" not in json.dumps(response_event.payload)
    finally:
        await decoder.close()
        sink.close(timeout_seconds=5)


async def test_provider_cancellation_marks_partial_response_and_closes_stream(tmp_path):
    class StalledStream(httpx.AsyncByteStream):
        def __init__(self):
            self.closed = False

        async def __aiter__(self):
            yield b'{"id":"partial",'
            await asyncio.Event().wait()

        async def aclose(self):
            self.closed = True

    stream = StalledStream()
    sink = journal_sink(tmp_path / "diagnostics")
    client = AsyncOpenAI(
        api_key="test-only",
        base_url="https://api.deepseek.com",
        max_retries=0,
        http_client=httpx.AsyncClient(
            transport=DiagnosticHTTPTransport(
                httpx.MockTransport(lambda request: httpx.Response(200, stream=stream)),
                sink,
                provider="deepseek",
            )
        ),
    )
    decoder = build_deepseek_decoder(
        ProviderConfig(api_key="test-only", model="deepseek-flash", timeout=20), client
    )
    decoder.timeout = 0.05
    try:
        with pytest.raises(DecodeError) as failure:
            await decoder.decode("Commentary", Route())
        assert failure.value.reason == "provider_timeout"
        assert stream.closed
        assert sink.flush(timeout_seconds=5)
        response_event = [
            event
            for event in journal_events(tmp_path / "diagnostics")
            if event.capture_kind == "model_response"
        ]
        assert len(response_event) == 1
        assert response_event[0].capture_status == "incomplete"
        assert response_event[0].payload is None
    finally:
        await decoder.close()
        sink.close(timeout_seconds=5)


async def test_observer_failure_does_not_replace_provider_connection_failure():
    class BrokenSink:
        def record_payload(self, **record):
            raise OSError("diagnostic observer failed")

    def handler(request):
        raise httpx.ConnectError("provider transport unavailable", request=request)

    client = AsyncOpenAI(
        api_key="test-only",
        base_url="https://api.deepseek.com",
        max_retries=0,
        http_client=httpx.AsyncClient(
            transport=DiagnosticHTTPTransport(
                httpx.MockTransport(handler), BrokenSink(), provider="deepseek"
            )
        ),
    )
    decoder = build_deepseek_decoder(
        ProviderConfig(api_key="test-only", model="deepseek-flash", timeout=20), client
    )
    try:
        with pytest.raises(DecodeError) as failure:
            await decoder.decode("Commentary", Route())
        assert failure.value.reason == "provider_timeout"
        assert failure.value.__cause__ is None
    finally:
        await decoder.close()


async def test_a_buy_naming_a_lot_keeps_only_a_safe_schema_diagnostic():
    from openai import AsyncOpenAI

    def handler(request):
        return httpx.Response(
            200,
            json={
                "id": "chat-test",
                "object": "chat.completion",
                "created": 1,
                "model": "deepseek-flash",
                "choices": [
                    {
                        "index": 0,
                        "finish_reason": "stop",
                        "message": {
                            "role": "assistant",
                            "content": json.dumps(
                                {
                                    "reading": {
                                        "kind": "trade_made",
                                        "summary": "PRIVATE_PROVIDER_TEXT",
                                        "calls": [
                                            {
                                                "action": "buy",
                                                "action_words": "加回",
                                                "stock": {"ticker": "ABC", "words": "abc"},
                                                "price": {
                                                    "kind": "exact",
                                                    "value": "25",
                                                    "words": "25",
                                                },
                                                "size": {"kind": "not_given"},
                                                "sell_from": {"kind": "not_said"},
                                            }
                                        ],
                                    }
                                }
                            ),
                        },
                    }
                ],
                "usage": {"prompt_tokens": 10, "completion_tokens": 10, "total_tokens": 20},
            },
        )

    client = AsyncOpenAI(
        api_key="PRIVATE_API_KEY",
        base_url="https://api.deepseek.com",
        max_retries=0,
        http_client=httpx.AsyncClient(transport=httpx.MockTransport(handler)),
    )
    decoder = build_deepseek_decoder(
        ProviderConfig(api_key="PRIVATE_API_KEY", model="deepseek-flash", timeout=20), client
    )
    try:
        with pytest.raises(DecodeError) as failure:
            await decoder.decode("25加回29卖出的abc", Route())
        error = failure.value
        assert error.reason == "invalid_model_output"
        assert not error.retryable
        assert error.issues[0].model_dump() == {
            "path": "reading.trade_made.calls.0.buy.sell_from",
            "code": "extra_forbidden",
        }
        assert "PRIVATE" not in repr(error.issues) + str(error)
        assert error.__cause__ is None
    finally:
        await decoder.close()
