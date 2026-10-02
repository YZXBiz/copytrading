"""A model on this Mac or a custom address can run without a key in every request that names one."""

import pytest
from pydantic import ValidationError

from copytrading_engine.host.pipe.requests import REQUEST_ADAPTER

PROFILE = {
    "guru_id": "zhao",
    "display_name": "Zhao",
    "prefix": "ZHAO:",
    "playbook": "",
    "examples": [],
    "exit_basis": "original_position",
}


def learn(provider: dict, key: str) -> dict:
    return {
        "version": 1,
        "request_id": "r-1",
        "operation": "learn_guru_playbook",
        "channel_id": "123",
        "discord_token": "discord",
        "provider": provider,
        "provider_api_key": key,
    }


@pytest.mark.parametrize(
    "provider",
    [
        {"name": "ollama", "model": "llama3.2"},
        {"name": "openai_compatible", "model": "m", "base_url": "http://127.0.0.1:1234/v1"},
    ],
)
def test_a_local_model_learns_a_playbook_without_a_key(provider):
    request = REQUEST_ADAPTER.validate_python(learn(provider, ""))
    reader = request.provider.reader(request.provider_api_key, timeout=5)
    assert reader.api_key.get_secret_value() == ""


def test_a_cloud_model_without_a_key_is_refused_by_its_reader():
    request = REQUEST_ADAPTER.validate_python(learn({"name": "openai", "model": "gpt"}, ""))
    with pytest.raises(ValueError, match="API key is required"):
        request.provider.reader(request.provider_api_key, timeout=5)


def test_the_other_provider_requests_accept_an_empty_key_for_a_local_model():
    ollama = {"name": "ollama", "model": "llama3.2"}
    review = {
        "version": 1,
        "request_id": "r-2",
        "operation": "review_profile_examples",
        "profile": PROFILE,
        "provider": ollama,
        "provider_api_key": "",
        "destinations": [],
    }
    evaluate = review | {
        "operation": "evaluate_historical_profile",
        "source_id": "discord:123:1",
        "destinations": [{"account_id": "paper", "mode": "fixed", "amount_usd": "100"}],
    }
    for payload in (review, evaluate):
        try:
            REQUEST_ADAPTER.validate_python(payload)
        except ValidationError as error:
            fields = {".".join(map(str, item["loc"])) for item in error.errors()}
            assert not any("provider_api_key" in field for field in fields), fields
