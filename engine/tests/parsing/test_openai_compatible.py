"""Every OpenAI-style model service gets the request it expects and is read the same way."""

import json

import httpx2 as httpx
import pytest
from openai import AsyncOpenAI
from pydantic import SecretStr, ValidationError

from copytrading_engine.parsing.providers import openai_compatible
from copytrading_engine.parsing.providers.registry import builtin_registry
from copytrading_engine.parsing.routes import Route
from copytrading_engine.shared.model_providers import (
    MODEL_PROVIDERS,
    ProviderConfig,
    endpoint_problem,
)
from copytrading_engine.trading.domain.config import ProviderConfiguration

IGNORE = {"decision": "ignore", "reason": "No trade action", "instructions": []}


def reply(content: dict) -> dict:
    return {
        "id": "chatcmpl-1",
        "object": "chat.completion",
        "created": 1,
        "model": "test-model",
        "choices": [
            {
                "index": 0,
                "finish_reason": "stop",
                "message": {"role": "assistant", "content": json.dumps(content)},
            }
        ],
        "usage": {"prompt_tokens": 10, "completion_tokens": 10, "total_tokens": 20},
    }


@pytest.fixture
def requests(monkeypatch):
    seen: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return httpx.Response(200, json=reply(IGNORE))

    def client(**options):
        return AsyncOpenAI(
            **options | {"http_client": httpx.AsyncClient(transport=httpx.MockTransport(handler))}
        )

    monkeypatch.setattr(openai_compatible, "AsyncOpenAI", client)
    return seen


def test_every_offered_service_has_a_reader():
    assert set(builtin_registry().names()) == set(MODEL_PROVIDERS)


@pytest.mark.parametrize(
    "name", [name for name in openai_compatible.SERVICES if name != "openai_compatible"]
)
async def test_each_named_service_is_asked_at_its_own_address(requests, name):
    service = openai_compatible.SERVICES[name]
    model = "openai/test-model" if name == "openrouter" else "test-model"
    decoder = await openai_compatible.create_decoder(
        name, ProviderConfig(api_key=SecretStr("test-only"), model=model, timeout=5)
    )
    try:
        result = await decoder.decode("Market commentary only. No trade action.", Route())
    finally:
        await decoder.close()

    assert result.decision == "ignore"
    [request] = requests
    assert service.endpoint is not None
    assert str(request.url) == service.endpoint.rstrip("/") + "/chat/completions"
    assert request.headers["authorization"] == "Bearer test-only"
    body = json.loads(request.content)
    assert body["model"] == model
    assert body["temperature"] == 0
    takes_max_tokens = name in {"google", "mistral", "openrouter"}
    assert ("max_tokens" in body) is takes_max_tokens
    assert ("max_completion_tokens" in body) is (not takes_max_tokens)


async def test_a_custom_service_is_asked_at_the_owners_address_without_a_key(requests):
    decoder = await openai_compatible.create_decoder(
        "openai_compatible",
        ProviderConfig(
            api_key=SecretStr(""),
            model="local-model",
            timeout=5,
            base_url="http://127.0.0.1:1234/v1",
        ),
    )
    try:
        await decoder.decode("Market commentary only. No trade action.", Route())
    finally:
        await decoder.close()
    [request] = requests
    assert str(request.url) == "http://127.0.0.1:1234/v1/chat/completions"


async def test_ollama_can_be_moved_to_another_port(requests):
    decoder = await openai_compatible.create_decoder(
        "ollama",
        ProviderConfig(
            api_key=SecretStr(""), model="llama3.2", timeout=5, base_url="http://localhost:9999/v1"
        ),
    )
    try:
        await decoder.decode("Market commentary only. No trade action.", Route())
    finally:
        await decoder.close()
    assert str(requests[0].url) == "http://localhost:9999/v1/chat/completions"


async def test_a_custom_service_without_an_address_closes_nothing_it_opened():
    with pytest.raises(ValueError, match="address"):
        await openai_compatible.create_decoder(
            "openai_compatible",
            ProviderConfig(api_key=SecretStr("k"), model="m", timeout=5),
        )


async def test_construction_failure_closes_the_client(monkeypatch):
    class FakeClient:
        closed = 0

        async def close(self):
            FakeClient.closed += 1

    monkeypatch.setattr(openai_compatible, "AsyncOpenAI", lambda **_: FakeClient())

    def fail(*_args, **_kwargs):
        raise RuntimeError("agent construction failed")

    monkeypatch.setattr(openai_compatible, "build_decoder", fail)
    with pytest.raises(RuntimeError, match="agent construction failed"):
        await openai_compatible.create_decoder(
            "openai", ProviderConfig(api_key=SecretStr("k"), model="m", timeout=5)
        )
    assert FakeClient.closed == 1


@pytest.mark.parametrize(
    ("url", "allowed"),
    [
        ("https://models.example.com/v1", True),
        ("http://localhost:11434/v1", True),
        ("http://127.0.0.1:1234/v1", True),
        ("http://[::1]:8080/v1", True),
        ("http://models.example.com/v1", False),
        ("ftp://models.example.com", False),
        ("https://user:pass@models.example.com/v1", False),
        ("https://models.example.com/v1?key=abc", False),
        ("models.example.com/v1", False),
    ],
)
def test_an_owner_entered_address_must_be_encrypted_unless_it_is_this_mac(url, allowed):
    assert (endpoint_problem(url) is None) is allowed


def test_only_local_and_custom_models_take_an_address():
    ProviderConfiguration(name="ollama", model="llama3.2")
    ProviderConfiguration(name="ollama", model="llama3.2", base_url="http://localhost:9999/v1")
    ProviderConfiguration(name="openai_compatible", model="m", base_url="https://x.example/v1")
    with pytest.raises(ValidationError, match="needs its address"):
        ProviderConfiguration(name="openai_compatible", model="m")
    with pytest.raises(ValidationError, match="Only a local or custom model"):
        ProviderConfiguration(name="openai", model="gpt", base_url="https://evil.example/v1")
    with pytest.raises(ValidationError, match="localhost"):
        ProviderConfiguration(name="openai_compatible", model="m", base_url="http://lan-box/v1")


def test_openrouter_models_name_their_upstream_provider():
    ProviderConfiguration(name="openrouter", model="anthropic/claude-sonnet-5.5")
    with pytest.raises(ValidationError, match="like openai/"):
        ProviderConfiguration(name="openrouter", model="claude-sonnet-5.5")


def test_a_cloud_service_needs_its_key_and_a_local_one_does_not():
    with pytest.raises(ValueError, match="API key is required"):
        ProviderConfiguration(name="openai", model="gpt").reader(SecretStr(""), timeout=5)
    local = ProviderConfiguration(name="ollama", model="llama3.2").reader(SecretStr(""), timeout=5)
    assert local.base_url is None
    custom = ProviderConfiguration(
        name="openai_compatible", model="m", base_url="https://x.example/v1"
    ).reader(SecretStr(""), timeout=5)
    assert custom.base_url == "https://x.example/v1"
