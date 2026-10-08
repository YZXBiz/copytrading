"""The provider registry builds, closes, and budgets decoders without leaking provider text."""

import pytest
from pydantic import SecretStr, ValidationError
from pydantic_ai.exceptions import ModelHTTPError, UsageLimitExceeded

from copytrading_engine.parsing.extraction import DecodeError
from copytrading_engine.parsing.providers.pydantic_ai import PydanticAIDecoder
from copytrading_engine.parsing.providers.registry import ProviderRegistry, builtin_registry
from copytrading_engine.parsing.routes import Route
from copytrading_engine.shared.model_providers import MODEL_PROVIDERS, ProviderConfig

from ..readings import commentary


def config() -> ProviderConfig:
    return ProviderConfig(api_key=SecretStr("test-only"), model="test-model", timeout=1)


class CloseOnlyClient:
    async def close(self) -> None:
        pass


async def test_unknown_provider_never_calls_a_factory():
    calls = []

    async def factory(provider_config):
        calls.append(provider_config)
        raise AssertionError("must not construct")

    registry = ProviderRegistry({"deepseek": factory})

    with pytest.raises(ValueError, match="Unknown LLM provider"):
        await registry.create("typo", config())

    assert calls == []


async def test_fake_provider_can_register_decode_and_close_without_worker_changes():
    calls = []

    class FakeDecoder:
        def __init__(self):
            self.close_calls = 0

        async def decode(self, text, route, recent=()):
            calls.append((text, route))
            return commentary("fake")

        async def close(self):
            self.close_calls += 1

    decoder = FakeDecoder()

    async def fake_factory(provider_config):
        assert provider_config == config()
        return decoder

    supplied = {"fake": fake_factory}
    registry = ProviderRegistry(supplied)
    supplied["injected-later"] = fake_factory

    assert registry.names() == ("fake",)
    registered = await registry.create("fake", config())
    route = Route()
    reading = await registered.decode("message", route)
    await registered.close()

    assert reading.kind == "commentary"
    assert calls == [("message", route)]
    assert decoder.close_calls == 1


def test_registry_names_are_sorted_from_its_copied_mapping():
    async def factory(provider_config):
        raise AssertionError("factory is not needed")

    supplied = {"zeta": factory, "alpha": factory}
    registry = ProviderRegistry(supplied)
    supplied["late"] = factory

    assert registry.names() == ("alpha", "zeta")


def test_builtin_registry_offers_every_model_service():
    assert builtin_registry().names() == tuple(sorted(MODEL_PROVIDERS))


def test_provider_config_is_frozen_and_validates_inputs():
    provider_config = config()

    with pytest.raises(ValidationError):
        provider_config.__setattr__("model", "other-model")

    with pytest.raises(ValidationError):
        ProviderConfig(api_key="key", model="", timeout=0)


async def test_deepseek_factory_closes_client_when_agent_construction_fails(monkeypatch):
    from copytrading_engine.parsing.providers import deepseek

    class FakeClient:
        def __init__(self):
            self.closed = 0

        async def close(self):
            self.closed += 1

    client = FakeClient()
    monkeypatch.setattr(deepseek, "AsyncOpenAI", lambda **kwargs: client)

    def fail_build(*args, **kwargs):
        raise RuntimeError("agent construction failed")

    monkeypatch.setattr(deepseek, "build_decoder", fail_build)

    with pytest.raises(RuntimeError, match="agent construction failed"):
        await deepseek.create_decoder(config())

    assert client.closed == 1


def test_prompt_bytes_match_the_pre_adapter_prompt():
    import hashlib

    from copytrading_engine.parsing.prompt import INSTRUCTIONS

    assert (
        hashlib.sha256(INSTRUCTIONS.encode()).hexdigest()
        == "6800492b8380b1f927996f629f58fafe42dace63b9b2df4fecdb92c587f255e5"
    )


