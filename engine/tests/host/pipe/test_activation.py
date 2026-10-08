"""Pipe activation requires fresh capability checks for the exact draft and secrets."""

import json
from pathlib import Path
from uuid import uuid4

from copytrading_engine.execution.domain.sizing import RouteConnection
from copytrading_engine.host.pipe.server import PipeServer
from copytrading_engine.host.self_test.parser import SelfTestParser
from copytrading_engine.host.self_test.service import SelfTestService
from copytrading_engine.host.status import EngineQueries
from copytrading_engine.shared.owner_facing import OwnerFacingError
from copytrading_engine.trading.adapters.activation import TradingActivationStatus
from copytrading_engine.trading.adapters.capabilities import (
    CapabilityCheck,
    TradingCapabilityReport,
)
from copytrading_engine.trading.domain.config import TradingConfiguration
from copytrading_engine.trading.domain.profiles import (
    LearnedPlaybook,
    ProfileBuilder,
    ProfileDraft,
    ProfileExampleReview,
    ProfileReplay,
    ReplayedPost,
)
from copytrading_engine.trading.domain.status import TradingStatus

from .builders import request_line, services


def _configuration():
    profile = ProfileBuilder().build(
        ProfileDraft(
            guru_id="stable-guru",
            display_name="Stable Guru",
            playbook="",
            examples=(),
        )
    )
    return TradingConfiguration.model_validate(
        {
            "version": 8,
            "source": {"channel_ids": ["123"]},
            "provider": {"name": "deepseek", "model": "test-model"},
            "accounts": [{"id": "paper", "environment": "paper"}],
            "profiles": [profile.model_dump(mode="json")],
            "routes": [
                {
                    "channel_id": "123",
                    "author_id": None,
                    "guru_id": profile.guru_id,
                    "profile_revision": profile.profile_revision,
                    "connections": [{"account_id": "paper", "full_position_usd": "600"}],
                }
            ],
        }
    )


def _secret_payload(provider_key: str = "provider-key"):
    return {
        "discord_token": "source-token",
        "provider_api_key": provider_key,
        "brokers": [{"account_id": "paper", "key": "broker-key", "secret": "broker-secret"}],
    }


class _Trading:
    def __init__(self):
        self.starts = 0
        self.connection_checks = []
        self.evaluations = []
        self.example_reviews = []
        self.learnings = []
        self.replays = []
        self.learning_error: str | None = None
        self.activation_id = None
        self.revision = None

    def status(self):
        return TradingStatus()

    async def validate(self, configuration, secrets):
        return TradingCapabilityReport(
            configuration_revision=configuration.revision(),
            activatable=True,
            checks=(
                CapabilityCheck(name="source", state="ready", adapter="fake"),
                CapabilityCheck(name="model", state="ready", adapter="fake"),
                CapabilityCheck(name="broker", state="ready", subject="paper", adapter="fake"),
            ),
            cost_notice="test notice",
        )

    async def check_connection(self, connection):
        self.connection_checks.append(connection)
        return CapabilityCheck(name=connection.kind, state="ready", adapter="fake")

    async def start(self, configuration, secrets, activation_id):
        self.starts += 1
        self.activation_id = activation_id
        self.revision = configuration.revision()
        return TradingStatus(state="starting", configured_accounts=1)

    def activation_status(self, activation_id):
        return TradingActivationStatus(
            requested_activation_id=activation_id,
            activation_id=self.activation_id,
            candidate_revision=self.revision,
            committed_revision=None,
            phase="starting" if activation_id == self.activation_id else "not_found",
            runtime_state="starting" if activation_id == self.activation_id else "paused",
        )

    async def evaluate_historical_profile(
        self, source_id, profile, provider, provider_api_key, destinations
    ):
        self.evaluations.append(
            (
                source_id,
                profile.profile_revision,
                provider.name,
                provider_api_key.get_secret_value(),
                destinations,
            )
        )

        class Evaluation:
            def model_dump(self, *, mode):
                assert mode == "json"
                return {
                    "message_identity": source_id,
                    "guru_id": profile.guru_id,
                    "profile_revision": profile.profile_revision,
                    "provider": provider.name,
                    "model": provider.model,
                    "simulated": True,
                    "no_order": True,
                    "cost_notice": "Model evaluation may incur provider charges.",
                }

        return Evaluation()

    async def replay_posts(
        self,
        channel_id,
        author_id,
        discord_token,
        provider,
        provider_api_key,
        profile,
        destinations,
    ):
        self.replays.append(
            (channel_id, profile.guru_id, tuple(d.account_id for d in destinations))
        )
        return ProfileReplay(
            posts=(
                ReplayedPost(
                    text="赵哥-股票：今天大盘不错",  # noqa: RUF001 - the guru's real fullwidth colon
                    decision="ignore",
                    reason="No trade action",
                    reading=None,
                    instructions=(),
                    suggested=(),
                    destinations=(),
                ),
            ),
            provider=provider.name,
            model=provider.model,
        )

    async def learn_playbook(
        self, channel_id, author_id, discord_token, provider, provider_api_key
    ):
        self.learnings.append(
            (
                channel_id,
                author_id,
                discord_token.get_secret_value(),
                provider.name,
                provider_api_key.get_secret_value(),
            )
        )
        if self.learning_error is not None:
            raise OwnerFacingError(self.learning_error)
        return LearnedPlaybook(
            posts_read=3,
            playbook="加 means buy\n英伟达 means NVDA",
            summary="Buys are written price first.",
            provider=provider.name,
            model=provider.model,
        )

    async def review_profile_examples(self, profile, provider, provider_api_key, destinations):
        self.example_reviews.append(
            (
                profile.profile_revision,
                provider.name,
                provider_api_key.get_secret_value(),
                destinations,
            )
        )
        return ProfileExampleReview(
            guru_id=profile.guru_id,
            profile_revision=profile.profile_revision,
            provider=provider.name,
            model=provider.model,
            examples=(),
            automatic_activation_allowed=True,
        )


