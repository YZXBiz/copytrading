"""Capability validation reads connections and never changes trading state."""

import asyncio
from dataclasses import dataclass

import discord
import httpx
from pydantic import SecretStr

import copytrading_engine.trading.adapters.capabilities as capabilities
from copytrading_engine.trading.adapters.capabilities import (
    CapabilityCheck,
    NativeCapabilityProbes,
    TradingCapabilityService,
)
from copytrading_engine.trading.domain.config import (
    AccountConfiguration,
    BrokerCredentials,
    NotificationConfiguration,
    ProviderConfiguration,
    SourceConfiguration,
    TradingConfiguration,
    TradingSecrets,
)
from copytrading_engine.trading.domain.profiles import ProfileBuilder, ProfileDraft


def _configuration(*, notification: bool = False) -> TradingConfiguration:
    profile = ProfileBuilder().build(
        ProfileDraft(
            guru_id="stable-guru",
            display_name="Stable Guru",
            prefix="ALERT:",
            playbook="",
            examples=(),
            exit_basis="original_position",
        )
    )
    return TradingConfiguration.model_validate(
        {
            "version": 4,
            "source": {"channel_ids": ["123"]},
            "provider": {"name": "deepseek", "model": "test-model"},
            "accounts": [
                {"id": "paper-account", "environment": "paper"},
                {"id": "live-account", "environment": "live"},
            ],
            "profiles": [profile.model_dump(mode="json")],
            "routes": [
                {
                    "channel_id": "123",
                    "author_id": None,
                    "guru_id": profile.guru_id,
                    "profile_revision": profile.profile_revision,
                    "connections": [
                        {"account_id": "paper-account", "mode": "fixed", "amount_usd": "100"},
                        {"account_id": "live-account", "mode": "fixed", "amount_usd": "100"},
                    ],
                }
            ],
            "notification": {"chat_id": "room-1"} if notification else None,
        }
    )


def _secrets(*, notification: bool = False) -> TradingSecrets:
    return TradingSecrets.model_validate(
        {
            "discord_token": "private-source-token",
            "provider_api_key": "private-model-key",
            "brokers": [
                {"account_id": "paper-account", "key": "paper-key", "secret": "paper-secret"},
                {"account_id": "live-account", "key": "live-key", "secret": "live-secret"},
            ],
            "notification_token": "private-notification-token" if notification else None,
        }
    )


@dataclass
class FakeProbes:
    source_result: CapabilityCheck
    model_result: CapabilityCheck
    broker_results: dict[str, CapabilityCheck]
    notification_result: CapabilityCheck
    calls: list[tuple[str, str | None]]

    async def source(self, configuration, token):
        self.calls.append(("source", None))
        assert token == "private-source-token"
        return self.source_result

    async def model(self, configuration, token):
        self.calls.append(("model", None))
        assert token == "private-model-key"
        return self.model_result

    async def broker(self, account, credentials):
        self.calls.append(("broker", account.id))
        assert credentials.account_id == account.id
        return self.broker_results[account.id]

    async def notification(self, configuration, token):
        self.calls.append(("notification", None))
        if token is not None:
            assert token == "private-notification-token"
        return self.notification_result


def _ready(name: str, *, subject: str | None = None, environment: str | None = None):
    return CapabilityCheck(
        name=name,
        state="ready",
        subject=subject,
        environment=environment,
        identity=f"verified-{subject or name}",
        adapter="controlled-fake",
        reason_code=None,
    )


def _fakes(*, failed: str | None = None, notification: bool = False):
    def result(name, subject=None, environment=None):
        if failed == name:
            return CapabilityCheck(
                name=name,
                state="failed",
                subject=subject,
                environment=environment,
                identity=None,
                adapter="controlled-fake",
                reason_code=f"{name}_capability_failed",
            )
        return _ready(name, subject=subject, environment=environment)

    return FakeProbes(
        source_result=result("source"),
        model_result=result("model"),
        broker_results={
            account.id: result("broker", account.id, account.environment)
            for account in _configuration().accounts
        },
        notification_result=(
            result("notification")
            if notification
            else CapabilityCheck(
                name="notification",
                state="not_configured",
                adapter="not_configured",
                reason_code=None,
            )
        ),
        calls=[],
    )


def test_validation_requires_real_source_model_and_each_explicit_broker_environment():
    probes = _fakes()
    report = asyncio.run(TradingCapabilityService(probes).validate(_configuration(), _secrets()))

    assert report.activatable is True
    assert report.configuration_revision == _configuration().revision()
    assert {
        (item.name, item.subject, item.environment)
        for item in report.checks
        if item.name == "broker"
    } == {
        ("broker", "paper-account", "paper"),
        ("broker", "live-account", "live"),
    }
    assert any(
        item.name == "public_source_authorization" and item.state == "unsupported"
        for item in report.checks
    )
    assert "public_discord_authorization_not_qualified" in report.release_gates
    assert "private-source-token" not in report.model_dump_json()
    assert "private-model-key" not in report.model_dump_json()
    assert probes.calls.count(("broker", "paper-account")) == 1
    assert probes.calls.count(("broker", "live-account")) == 1


