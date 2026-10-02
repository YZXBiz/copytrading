"""Every interpreter the owner can choose also opens as a chat model for the assistant."""

import pytest
from pydantic import SecretStr

from copytrading_engine.parsing.providers.registry import open_chat_model
from copytrading_engine.shared.model_providers import MODEL_PROVIDERS, ProviderConfig


@pytest.mark.parametrize("name", MODEL_PROVIDERS)
async def test_each_provider_opens_a_chat_model(name):
    model_name = "openai/test" if name == "openrouter" else "test-model"
    config = ProviderConfig(
        api_key=SecretStr("k"),
        model=model_name,
        timeout=5,
        base_url="http://127.0.0.1:9/v1" if name == "openai_compatible" else None,
    )
    model, close = await open_chat_model(name, config)
    try:
        assert model.model_name == model_name
    finally:
        await close()
