"""One service is checked the moment it is connected, with the same read-only probe a full
validation runs for it."""

import asyncio

import pytest
from pydantic import TypeAdapter, ValidationError

from copytrading_engine.trading.adapters.capabilities import (
    CapabilityCheck,
    TradingCapabilityService,
)
from copytrading_engine.trading.domain.config import ConnectionCheck

CHECK = TypeAdapter(ConnectionCheck)


class RecordingProbes:
    """Answers ready for every service, and remembers what each probe was handed."""

    def __init__(self, *, failing: str | None = None) -> None:
        self.calls: list[tuple[str, object, object]] = []
        self._failing = failing

    def _answer(self, name, **values) -> CapabilityCheck:
        if name == self._failing:
            raise RuntimeError("the client blew up")
        return CapabilityCheck(name=name, state="ready", adapter="fake", **values)

    async def source(self, configuration, token):
        self.calls.append(("source", configuration.channel_ids, token))
        return self._answer("source")

    async def model(self, configuration, token):
        self.calls.append(("model", configuration.model, token))
        return self._answer("model")

    async def broker(self, account, credentials):
        self.calls.append(("broker", account.id, credentials.secret.get_secret_value()))
        return self._answer("broker", subject=account.id, environment=account.environment)

    async def notification(self, configuration, token):
        self.calls.append(("notification", configuration.service, token))
        return self._answer("notification")


CONNECTIONS = {
    "source": {
        "kind": "source",
        "source": {"channel_ids": ["123"]},
        "token": "private-source-token",
    },
    "model": {
        "kind": "model",
        "provider": {"name": "deepseek", "model": "deepseek-flash"},
        "api_key": "private-model-key",
    },
    "broker": {
        "kind": "broker",
        "account": {"id": "primary", "environment": "paper"},
        "credentials": {"account_id": "primary", "key": "paper-key", "secret": "paper-secret"},
    },
    "notification": {
        "kind": "notification",
        "notification": {"service": "discord"},
        "token": "https://discord.com/api/webhooks/1/private",
    },
}


@pytest.mark.parametrize(
    ("kind", "handed"),
    [
        ("source", (("123",), "private-source-token")),
        ("model", ("deepseek-flash", "private-model-key")),
        ("broker", ("primary", "paper-secret")),
        ("notification", ("discord", "https://discord.com/api/webhooks/1/private")),
    ],
)
def test_each_service_is_checked_by_its_own_probe_alone(kind, handed):
    probes = RecordingProbes()

    check = asyncio.run(
        TradingCapabilityService(probes).check(CHECK.validate_python(CONNECTIONS[kind]))
    )

    assert check.name == kind
    assert check.state == "ready"
    assert probes.calls == [(kind, *handed)]


def test_a_broker_check_names_the_account_it_checked():
    check = asyncio.run(
        TradingCapabilityService(RecordingProbes()).check(
            CHECK.validate_python(CONNECTIONS["broker"])
        )
    )

    assert (check.subject, check.environment) == ("primary", "paper")


@pytest.mark.parametrize("kind", sorted(CONNECTIONS))
def test_a_client_that_blows_up_is_a_failed_check_without_details(kind):
    check = asyncio.run(
        TradingCapabilityService(RecordingProbes(failing=kind)).check(
            CHECK.validate_python(CONNECTIONS[kind])
        )
    )

    assert check.state == "failed"
    assert check.reason_code == f"{kind}_capability_unavailable"
    assert "private" not in check.model_dump_json()


def test_broker_keys_must_belong_to_the_account_checked():
    connection = {
        **CONNECTIONS["broker"],
        "credentials": {"account_id": "other", "key": "k", "secret": "s"},
    }

    with pytest.raises(ValidationError):
        CHECK.validate_python(connection)


def test_every_check_lists_its_secrets_for_redaction():
    secrets = {
        kind: CHECK.validate_python(connection).secret_values()
        for kind, connection in CONNECTIONS.items()
    }

    assert secrets == {
        "source": ("private-source-token",),
        "model": ("private-model-key",),
        "broker": ("paper-key", "paper-secret"),
        "notification": ("https://discord.com/api/webhooks/1/private",),
    }