def test_one_failed_capability_keeps_configuration_nonactivatable():
    report = asyncio.run(
        TradingCapabilityService(_fakes(failed="broker")).validate(_configuration(), _secrets())
    )

    assert report.activatable is False
    assert any(item.name == "broker" and item.state == "failed" for item in report.checks)


def test_validation_never_sends_a_notification_message():
    probes = _fakes(notification=True)
    report = asyncio.run(
        TradingCapabilityService(probes).validate(
            _configuration(notification=True), _secrets(notification=True)
        )
    )

    assert report.activatable is True
    assert ("notification", None) in probes.calls


def test_cancelled_probe_propagates_cancellation():
    entered = asyncio.Event()

    class SlowProbes(FakeProbes):
        async def source(self, configuration, token):
            entered.set()
            await asyncio.Event().wait()

    probes = _fakes()
    slow_probes = SlowProbes(**vars(probes))

    async def run_and_cancel():
        task = asyncio.create_task(
            TradingCapabilityService(slow_probes).validate(_configuration(), _secrets())
        )
        await entered.wait()
        task.cancel()
        try:
            await task
        except asyncio.CancelledError:
            return True
        return False

    assert asyncio.run(run_and_cancel()) is True


def test_native_source_probe_uses_authenticated_identity_and_channel_read(monkeypatch):
    calls = []

    class ReadableChannel(discord.abc.Messageable):
        def history(self, *, limit):
            calls.append(("history", limit))

            async def messages():
                calls.append(("history_read", limit))
                yield object()

            return messages()

    class Client:
        user = type("User", (), {"id": 987})()

        def __init__(self):
            calls.append(("client", None))

        async def login(self, token):
            calls.append(("login", token))

        async def fetch_channel(self, channel_id):
            calls.append(("channel", channel_id))
            return ReadableChannel()

        async def close(self):
            calls.append(("close", None))

    probes = NativeCapabilityProbes(discord_client_factory=Client)
    result = asyncio.run(probes.source(SourceConfiguration(channel_ids=("123",)), "source-secret"))
    assert result.state == "ready"
    assert result.identity == "discord_user:987"
    assert result.adapter == "discord-py-self-user-token"
    assert ("login", "source-secret") in calls
    assert ("channel", 123) in calls
    assert ("history", 1) in calls
    assert ("history_read", 1) in calls
    assert calls[-1] == ("close", None)


def test_native_source_probe_reports_history_permission_denial_without_secret_details():
    class ForbiddenChannel(discord.abc.Messageable):
        def history(self, *, limit):
            assert limit == 1

            async def messages():
                from types import SimpleNamespace

                raise discord.Forbidden(
                    SimpleNamespace(status=403, reason="Forbidden", headers={}),
                    "history denied with private details",
                )
                yield object()

            return messages()

    class Client:
        user = type("User", (), {"id": 987})()

        async def login(self, token):
            pass

        async def fetch_channel(self, channel_id):
            return ForbiddenChannel()

        async def close(self):
            pass

    result = asyncio.run(
        NativeCapabilityProbes(discord_client_factory=Client).source(
            SourceConfiguration(channel_ids=("123",)), "source-secret"
        )
    )
    assert result.state == "failed"
    assert result.reason_code == "source_history_permission_denied"
    assert "private details" not in str(result.model_dump(mode="json"))


def test_native_source_probe_bounds_history_permission_check():
    class SlowChannel(discord.abc.Messageable):
        def history(self, *, limit):
            async def messages():
                await asyncio.Event().wait()
                yield object()

            return messages()

    class Client:
        user = type("User", (), {"id": 987})()

        async def login(self, token):
            pass

        async def fetch_channel(self, channel_id):
            return SlowChannel()

        async def close(self):
            pass

    result = asyncio.run(
        NativeCapabilityProbes(discord_client_factory=Client, source_timeout_seconds=0.01).source(
            SourceConfiguration(channel_ids=("123",)), "source-secret"
        )
    )
    assert result.state == "failed"
    assert result.reason_code == "source_history_probe_timed_out"


def test_native_model_probe_uses_configured_provider_and_safe_failure_reason(monkeypatch):
    created = []

    class Decoder:
        async def close(self):
            created.append(("close", None))

    class Registry:
        async def create(self, name, configuration):
            created.append((name, configuration.model, configuration.timeout))
            return Decoder()

    async def ready(decoder, health):
        health.ready = True
        health.error = None

    monkeypatch.setattr(capabilities, "builtin_registry", lambda: Registry())
    monkeypatch.setattr(capabilities, "probe_model", ready)
    probes = NativeCapabilityProbes()
    result = asyncio.run(
        probes.model(
            ProviderConfiguration(name="deepseek", model="configured-model"), "provider-secret"
        )
    )
    assert result.state == "ready"
    assert result.identity == "deepseek:configured-model"
    assert created == [("deepseek", "configured-model", 20), ("close", None)]

    async def failed(decoder, health):
        health.ready = False
        health.error = "private provider response body"

    monkeypatch.setattr(capabilities, "probe_model", failed)
    rejected = asyncio.run(
        probes.model(
            ProviderConfiguration(name="deepseek", model="configured-model"), "provider-secret"
        )
    )
    assert rejected.state == "failed"
    assert rejected.reason_code == "model_probe_rejected"
    assert "provider-secret" not in rejected.model_dump_json()
    assert "private provider response body" not in rejected.model_dump_json()


