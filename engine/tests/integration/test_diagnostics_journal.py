"""A real workflow leaves complete, correlated, redacted records in the local journal."""

import asyncio
import contextlib
import datetime as dt
import json
from decimal import Decimal
from pathlib import Path
from types import SimpleNamespace

import httpx2 as httpx
from openai import AsyncOpenAI

from copytrading_engine.diagnostics.telemetry.config import TelemetryConfig
from copytrading_engine.diagnostics.telemetry.local import LocalTelemetry
from copytrading_engine.execution.domain.sizing import DestinationTerms, RouteConnection
from copytrading_engine.parsing.providers.deepseek import build_decoder as build_deepseek_decoder
from copytrading_engine.parsing.providers.transport import DiagnosticHTTPTransport
from copytrading_engine.parsing.routes import Route
from copytrading_engine.parsing.sqlite import SQLiteExtractionStore
from copytrading_engine.parsing.worker import ParseWorker
from copytrading_engine.shared.correlation import current_workflow_attempt
from copytrading_engine.shared.model_providers import ProviderConfig
from copytrading_engine.sources.source import adapter_event, envelope
from copytrading_engine.trading.adapters.telemetry import TradingTelemetry
from copytrading_engine.trading.application.accounts import AccountUnavailable, SignalFanout
from copytrading_engine.trading.domain.config import TradingConfiguration, TradingSecrets
from copytrading_engine.trading.domain.profiles import ProfileBuilder, ProfileDraft
from copytrading_engine.trading.entrypoints.factories import TradingFactories
from copytrading_engine.trading.entrypoints.runtime import TradingRuntime

from ..diagnostics.telemetry.builders import journal_records, journal_text