async def test_historical_evaluation_has_typed_no_order_pipe_operation(store: Path):
    trading = _Trading()
    queries = EngineQueries(store, store.installation.instance_id)
    server = PipeServer(SelfTestService(store, SelfTestParser()), queries, services(trading))
    profile = _configuration().profiles[0]
    destination = {"account_id": "paper", "full_position_usd": "100"}
    request = request_line(
        "evaluate_historical_profile",
        "evaluate-historical",
        source_id="discord:123:456",
        profile=profile.model_dump(mode="json"),
        provider={"name": "deepseek", "model": "test-model"},
        provider_api_key="private-provider-key",
        destinations=[destination],
    )

    response = json.loads(await server.handle_line(request))

    assert response["ok"]["type"] == "profile_evaluation"
    result = response["ok"]["evaluation"]
    assert result["simulated"] is True
    assert result["no_order"] is True
    assert "provider charges" in result["cost_notice"]
    assert trading.evaluations == [
        (
            "discord:123:456",
            profile.profile_revision,
            "deepseek",
            "private-provider-key",
            [RouteConnection(account_id="paper", full_position_usd="100")],
        )
    ]
    assert trading.starts == 0
    status = await queries.status("running")
    assert status.accepted == status.pending == status.completed == 0

    with_extra_order_field = request_line(
        "evaluate_historical_profile",
        "not-an-order",
        source_id="discord:123:456",
        profile=profile.model_dump(mode="json"),
        provider={"name": "deepseek", "model": "test-model"},
        provider_api_key="private-provider-key",
        destinations=[destination],
        command={"command_id": "bad", "text": "buy", "destination_ids": ["paper"]},
    )
    rejected = json.loads(await server.handle_line(with_extra_order_field))
    assert rejected["error"]["code"] == "invalid_request"
    assert len(trading.evaluations) == 1