async def test_budget_exhaustion_is_translated_without_provider_text():
    class FailedAgent:
        async def run(self, *args, **kwargs):
            raise UsageLimitExceeded("PRIVATE_PROVIDER_DETAIL")

    decoder = PydanticAIDecoder(FailedAgent(), FailedAgent(), CloseOnlyClient(), timeout=1)

    with pytest.raises(DecodeError) as failure:
        await decoder.decode("source", Route())

    assert failure.value.reason == "model_output_budget_exceeded"
    assert not failure.value.retryable
    assert "PRIVATE_PROVIDER_DETAIL" not in str(failure.value)
    assert failure.value.__cause__ is None


async def test_rejected_key_does_not_leak_http_body():
    class FailedAgent:
        async def run(self, *args, **kwargs):
            raise ModelHTTPError(
                status_code=401,
                model_name="test-model",
                body={"error": "PRIVATE_PROVIDER_DETAIL"},
            )

    decoder = PydanticAIDecoder(FailedAgent(), FailedAgent(), CloseOnlyClient(), timeout=1)

    with pytest.raises(DecodeError) as failure:
        await decoder.decode("source", Route())

    assert failure.value.reason == "provider_key_rejected"
    assert not failure.value.retryable
    assert "PRIVATE_PROVIDER_DETAIL" not in str(failure.value)
    assert failure.value.__cause__ is None


@pytest.mark.parametrize(
    ("status", "body", "reason"),
    [
        (401, {"error": "bad key"}, "provider_key_rejected"),
        (403, None, "provider_key_rejected"),
        # OpenAI, Anthropic, and Ollama answer an unknown model with 404 and quote its name.
        (
            404,
            {
                "error": {
                    "code": "model_not_found",
                    "message": "The model `test-model` does not exist",
                }
            },
            "provider_model_not_found",
        ),
        (
            404,
            {"error": {"message": 'model "test-model" not found, try pulling it first'}},
            "provider_model_not_found",
        ),
        # DeepSeek and Mistral answer it with 400.
        (
            400,
            {
                "error": {
                    "message": "The supported API model names are a, b, but you passed test-model."
                }
            },
            "provider_model_not_found",
        ),
        (400, {"message": "Invalid model: test-model"}, "provider_model_not_found"),
        # A 404 that does not quote the model is a wrong address, not a wrong name.
        (404, {"detail": "Not Found"}, "provider_rejected"),
        (400, {"error": {"message": "max_tokens is too large"}}, "provider_rejected"),
    ],
)
async def test_rejections_name_the_key_or_the_model(status, body, reason):
    class FailedAgent:
        async def run(self, *args, **kwargs):
            raise ModelHTTPError(status_code=status, model_name="test-model", body=body)

    decoder = PydanticAIDecoder(FailedAgent(), FailedAgent(), CloseOnlyClient(), timeout=1)

    with pytest.raises(DecodeError) as failure:
        await decoder.decode("source", Route())

    assert failure.value.reason == reason


async def test_model_names_strip_google_prefix_and_stop_at_the_limit():
    class Listed:
        def __init__(self, id):
            self.id = id

    class Models:
        def list(self):
            async def pages():
                yield Listed("models/gemini-2.5-flash")
                yield Listed("deepseek-flash")

            return pages()

    class ListingClient(CloseOnlyClient):
        models = Models()

    decoder = PydanticAIDecoder(None, None, ListingClient(), timeout=1)

    assert await decoder.model_names() == ("gemini-2.5-flash", "deepseek-flash")


async def test_learning_failures_are_translated_without_provider_text():
    class FailedAgent:
        async def run(self, *args, **kwargs):
            raise ModelHTTPError(
                status_code=503,
                model_name="test-model",
                body={"error": "PRIVATE_PROVIDER_DETAIL"},
            )

    decoder = PydanticAIDecoder(FailedAgent(), FailedAgent(), CloseOnlyClient(), timeout=1)

    with pytest.raises(DecodeError) as failure:
        await decoder.learn(("25加了abc",))

    assert failure.value.reason == "provider_unavailable"
    assert failure.value.retryable
    assert "PRIVATE_PROVIDER_DETAIL" not in str(failure.value)