async def test_a_workflow_journals_its_source_model_and_destination_records_redacted(
    tmp_path: Path,
) -> None:
    """Capture a source post, parse it, and deliver it to two accounts across a restart."""
    directory = tmp_path / "diagnostics"
    secret = "task6-capture-secret-67fa2c"
    provider_key = "task6-provider-key-a803e1"
    now = dt.datetime.now(dt.UTC)
    message = SimpleNamespace(
        content=f"Market commentary source-event-marker {secret}",
        id=90210,
        channel=SimpleNamespace(id=123),
        author=SimpleNamespace(id=99),
        created_at=now,
        embeds=[
            SimpleNamespace(
                title="Signal card",
                description="original embed evidence",
                fields=[SimpleNamespace(name="Symbol", value="AAPL", inline=False)],
            )
        ],
        attachments=[],
    )
    source_payload = adapter_event(message)
    assert "url" not in json.dumps(source_payload)
    source_raw = envelope(message)
    requests: list[httpx.Request] = []
    response_text = json.dumps(
        {"reading": {"kind": "commentary", "summary": "provider-response-marker"}}
    )

    def provider_handler(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        return httpx.Response(
            200,
            json={
                "id": "chat-task6",
                "object": "chat.completion",
                "created": 1,
                "model": "deepseek-flash",
                "choices": [
                    {
                        "index": 0,
                        "finish_reason": "stop",
                        "message": {"role": "assistant", "content": response_text},
                    }
                ],
                "usage": {"prompt_tokens": 10, "completion_tokens": 10, "total_tokens": 20},
            },
        )

    class Receiver:
        def __init__(self, failures: int = 0) -> None:
            self.failures = failures
            self.observed = []

        async def receive(self, delivery, at: dt.datetime) -> None:
            attempt = current_workflow_attempt()
            assert attempt is not None
            assert attempt.destination_id is not None
            self.observed.append(attempt)
            if self.failures:
                self.failures -= 1
                raise AccountUnavailable

    sink = LocalTelemetry(TelemetryConfig(journal_directory=directory))
    assert sink.register_secrets((secret, provider_key))
    observer = TradingTelemetry(sink=sink)
    client = AsyncOpenAI(
        api_key=provider_key,
        base_url="https://api.deepseek.com",
        max_retries=0,
        http_client=httpx.AsyncClient(
            transport=DiagnosticHTTPTransport(
                httpx.MockTransport(provider_handler), sink, provider="deepseek"
            )
        ),
    )
    decoder = build_deepseek_decoder(
        ProviderConfig(api_key=provider_key, model="deepseek-flash", timeout=20), client
    )
    database = tmp_path / "workflow.sqlite3"
    receivers = {"account-a": Receiver(failures=1), "account-b": Receiver()}
    revision = "c" * 64
    terms = tuple(
        DestinationTerms(
            connection=RouteConnection(
                account_id=account_id,
                full_position_usd=Decimal("100.00"),
            ),
            environment="paper",
            configuration_revision=revision,
        )
        for account_id in ("account-a", "account-b")
    )
    routes = {"discord:123:99": terms}
    stop = asyncio.Event()

    async def run_pipeline() -> tuple[str, str]:
        store = await SQLiteExtractionStore.open(database)
        try:
            await store.add(source_raw)
            job = await store.next(now)
            assert job is not None
            workflow_id, trace_id = job.workflow_id, job.trace_id
            sink.record_payload(
                capture_kind="source_event",
                workflow_id=workflow_id,
                trace_id=trace_id,
                destination_id=None,
                attempt=None,
                provider="other",
                payload=source_payload,
                status="complete",
            )
            worker = ParseWorker(
                store,
                decoder,
                {"discord:123:99": Route()},
                "deepseek-flash",
                observe=observer.model_span,
                observe_workflow=observer.workflow_span,
            )
            assert await worker.process_next(now)
            assert len(requests) == 1

            first_fanout = SignalFanout(
                store,
                routes,
                receivers,
                stop,
                observe_workflow=observer.workflow_span,
                observe_destination=observer.destination_span,
            )
            assert await first_fanout.deliver() == 0
            await store.close()

            store = await SQLiteExtractionStore.open(database)
            replayed_fanout = SignalFanout(
                store,
                routes,
                receivers,
                stop,
                observe_workflow=observer.workflow_span,
                observe_destination=observer.destination_span,
            )
            assert await replayed_fanout.deliver() == 1
            await store.close()
            await decoder.close()
            assert sink.flush(timeout_seconds=15)
            assert sink.snapshot().state == "healthy"
            return workflow_id, trace_id
        finally:
            with contextlib.suppress(Exception):
                await store.close()
            await decoder.close()

    try:
        workflow_id, trace_id = await run_pipeline()
    finally:
        sink.close(timeout_seconds=5)

    records = journal_records(directory)
    captures = {
        record["capture_kind"]: record
        for record in records
        if record["kind"] == "payload" and record["workflow_id"] == workflow_id
    }
    assert set(captures) == {"source_event", "model_request", "model_response"}
    assert all(capture["capture_status"] == "complete" for capture in captures.values())
    assert all(capture["trace_id"] == trace_id for capture in captures.values())
    source = json.dumps(captures["source_event"])
    assert "source-event-marker" in source
    assert "original embed evidence" in source
    assert "source-event-marker" in json.dumps(captures["model_request"])
    assert "provider-response-marker" in json.dumps(captures["model_response"])

    deliveries = [
        record
        for record in records
        if record["kind"] == "trading" and record["operation"] == "destination.receive"
    ]
    assert sorted((item["outcome"], item["attempt"]) for item in deliveries) == [
        ("raised", 1),
        ("returned", 1),
        ("returned", 2),
        ("returned", 2),
    ]
    observed = [attempt for receiver in receivers.values() for attempt in receiver.observed]
    assert [attempt.attempt for attempt in receivers["account-a"].observed] == [1, 2]
    assert [attempt.attempt for attempt in receivers["account-b"].observed] == [1, 2]
    assert {item["destination_id"] for item in deliveries} == {
        attempt.destination_id for attempt in observed
    }
    assert len({item["destination_id"] for item in deliveries}) == 2
    assert {item["workflow_id"] for item in deliveries} == {workflow_id}
    assert {item["trace_id"] for item in deliveries} == {trace_id}

    journal = journal_text(directory)
    for forbidden in (secret, provider_key, "cdn.discordapp.com"):
        assert forbidden not in journal


async def test_runtime_registered_credentials_never_reach_the_journal(
    tmp_path: Path,
) -> None:
    directory = tmp_path / "diagnostics"
    credential_values = (
        ("source", "task6-runtime-source-credential-5be114"),
        ("provider", "task6-runtime-provider-credential-c81f22"),
        ("broker key", "task6-runtime-broker-key-a78de3"),
        ("broker secret", "task6-runtime-broker-secret-93b2fa"),
        ("notification", "task6-runtime-notification-credential-d0367a"),
    )
    marker = "runtime-source-event-marker"
    failure_marker = "runtime-provider-failure-marker"
    now = dt.datetime.now(dt.UTC)
    message = SimpleNamespace(
        content="ALERT: " + marker + " " + " ".join(value for _, value in credential_values),
        id=90555,
        channel=SimpleNamespace(id=123),
        author=SimpleNamespace(id=99),
        created_at=now,
        embeds=[],
        attachments=[],
    )
    provider_requests: list[httpx.Request] = []
    source_request_observed = asyncio.Event()

    def provider_handler(request: httpx.Request) -> httpx.Response:
        provider_requests.append(request)
        if marker.encode("utf-8") in request.content:
            source_request_observed.set()
        return httpx.Response(
            401,
            json={
                "error": {
                    "message": f"{failure_marker} echoed {credential_values[1][1]}",
                    "type": "invalid_api_key",
                    "param": None,
                    "code": "invalid_api_key",
                }
            },
            request=request,
        )

    sink = LocalTelemetry(TelemetryConfig(journal_directory=directory))
    observer = TradingTelemetry(sink=sink)
    secrets = TradingSecrets.model_validate(
        {
            "discord_token": credential_values[0][1],
            "provider_api_key": credential_values[1][1],
            "brokers": [
                {
                    "account_id": "account-a",
                    "key": credential_values[2][1],
                    "secret": credential_values[3][1],
                }
            ],
            "notification_token": credential_values[4][1],
        }
    )
    profile = ProfileBuilder().build(
        ProfileDraft(
            guru_id="runtime-capture",
            display_name="Runtime Capture",
            playbook="",
            examples=(),
        )
    )
    configuration = TradingConfiguration.model_validate(
        {
            "version": 8,
            "source": {"channel_ids": ["123"]},
            "provider": {"name": "deepseek", "model": "deepseek-flash"},
            "accounts": [{"id": "account-a", "environment": "paper"}],
            "profiles": [profile.model_dump(mode="json")],
            "routes": [
                {
                    "channel_id": "123",
                    "author_id": None,
                    "guru_id": profile.guru_id,
                    "profile_revision": profile.profile_revision,
                    "connections": [{"account_id": "account-a", "full_position_usd": "600"}],
                }
            ],
        }
    )

    class Owner:
        async def account_status(self):
            from copytrading_engine.execution.application.ports import AccountRuntimeView

            return AccountRuntimeView(
                "disabled", "manual", "disabled", "ready", None, "ready", None
            )

        async def cycle(self, now, *, halted):
            del now, halted
            return SimpleNamespace(ledger=SimpleNamespace(has_outstanding_work=False))

        async def receive(self, delivery, now):
            del delivery, now
            raise AssertionError("A provider failure must not produce a destination delivery")

        def request_stop(self):
            return None

        async def close(self):
            return None

    class Session:
        ready = True

        def __init__(self, source):
            self.source = source
            self.capture_task: asyncio.Task[None] | None = None

        def start(self, token: str) -> None:
            if not token:
                raise AssertionError("runtime did not pass the configured source credential")
            from copytrading_engine.sources.session import capture_message

            self.capture_task = asyncio.create_task(capture_message(message, self.source))

        async def ensure_running(self):
            if self.capture_task is not None:
                await self.capture_task

        async def forward_if_ready(self, forwarder):
            await forwarder.flush()

        async def close(self):
            if self.capture_task is not None:
                await self.capture_task

    async def decoder_factory(name: str, provider_config: ProviderConfig):
        assert name == "deepseek"
        client = AsyncOpenAI(
            api_key=provider_config.api_key.get_secret_value(),
            base_url="https://api.deepseek.com",
            max_retries=0,
            http_client=httpx.AsyncClient(
                transport=DiagnosticHTTPTransport(
                    httpx.MockTransport(provider_handler), sink, provider="deepseek"
                ),
                follow_redirects=False,
            ),
        )
        return build_deepseek_decoder(provider_config, client)

    factories = TradingFactories(
        owner=lambda *args: asyncio.sleep(0, result=Owner()),
        decoder=decoder_factory,
        session=lambda source, channels, authors, stop, report_failure: Session(source),
    )
    runtime = TradingRuntime(
        tmp_path / "runtime",
        factories=factories,
        telemetry=observer,
    )
    runtime_stopped = False
    sink_closed = False
    try:
        await runtime.start(configuration, secrets)
        deadline = asyncio.get_running_loop().time() + 15
        while asyncio.get_running_loop().time() < deadline:
            health = sink.capture_health()
            request_count = len(provider_requests)
            if (
                health.source_events >= 1
                and source_request_observed.is_set()
                and health.model_requests >= request_count
                and health.model_responses >= request_count
            ):
                break
            await asyncio.sleep(0.05)
        assert health.source_events >= 1
        assert source_request_observed.is_set(), "source message never reached the model provider"
        assert provider_requests
        assert health.model_requests >= len(provider_requests)
        assert health.model_responses >= len(provider_requests)
        await runtime.shutdown()
        runtime_stopped = True
        assert sink.flush(timeout_seconds=15)
        assert sink.snapshot().state == "healthy"
        sink.close(timeout_seconds=5)
        sink_closed = True
    finally:
        if not runtime_stopped:
            await runtime.shutdown()
        if not sink_closed:
            sink.close(timeout_seconds=5)

    records = [record for record in journal_records(directory) if record["kind"] == "payload"]
    sources = [
        record
        for record in records
        if record["capture_kind"] == "source_event" and marker in json.dumps(record)
    ]
    assert sources
    workflow_ids = {record["workflow_id"] for record in sources}
    requests = [
        record
        for record in records
        if record["capture_kind"] == "model_request"
        and marker in json.dumps(record)
        and record["workflow_id"] in workflow_ids
        and record["trace_id"]
    ]
    assert requests
    request_identities = {(record["workflow_id"], record["trace_id"]) for record in requests}
    assert any(
        record["capture_kind"] == "model_response"
        and failure_marker in json.dumps(record)
        and "401" in json.dumps(record)
        and (record["workflow_id"], record["trace_id"]) in request_identities
        for record in records
    )
    journal = journal_text(directory)
    leaked = [label for label, value in credential_values if value in journal]
    assert not leaked, f"runtime credential categories reached the journal: {leaked}"
