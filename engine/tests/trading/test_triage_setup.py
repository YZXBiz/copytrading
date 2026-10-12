"""The optional triage decision model in the saved setup, its key, and its connection check
(ADR-0012)."""

import asyncio

import pytest
from pydantic import SecretStr, ValidationError

from copytrading_engine.trading.adapters.capabilities import (
    CapabilityCheck,
    NativeCapabilityProbes,
    TradingCapabilityService,
)
from copytrading_engine.trading.domain.config import (
    TradingConfiguration,
    TradingSecrets,
    TriageCheck,
    TriageConfiguration,
)

from .test_capabilities import _configuration, _fakes, _secrets

TRIAGE = {"provider": "openai-decisions", "model": "gpt-6-luna", "route_threshold": 0.9}


def _with(triage: dict | None, provider: str = "deepseek") -> TradingConfiguration:
    saved = _configuration().model_dump(mode="json")
    saved["provider"] = {"name": provider, "model": "test-model"}
    saved["triage"] = triage
    return TradingConfiguration.model_validate(saved)


def test_triage_is_off_unless_the_setup_names_one():
    assert _configuration().triage is None
    assert _with(TRIAGE).triage == TriageConfiguration(
        provider="openai-decisions", model="gpt-6-luna", route_threshold=0.9
    )
    assert _with({"provider": "typesafe", "model": "jev-latest"}).triage.route_threshold == 0.9


@pytest.mark.parametrize(
    "triage",
    [
        TRIAGE | {"extra": True},
        TRIAGE | {"provider": "anthropic"},
        TRIAGE | {"route_threshold": 1.5},
        TRIAGE | {"route_threshold": 0.2},
        TRIAGE | {"model": ""},
    ],
)
def test_a_malformed_triage_section_is_refused(triage):
    with pytest.raises(ValidationError):
        _with(triage)


def test_triage_sits_in_front_of_the_deepseek_reader_only():
    with pytest.raises(ValidationError, match="DeepSeek"):
        _with(TRIAGE, provider="anthropic")


def test_the_triage_key_travels_with_the_other_secrets_and_is_required():
    secrets = TradingSecrets.model_validate(
        {
            "discord_token": "private-source-token",
            "provider_api_key": "private-model-key",
            "brokers": [],
            "triage_api_key": "private-triage-key",
        }
    )
    triage = _with(TRIAGE).triage

    config = triage.config(secrets.triage_api_key, timeout=5)

    assert config.api_key.get_secret_value() == "private-triage-key"
    assert "private-triage-key" not in repr(secrets)
    with pytest.raises(ValueError, match="triage model API key"):
        triage.config(None, timeout=5)


def test_full_validation_checks_triage_only_when_it_is_set_up():
    probes = _fakes()
    seen = []

    async def triage(configuration, token):
        seen.append((configuration.model, token))
        return CapabilityCheck(name="triage", state="ready", adapter="controlled-fake")

    probes.triage = triage
    secrets = _secrets().model_copy(update={"triage_api_key": SecretStr("private-triage-key")})
    service = TradingCapabilityService(probes)

    with_triage = asyncio.run(service.validate(_with(TRIAGE), secrets))
    without = asyncio.run(service.validate(_configuration(), _secrets()))

    assert "triage" in {check.name for check in with_triage.checks}
    assert "triage" not in {check.name for check in without.checks}
    assert seen == [("gpt-6-luna", "private-triage-key")]
    assert "private-triage-key" not in with_triage.model_dump_json()


def test_connect_checks_the_triage_key_on_its_own():
    probes = _fakes()

    async def triage(configuration, token):
        assert token == "private-triage-key"
        return CapabilityCheck(
            name="triage", state="failed", adapter="openai-decisions", reason_code="x"
        )

    probes.triage = triage
    check = TriageCheck(
        kind="triage",
        triage=TriageConfiguration(**TRIAGE),
        api_key=SecretStr("private-triage-key"),
    )

    result = asyncio.run(TradingCapabilityService(probes).check(check))

    assert (result.name, result.state) == ("triage", "failed")
    assert check.secret_values() == ("private-triage-key",)


def test_the_native_probe_refuses_a_missing_key_without_a_request():
    result = asyncio.run(NativeCapabilityProbes().triage(TriageConfiguration(**TRIAGE), ""))

    assert (result.state, result.reason_code) == ("failed", "triage_key_missing")