async def test_profile_example_review_pipe_is_typed_and_cannot_submit_work(store: Path):
    trading = _Trading()
    server = PipeServer(
        SelfTestService(store, SelfTestParser()),
        EngineQueries(store, store.installation.instance_id),
        services(trading),
    )
    profile = _configuration().profiles[0]
    request = request_line(
        "review_profile_examples",
        "review-examples",
        profile=profile.model_dump(mode="json"),
        provider={"name": "deepseek", "model": "test-model"},
        provider_api_key="private-provider-key",
        destinations=[{"account_id": "paper", "full_position_usd": "100"}],
    )

    response = json.loads(await server.handle_line(request))

    assert response["ok"]["type"] == "profile_example_review"
    result = response["ok"]["review"]
    assert result["simulated"] is True
    assert result["no_order"] is True
    assert result["automatic_activation_allowed"] is True
    assert "provider charges may apply" in result["cost_notice"]
    assert trading.example_reviews == [
        (
            profile.profile_revision,
            "deepseek",
            "private-provider-key",
            [RouteConnection(account_id="paper", full_position_usd="100")],
        )
    ]
    assert trading.starts == 0
    status = await EngineQueries(store, store.installation.instance_id).status("running")
    assert status.accepted == status.pending == status.completed == 0

    with_order = request_line(
        "review_profile_examples",
        "review-examples-with-command",
        profile=profile.model_dump(mode="json"),
        provider={"name": "deepseek", "model": "test-model"},
        provider_api_key="private-provider-key",
        destinations=[],
        command={"command_id": "bad", "text": "buy", "destination_ids": ["paper"]},
    )
    rejected = json.loads(await server.handle_line(with_order))
    assert rejected["error"]["code"] == "invalid_request"
    assert len(trading.example_reviews) == 1


async def test_activation_grant_is_required_exact_and_single_use(store: Path):
    trading = _Trading()
    server = PipeServer(
        SelfTestService(store, SelfTestParser()),
        EngineQueries(store, store.installation.instance_id),
        services(trading),
    )
    configuration = _configuration()
    payload = _secret_payload()
    raw_configuration = configuration.model_dump(mode="json")
    activation_id = str(uuid4())

    skipped_validation = json.loads(
        await server.handle_line(
            request_line(
                "start_trading",
                "start-before-validation",
                configuration=raw_configuration,
                secrets=payload,
                validation_token="unverified",
                activation_id=activation_id,
            )
        )
    )
    assert skipped_validation["error"]["code"] == "invalid_request"
    assert trading.starts == 0

    validation = json.loads(
        await server.handle_line(
            request_line(
                "validate_trading",
                "validate-draft",
                configuration=raw_configuration,
                secrets=payload,
            )
        )
    )
    token = validation["ok"]["activation_token"]
    assert validation["ok"]["report"]["activatable"] is True
    assert "source-token" not in json.dumps(validation)

    changed_secret = json.loads(
        await server.handle_line(
            request_line(
                "start_trading",
                "start-changed-secret",
                configuration=raw_configuration,
                secrets=_secret_payload("different-provider-key"),
                validation_token=token,
                activation_id=activation_id,
            )
        )
    )
    assert changed_secret["error"]["code"] == "invalid_request"
    assert trading.starts == 0

    validation = json.loads(
        await server.handle_line(
            request_line(
                "validate_trading",
                "validate-again",
                configuration=raw_configuration,
                secrets=payload,
            )
        )
    )
    token = validation["ok"]["activation_token"]
    started = json.loads(
        await server.handle_line(
            request_line(
                "start_trading",
                "start-verified",
                configuration=raw_configuration,
                secrets=payload,
                validation_token=token,
                activation_id=activation_id,
            )
        )
    )
    assert started["ok"]["type"] == "trading_status"
    assert trading.starts == 1
    activation = json.loads(
        await server.handle_line(
            request_line(
                "get_trading_activation",
                "activation-status",
                activation_id=activation_id,
            )
        )
    )
    assert activation["ok"]["type"] == "trading_activation"
    assert activation["ok"]["activation"]["activation_id"] == activation_id
    assert activation["ok"]["activation"]["candidate_revision"] == configuration.revision()

    replayed = json.loads(
        await server.handle_line(
            request_line(
                "start_trading",
                "replay-validation",
                configuration=raw_configuration,
                secrets=payload,
                validation_token=token,
                activation_id=activation_id,
            )
        )
    )
    assert replayed["error"]["code"] == "invalid_request"
    assert trading.starts == 1


