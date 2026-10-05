"""The runtime registers every credential for redaction before any capture uses it."""

import asyncio
import datetime as dt

import pytest
from pydantic import SecretStr, ValidationError

from copytrading_engine.shared.raw_message import RawMessage
from copytrading_engine.sources.sqlite import SQLiteSourceStore
from copytrading_engine.trading.adapters.telemetry import TradingTelemetry
from copytrading_engine.trading.domain.config import TradingConfiguration, TradingSecrets
from copytrading_engine.trading.domain.profiles import ProfileBuilder, ProfileDraft, ProfileExample
from copytrading_engine.trading.entrypoints.factories import TradingFactories
from copytrading_engine.trading.entrypoints.runtime import TradingRuntime

from ...diagnostics.telemetry.builders import journal_events, journal_sink, journal_text
from ...readings import commentary
from .builders import trading_configuration, trading_secrets, wait_for
from .fakes import Decoder, Owner, Session


async def test_runtime_registers_all_loaded_credentials_before_source_and_model_capture(tmp_path):
    credential_values = (
        ("source", "discord-secret"),
        ("provider", "provider-secret"),
        ("first broker key", "first-key"),
        ("first broker secret", "first-secret"),
        ("second broker key", "second-key"),
        ("second broker secret", "second-secret"),
        ("notification", "notification-secret"),
    )

    sink = journal_sink(tmp_path / "diagnostics")
    telemetry = TradingTelemetry(sink=sink)
    event = RawMessage(
        schema_version=1,
        event_type="raw_message",
        source="discord",
        channel_id="123",
        id="credential-echo",
        timestamp=dt.datetime.now(dt.UTC),
        text="ALERT: " + " ".join(value for _, value in credential_values),
    )

    class _EchoDecoder:
        async def decode(self, text, route):
            telemetry.record_payload(
                capture_kind="model_response",
                workflow_id=None,
                trace_id=None,
                destination_id=None,
                attempt=None,
                provider="anthropic",
                payload={"error": "provider rejected " + credential_values[1][1]},
            )
            return commentary("synthetic probe")

        async def close(self):
            pass

    async def owner_factory(path, credentials, policy, environment):
        return Owner(path, {}, {})

    async def decoder_factory(name, config):
        return _EchoDecoder()

    factories = TradingFactories(
        owner=owner_factory,
        decoder=decoder_factory,
        session=lambda source, channels, authors, stop, report_failure: Session(source, event),
    )
    secrets = TradingSecrets.model_validate(
        {
            "discord_token": credential_values[0][1],
            "provider_api_key": credential_values[1][1],
            "brokers": [
                {
                    "account_id": "first",
                    "key": credential_values[2][1],
                    "secret": credential_values[3][1],
                },
                {
                    "account_id": "second",
                    "key": credential_values[4][1],
                    "secret": credential_values[5][1],
                },
            ],
            "notification_token": credential_values[6][1],
        }
    )
    runtime = TradingRuntime(tmp_path, factories=factories, telemetry=telemetry)
    try:
        await runtime.start(trading_configuration(), secrets)
        await wait_for(
            runtime,
            lambda _: (
                sink.capture_health().source_events >= 1
                and sink.capture_health().model_responses >= 1
            ),
        )
        assert sink.flush(timeout_seconds=5)
        journal = journal_text(tmp_path / "diagnostics")
    finally:
        await runtime.shutdown()
        sink.close(timeout_seconds=5)

    leaked = [label for label, value in credential_values if value in journal]
    assert not leaked, f"credential categories reached the journal: {leaked}"