def test_native_model_probe_names_a_rejected_key_and_suggests_a_listed_model(monkeypatch):
    class Decoder:
        async def model_names(self):
            return ("deepseek-flash", "deepseek-pro")

        async def close(self):
            pass

    class Registry:
        async def create(self, name, configuration):
            return Decoder()

    def failing(reason):
        async def probe(decoder, health):
            health.ready = False
            health.error = reason

        return probe

    monkeypatch.setattr(capabilities, "builtin_registry", lambda: Registry())
    probes = NativeCapabilityProbes()

    def check(model):
        return asyncio.run(probes.model(ProviderConfiguration(name="deepseek", model=model), "key"))

    monkeypatch.setattr(capabilities, "probe_model", failing("provider_key_rejected"))
    key = check("deepseek-flash")
    assert (key.state, key.reason_code, key.suggestion) == ("failed", "model_key_rejected", None)

    monkeypatch.setattr(capabilities, "probe_model", failing("provider_model_not_found"))
    typo = check("dpeeseek-flash")
    assert (typo.reason_code, typo.suggestion) == ("model_not_found", "deepseek-flash")
    unrelated = check("llama-3.3-70b")
    assert (unrelated.reason_code, unrelated.suggestion) == ("model_not_found", None)


def test_native_model_probe_still_fails_cleanly_when_the_model_list_is_unavailable(monkeypatch):
    class Decoder:
        async def model_names(self):
            raise RuntimeError("PRIVATE list failure")

        async def close(self):
            pass

    class Registry:
        async def create(self, name, configuration):
            return Decoder()

    async def missing(decoder, health):
        health.ready = False
        health.error = "provider_model_not_found"

    monkeypatch.setattr(capabilities, "builtin_registry", lambda: Registry())
    monkeypatch.setattr(capabilities, "probe_model", missing)
    result = asyncio.run(
        NativeCapabilityProbes().model(ProviderConfiguration(name="deepseek", model="x"), "key")
    )
    assert (result.reason_code, result.suggestion) == ("model_not_found", None)
    assert "PRIVATE" not in result.model_dump_json()


def test_native_broker_probe_reads_account_positions_and_orders_only(monkeypatch):
    calls = []

    class Account:
        id = "broker-account-123"
        active = True

    class Broker:
        def __init__(self, credentials, environment):
            calls.append(("init", environment))

        def account(self):
            calls.append(("account", None))
            return Account()

        def positions(self):
            calls.append(("positions", None))
            return ()

        def open_orders(self):
            calls.append(("open_orders", None))
            return ()

        def close(self):
            calls.append(("close", None))

        def submit_order(self, *_args, **_kwargs):
            raise AssertionError("capability validation must not submit an order")

    monkeypatch.setattr(capabilities, "AlpacaBroker", Broker)
    probes = NativeCapabilityProbes()
    result = asyncio.run(
        probes.broker(
            AccountConfiguration(id="paper", environment="paper"),
            BrokerCredentials(
                account_id="paper", key=SecretStr("broker-key"), secret=SecretStr("broker-secret")
            ),
        )
    )
    assert result.state == "ready"
    assert result.environment == "paper"
    assert result.identity == "broker-account-123"
    assert [name for name, _ in calls] == ["init", "account", "positions", "open_orders", "close"]


def test_native_notification_probe_uses_only_get_me_and_get_chat():
    requests = []

    def handle(request):
        requests.append((request.method, request.url.path, request.url.query))
        if request.url.path.endswith("/getMe"):
            return httpx.Response(200, json={"ok": True, "result": {"username": "signal_bot"}})
        if request.url.path.endswith("/getChat"):
            return httpx.Response(200, json={"ok": True, "result": {"id": 321}})
        raise AssertionError(f"unexpected notification capability path: {request.url.path}")

    transport = httpx.MockTransport(handle)

    def client_factory(**kwargs):
        return httpx.AsyncClient(transport=transport, **kwargs)

    probes = NativeCapabilityProbes(http_client_factory=client_factory)
    result = asyncio.run(
        probes.notification(NotificationConfiguration(chat_id="321"), "bot-secret")
    )
    assert result.state == "ready"
    assert result.identity == "telegram_bot:@signal_bot;chat:321"
    assert [method for method, _, _ in requests] == ["GET", "GET"]
    assert [path.rsplit("/", 1)[-1] for _, path, _ in requests] == ["getMe", "getChat"]
    assert all("sendMessage" not in path for _, path, _ in requests)