async def test_learn_playbook_pipe_returns_a_draft_and_never_echoes_tokens(store: Path):
    trading = _Trading()
    server = PipeServer(
        SelfTestService(store, SelfTestParser()),
        EngineQueries(store, store.installation.instance_id),
        services(trading),
    )
    request = request_line(
        "learn_guru_playbook",
        "learn",
        channel_id="1517754775674949742",
        discord_token="private-discord-token",
        provider={"name": "deepseek", "model": "test-model"},
        provider_api_key="private-provider-key",
    )

    raw = (await server.handle_line(request)).decode()
    response = json.loads(raw)

    assert response["ok"]["type"] == "learned_playbook"
    draft = response["ok"]["playbook"]
    assert draft["playbook"] == "加 means buy\n英伟达 means NVDA"
    assert "private-discord-token" not in raw
    assert "private-provider-key" not in raw
    assert trading.learnings == [
        (
            "1517754775674949742",
            None,
            "private-discord-token",
            "deepseek",
            "private-provider-key",
        )
    ]

    trading.learning_error = "Discord refused to show this channel's history."
    failed = json.loads(await server.handle_line(request))
    assert "Discord refused" in json.dumps(failed)
    assert "ok" not in failed or failed.get("ok") is None

    bad_channel = request_line(
        "learn_guru_playbook",
        "learn-bad",
        channel_id="not-a-channel",
        discord_token="private-discord-token",
        provider={"name": "deepseek", "model": "test-model"},
        provider_api_key="private-provider-key",
    )
    rejected = (await server.handle_line(bad_channel)).decode()
    assert "private-discord-token" not in rejected
    assert len(trading.learnings) == 2


async def test_one_connection_is_checked_without_touching_the_start_grant(store: Path):
    trading = _Trading()
    server = PipeServer(
        SelfTestService(store, SelfTestParser()),
        EngineQueries(store, store.installation.instance_id),
        services(trading),
    )
    configuration = _configuration().model_dump(mode="json")
    validation = json.loads(
        await server.handle_line(
            request_line(
                "validate_trading",
                "validate-draft",
                configuration=configuration,
                secrets=_secret_payload(),
            )
        )
    )

    checked = json.loads(
        await server.handle_line(
            request_line(
                "check_connection",
                "check-model",
                connection={
                    "kind": "model",
                    "provider": {"name": "deepseek", "model": "test-model"},
                    "api_key": "private-provider-key",
                },
            )
        )
    )

    assert checked["ok"] == {
        "type": "connection_check",
        "check": {
            "name": "model",
            "state": "ready",
            "subject": None,
            "environment": None,
            "identity": None,
            "adapter": "fake",
            "reason_code": None,
            "suggestion": None,
        },
    }
    assert "private-provider-key" not in json.dumps(checked)
    assert [check.kind for check in trading.connection_checks] == ["model"]
    started = json.loads(
        await server.handle_line(
            request_line(
                "start_trading",
                "start-after-check",
                configuration=configuration,
                secrets=_secret_payload(),
                validation_token=validation["ok"]["activation_token"],
                activation_id=str(uuid4()),
            )
        )
    )
    assert "ok" in started
    assert trading.starts == 1


async def test_a_connection_of_an_unknown_kind_is_refused(store: Path):
    trading = _Trading()
    server = PipeServer(
        SelfTestService(store, SelfTestParser()),
        EngineQueries(store, store.installation.instance_id),
        services(trading),
    )

    refused = json.loads(
        await server.handle_line(
            request_line("check_connection", "check-x", connection={"kind": "fax", "token": "t"})
        )
    )

    assert refused["error"]["code"] == "invalid_request"
    assert trading.connection_checks == []


async def test_replay_pipe_reads_recent_posts_with_the_draft_and_never_echoes_tokens(store: Path):
    trading = _Trading()
    server = PipeServer(
        SelfTestService(store, SelfTestParser()),
        EngineQueries(store, store.installation.instance_id),
        services(trading),
    )
    profile = _configuration().profiles[0].model_copy()
    request = request_line(
        "replay_guru_posts",
        "replay",
        channel_id="1517754775674949742",
        discord_token="private-discord-token",
        provider={"name": "deepseek", "model": "test-model"},
        provider_api_key="private-provider-key",
        profile=profile.model_dump(mode="json"),
        destinations=[{"account_id": "paper-account", "full_position_usd": "600.00"}],
    )

    raw = (await server.handle_line(request)).decode()
    response = json.loads(raw)

    assert response["ok"]["type"] == "guru_replay"
    assert [post["decision"] for post in response["ok"]["replay"]["posts"]] == ["ignore"]
    assert "private-discord-token" not in raw
    assert "private-provider-key" not in raw
    assert trading.replays == [("1517754775674949742", profile.guru_id, ("paper-account",))]