async def test_redaction_registry_overflow_marks_gap_without_blocking_runtime(tmp_path):
    from copytrading_engine.diagnostics.telemetry import local as local_module

    sink = journal_sink(
        tmp_path / "diagnostics",
        secrets=tuple(f"seed-{index}" for index in range(local_module._MAX_KNOWN_SECRETS)),
    )
    telemetry = TradingTelemetry(sink=sink)

    class _CaptureDecoder:
        async def decode(self, text, route):
            telemetry.record_payload(
                capture_kind="model_response",
                workflow_id=None,
                trace_id=None,
                destination_id=None,
                attempt=None,
                provider="anthropic",
                payload={"error": "upstream echoed provider-secret"},
            )
            return commentary("probe ok")

        async def close(self):
            pass

    async def owner_factory(path, credentials, policy, environment):
        return Owner(path, {}, {})

    runtime = TradingRuntime(
        tmp_path,
        factories=TradingFactories(
            owner=owner_factory,
            decoder=lambda name, config: asyncio.sleep(0, result=_CaptureDecoder()),
            session=lambda source, channels, authors, stop, report_failure: Session(source, None),
        ),
        telemetry=telemetry,
    )
    try:
        await runtime.start(trading_configuration(), trading_secrets())
        running = await wait_for(runtime, lambda status: status.state == "running")
        assert running.active_accounts == 2
        assert sink.flush(timeout_seconds=5)
        health = sink.capture_health()
    finally:
        await runtime.shutdown()
        sink.close(timeout_seconds=5)

    assert health.model_responses == 0
    assert health.model_response_gaps >= 1
    assert all(
        getattr(event, "payload", None) is None
        for event in journal_events(tmp_path / "diagnostics")
    )
    assert "provider-secret" not in repr(journal_events(tmp_path / "diagnostics"))


async def test_validate_adds_candidate_credentials_while_retaining_active_credentials(tmp_path):
    active = trading_secrets()
    candidate = TradingSecrets.model_validate(
        {
            "discord_token": "candidate-discord-token",
            "provider_api_key": "candidate-provider-key",
            "brokers": [
                {
                    "account_id": "first",
                    "key": "candidate-first-key",
                    "secret": "candidate-first-secret",
                },
                {
                    "account_id": "second",
                    "key": "candidate-second-key",
                    "secret": "candidate-second-secret",
                },
            ],
            "notification_token": "candidate-notification-token",
        }
    )
    values = (
        ("active provider", "provider-secret"),
        ("candidate provider", "candidate-provider-key"),
        ("candidate source", "candidate-discord-token"),
        ("candidate broker", "candidate-first-secret"),
        ("candidate notification", "candidate-notification-token"),
    )

    sink = journal_sink(tmp_path / "diagnostics")
    telemetry = TradingTelemetry(sink=sink)
    configuration = trading_configuration()

    class _CapabilityService:
        async def validate(self, config, secrets):
            telemetry.record_payload(
                capture_kind="model_response",
                workflow_id=None,
                trace_id=None,
                destination_id=None,
                attempt=None,
                provider="anthropic",
                payload={
                    "error": "candidate probe echoed " + " ".join(value for _, value in values)
                },
            )
            from copytrading_engine.trading.adapters.capabilities import TradingCapabilityReport

            return TradingCapabilityReport(
                configuration_revision=config.revision(),
                activatable=False,
                checks=(),
                release_gates=(),
                cost_notice="synthetic test",
            )

    runtime = TradingRuntime(
        tmp_path,
        factories=TradingFactories(
            owner=lambda *args: asyncio.sleep(0, result=Owner(args[0], {}, {})),
            decoder=lambda name, config: asyncio.sleep(0, result=Decoder()),
            session=lambda source, channels, authors, stop, report_failure: Session(source, None),
        ),
        telemetry=telemetry,
        capability_service=_CapabilityService(),
    )
    try:
        await runtime.start(configuration, active)
        await runtime.validate(configuration, candidate)
        assert sink.flush(timeout_seconds=5)
        journal = journal_text(tmp_path / "diagnostics")
    finally:
        await runtime.shutdown()
        sink.close(timeout_seconds=5)

    leaked = [label for label, value in values if value in journal]
    assert not leaked, f"credential categories reached the journal: {leaked}"


async def test_preview_paths_register_provider_keys_before_decoder_factory(tmp_path):
    from copytrading_engine.execution.domain.sizing import RouteConnection
    from copytrading_engine.trading.domain.config import ProviderConfiguration

    values = ("historical-preview-key", "example-preview-key")

    sink = journal_sink(tmp_path / "diagnostics")
    telemetry = TradingTelemetry(sink=sink)
    source_event = RawMessage(
        schema_version=1,
        event_type="raw_message",
        source="discord",
        channel_id="123",
        id="999",
        timestamp=dt.datetime.now(dt.UTC) - dt.timedelta(minutes=10),
        text="ALERT: Bought AAPL at 200",
    )
    store = await SQLiteSourceStore.open(tmp_path / "application.db")
    await store.recovery_start(123, 1)
    await store.capture_recovery_page(123, [source_event], [], 999)
    await store.close()

    async def decoder_factory(name, config):
        key = config.api_key.get_secret_value()
        telemetry.record_payload(
            capture_kind="model_response",
            workflow_id=None,
            trace_id=None,
            destination_id=None,
            attempt=None,
            provider="anthropic",
            payload={"error": "preview provider echoed " + key},
        )
        return Decoder()

    runtime = TradingRuntime(
        tmp_path,
        factories=TradingFactories(decoder=decoder_factory),
        telemetry=telemetry,
    )
    profile = ProfileBuilder().build(
        ProfileDraft(
            guru_id="preview-guru",
            display_name="Preview Guru",
            prefix="ALERT:",
            playbook="",
            examples=(
                ProfileExample(
                    message="ALERT: Bought AAPL at 200",
                    expected_action="buy",
                    expected_symbol="AAPL",
                ),
            ),
            exit_basis="original_position",
        )
    )
    provider = ProviderConfiguration(name="anthropic", model="test-model")
    destinations = [RouteConnection(account_id="first", full_position_usd="100")]
    await runtime.profiles.evaluate_historical_profile(
        source_event.identity,
        profile,
        provider,
        SecretStr(values[0]),
        destinations,
    )
    await runtime.profiles.review_profile_examples(
        profile, provider, SecretStr(values[1]), destinations
    )
    assert sink.flush(timeout_seconds=5)
    journal = journal_text(tmp_path / "diagnostics")
    sink.close(timeout_seconds=5)

    leaked = [index for index, value in enumerate(values) if value in journal]
    assert not leaked, f"credential categories reached the journal: {leaked}"


async def test_invalid_account_path_or_missing_secret_never_opens_runtime(tmp_path):
    runtime = TradingRuntime(tmp_path)
    config = trading_configuration().model_dump(mode="json")
    config["accounts"][0]["id"] = "../escape"
    with pytest.raises(ValidationError, match=r"accounts\.0\.id"):
        TradingConfiguration.model_validate(config)
    invalid = trading_secrets().model_dump(mode="json")
    invalid["discord_token"] = ""
    secrets = TradingSecrets.model_validate(invalid)
    with pytest.raises(ValueError, match="Source and provider credentials are required"):
        await runtime.start(trading_configuration(), secrets)
    assert runtime.status().state == "paused"
    assert not (tmp_path / "accounts").exists()


async def test_restore_marker_blocks_trading_start_before_secret_registration(
    tmp_path, monkeypatch
):
    marker = tmp_path / ".restore-manual-disabled"
    marker.write_text("restore pending", encoding="utf-8")
    runtime = TradingRuntime(tmp_path, restore_gate_path=marker)
    registered = []
    monkeypatch.setattr(runtime, "_register_trading_secrets", registered.append)

    with pytest.raises(ValueError, match="restore reconciliation"):
        await runtime.start(trading_configuration(), trading_secrets())

    assert registered == []
    assert runtime.status().state == "paused"
    assert runtime._task is None
