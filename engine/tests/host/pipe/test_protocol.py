"""The pipe answers each request with one bounded line and never activates a restore."""

import asyncio
import datetime as dt
import json
import sqlite3
from contextlib import asynccontextmanager
from datetime import UTC, datetime
from pathlib import Path
from typing import get_args
from uuid import UUID, uuid4

import pytest

from copytrading_engine.backup.manifest import (
    BackupManifest,
    BackupManifestError,
    BackupMember,
    RestorePreview,
)
from copytrading_engine.backup.schema_catalog import (
    APPLICATION_COMPONENTS,
    current_operational_schema_catalog,
)
from copytrading_engine.backup.service import BackupRestoreService
from copytrading_engine.execution.adapters.sqlite_ledger import current_execution_snapshot_schema
from copytrading_engine.execution.domain.lifecycle import (
    AccountControlCommand,
    AccountControlResult,
)
from copytrading_engine.execution.domain.market import EquityHistory, HistoryWindow
from copytrading_engine.execution.domain.ownership import (
    OwnershipResolution,
    OwnershipResolutionRequest,
)
from copytrading_engine.execution.presentation.account_feed import AccountFeedPage
from copytrading_engine.execution.presentation.operator_views import (
    AccountOverviewPage,
)
from copytrading_engine.host.installation import Installation
from copytrading_engine.host.pipe.requests import RequestType
from copytrading_engine.host.pipe.server import MAX_REQUEST_LINE_BYTES, PipeServer
from copytrading_engine.host.self_test.parser import SelfTestParser
from copytrading_engine.host.self_test.service import SelfTestService
from copytrading_engine.host.self_test.store import SQLiteSelfTestStore
from copytrading_engine.host.status import EngineQueries
from copytrading_engine.shared.sqlite import ensure_schema
from copytrading_engine.trading.presentation.operator_models import SourceActivityPage

from ...contracts import CONTRACTS, contract
from .builders import decode, request_line, services


def _server(store: SQLiteSelfTestStore) -> PipeServer:
    service = SelfTestService(store, SelfTestParser())
    return PipeServer(service, EngineQueries(store, store.installation.instance_id))


class _OperatorControl:
    async def resolve_ownership(
        self, local_account_id: str, request: OwnershipResolutionRequest
    ) -> OwnershipResolution:
        assert local_account_id == "paper"
        fixture = contract("ownership-resolution-response.json")
        result = OwnershipResolution.model_validate_json(json.dumps(fixture["ok"]["resolution"]))
        assert request == result.request
        return result

    async def control_account(self, command: AccountControlCommand) -> AccountControlResult:
        fixture = contract("account-control-response.json")
        result = AccountControlResult.model_validate_json(json.dumps(fixture["ok"]["control"]))
        assert command == result.command
        return result

    async def account_overviews(
        self, before_account_id: str | None, limit: int
    ) -> AccountOverviewPage:
        assert before_account_id == "gamma"
        assert limit == 12
        fixture = contract("account-overviews-response.json")
        return AccountOverviewPage.model_validate_json(json.dumps(fixture["ok"]["accounts"]))

    async def source_activity(self, before_seq: int | None, limit: int) -> SourceActivityPage:
        assert before_seq is None
        assert limit == 50
        fixture = contract("source-activity-response.json")
        return SourceActivityPage.model_validate_json(json.dumps(fixture["ok"]["activity"]))

    async def account_feed(
        self, account_id: str, before_seq: int | None, limit: int
    ) -> AccountFeedPage:
        assert account_id == "paper"
        assert before_seq is None
        assert limit == 50
        fixture = contract("account-feed-response.json")
        return AccountFeedPage.model_validate_json(json.dumps(fixture["ok"]["feed"]))

    async def equity_history(self, account_id: str, window: HistoryWindow) -> EquityHistory | None:
        if account_id != "paper":
            raise KeyError(account_id)
        assert window == HistoryWindow(range="day", day=dt.date(2026, 9, 26))
        fixture = contract("equity-history-response.json")
        return EquityHistory.model_validate_json(json.dumps(fixture["ok"]["history"]))


class _BackupRestore:
    def __init__(self, staging_root: Path) -> None:
        self.staging_root = staging_root
        self.destination: Path | None = None
        self.archive: Path | None = None
        self.manifest = BackupManifest(
            format_version=1,
            created_at=datetime(2026, 9, 27, tzinfo=UTC),
            installation_id=str(uuid4()),
            environment_ids=("paper:acct-a",),
            members=(
                BackupMember("application.db", 40, "a" * 64, "sqlite:application:2;components="),
            ),
        )

    async def create_backup(self, destination: Path) -> BackupManifest:
        self.destination = destination
        return self.manifest

    def stage_restore(self, archive: Path, staging_root: Path):
        self.archive = archive
        assert staging_root == self.staging_root
        preview = RestorePreview(
            self.manifest,
            matches_installation=False,
            account_ids=("acct-a",),
            credential_references=(str(uuid4()),),
        )
        return staging_root / "restore-test", preview


async def test_account_operator_contract_fixtures_and_exact_request_schema(store):
    server = PipeServer(
        SelfTestService(store, SelfTestParser()),
        EngineQueries(store, store.installation.instance_id),
        services(_OperatorControl()),
    )
    control = decode(
        await server.handle_line((CONTRACTS / "account-control-request.json").read_bytes())
    )
    assert control == contract("account-control-response.json")
    resolution = decode(
        await server.handle_line((CONTRACTS / "ownership-resolution-request.json").read_bytes())
    )
    assert resolution == json.loads((CONTRACTS / "ownership-resolution-response.json").read_text())
    accounts = decode(
        await server.handle_line((CONTRACTS / "get-accounts-page-request.json").read_bytes())
    )
    assert accounts == contract("account-overviews-response.json")
    activity = decode(await server.handle_line(request_line("get_source_activity", "req-activity")))
    assert activity == contract("source-activity-response.json")
    feed = decode(
        await server.handle_line(request_line("get_account_feed", "req-feed", account_id="paper"))
    )
    assert feed == contract("account-feed-response.json")
    history = decode(
        await server.handle_line(
            request_line(
                "get_equity_history",
                "req-history",
                account_id="paper",
                window={"range": "day", "day": "2026-09-26"},
            )
        )
    )
    assert history == contract("equity-history-response.json")
    missing = request_line(
        "get_equity_history", "missing", account_id="other", window={"range": "day"}
    )
    assert decode(await server.handle_line(missing))["error"] == {"code": "not_found"}
    for invalid in (
        request_line("get_accounts", "bad", limit=True),
        request_line("get_accounts", "bad", before_account_id=""),
        request_line("get_accounts", "bad", before_account_id="a" * 65),
        request_line("get_source_activity", "bad", limit=True),
        request_line("get_account_feed", "bad", account_id="paper", before_seq=0),
        request_line(
            "get_equity_history",
            "bad",
            account_id="paper",
            window={"range": "week", "day": "2026-09-26"},
        ),
        request_line("get_equity_history", "bad", account_id="paper", window={"range": "all"}),
        request_line(
            "resolve_ownership", "bad", account_id="paper", resolution={"incident_id": "x"}
        ),
        request_line(
            "control_account",
            "bad",
            command={"command_id": "x", "account_id": "paper", "action": "pause", "extra": 1},
        ),
    ):
        assert decode(await server.handle_line(invalid))["error"] == {"code": "invalid_request"}


async def test_backup_and_restore_preview_ipc_are_bounded_and_never_activate(store, tmp_path):
    backup_service = _BackupRestore(tmp_path / ".restore-staging")
    server = PipeServer(
        SelfTestService(store, SelfTestParser()),
        EngineQueries(store, store.installation.instance_id),
        backup_restore=backup_service,
    )
    destination = tmp_path / "user-backup.zip"
    created = decode(
        await server.handle_line(
            request_line("create_backup", "req-backup", destination=str(destination))
        )
    )
    assert created["ok"]["type"] == "backup"
    assert created["ok"]["manifest"]["environment_ids"] == ["paper:acct-a"]
    assert backup_service.destination == destination

    archive = tmp_path / "old-backup.zip"
    previewed = decode(
        await server.handle_line(
            request_line("preview_restore", "req-restore-preview", archive_path=str(archive))
        )
    )
    assert previewed["ok"]["type"] == "restore_preview"
    assert previewed["ok"]["preview"]["matches_installation"] is False
    assert previewed["ok"]["preview"]["credential_references"]
    assert previewed["ok"]["preview"]["staging_id"] == "restore-test"
    assert backup_service.archive == archive

    assert decode(
        await server.handle_line(
            request_line("create_backup", "req-relative", destination="backup.zip")
        )
    ) == {
        "version": 1,
        "request_id": "req-relative",
        "error": {"code": "invalid_request"},
    }
    oversized = request_line("preview_restore", "req-long", archive_path="x" * 4097)
    assert decode(await server.handle_line(oversized))["error"] == {"code": "invalid_request"}


async def test_prepare_restore_candidate_ipc_uses_durable_backup_restore_service(tmp_path):
    installation_id = str(uuid4())
    owner = tmp_path / "CopyTrading"
    generation = owner / "generations" / str(uuid4())
    generation.mkdir(parents=True)
    (owner / "installation-id").write_text(installation_id + "\n", encoding="ascii")
    (owner / "active-generation").write_text(generation.name + "\n", encoding="ascii")

    @asynccontextmanager
    async def fence():
        yield

    application_database = generation / "application.db"
    with (
        Installation(application_database, instance_id=installation_id) as installation,
        SQLiteSelfTestStore(installation),
    ):
        pass
    connection = sqlite3.connect(application_database)
    try:
        for component in APPLICATION_COMPONENTS:
            ensure_schema(connection, component)
        connection.commit()
    finally:
        connection.close()
    backup_restore = BackupRestoreService(
        generation,
        lambda: fence(),
        schema_catalog=current_operational_schema_catalog,
        snapshot_schema=current_execution_snapshot_schema,
        owner_support_directory=owner,
    )
    archive = tmp_path / "selected-backup.zip"
    await backup_restore.create_backup(archive)

    with (
        Installation(generation / "application.db", instance_id=installation_id) as installation,
        SQLiteSelfTestStore(installation) as store,
    ):
        server = PipeServer(
            SelfTestService(store, SelfTestParser()),
            EngineQueries(store, store.installation.instance_id),
            backup_restore=backup_restore,
        )
        previewed = decode(
            await server.handle_line(
                request_line("preview_restore", "req-preview", archive_path=str(archive))
            )
        )
        staging_id = previewed["ok"]["preview"]["staging_id"]
        prepared = decode(
            await server.handle_line(
                request_line(
                    "prepare_restore_candidate",
                    "req-prepare",
                    staging_id=staging_id,
                )
            )
        )
        assert "ok" in prepared, prepared
        assert prepared["ok"]["type"] == "restore_candidate"
        candidate_id = prepared["ok"]["candidate_id"]
        assert candidate_id == str(UUID(candidate_id))
        assert (owner / "generations" / candidate_id).is_dir()
        assert (owner / ".restore-manual-disabled").is_file()
        assert (owner / "active-generation").read_text(encoding="ascii").strip() == generation.name
        pending = decode(
            await server.handle_line(request_line("restore_candidate_status", "req-status"))
        )
        assert pending["ok"]["candidate"]["candidate_id"] == candidate_id
        assert pending["ok"]["candidate"]["candidate_valid"] is True
        aborted = decode(
            await server.handle_line(
                request_line(
                    "abort_restore_candidate",
                    "req-abort",
                    candidate_id=candidate_id,
                )
            )
        )
        assert aborted["ok"] == {"type": "restore_aborted", "candidate_id": candidate_id}
        assert not (owner / "generations" / candidate_id).exists()
        assert not (owner / ".restore-manual-disabled").exists()


async def test_gated_restore_preflight_token_completes_and_exits_without_recovery(store):
    from copytrading_engine.execution.application.restore_preflight import RestorePreflightResult

    candidate_id = str(uuid4())
    events: list[object] = []
    key = "restore-key-must-not-echo"
    secret = "restore-secret-must-not-echo"

    class Trading:
        def register_restore_secrets(self, values: tuple[str, ...]) -> None:
            assert values == (key, secret)
            events.append("secrets-registered")

        async def pause(self):
            raise AssertionError("gated bootstrap must not start or pause trading")

    class Preflight:
        def preflight_restore_candidate(self, requested_id, credentials):
            assert events == ["secrets-registered"]
            assert requested_id == candidate_id
            assert len(credentials) == 1
            assert credentials[0].key.get_secret_value() == key
            assert credentials[0].secret.get_secret_value() == secret
            events.append("preflight")
            return RestorePreflightResult(candidate_id, 1, ())

    class CandidateActivation:
        def complete_restore_candidate(self, requested_id):
            assert events == ["secrets-registered", "preflight"]
            assert requested_id == candidate_id
            events.append("completed")

    class NoPendingWork:
        async def process_pending(self, *, max_items):
            raise AssertionError("gated bootstrap must not recover archived work")

    server = PipeServer(
        NoPendingWork(),
        EngineQueries(store, store.installation.instance_id),
        trading=services(Trading()),
        backup_restore=CandidateActivation(),
        restore_preflight=Preflight(),
        restore_gated=True,
    )
    blocked = decode(
        await server.handle_line(
            request_line(
                "submit_self_test",
                "req-blocked",
                command={
                    "command_id": "must-not-run",
                    "text": "Bought AAPL 1/6 at 200",
                    "destination_ids": ["self-test-a"],
                },
            )
        )
    )
    assert blocked["error"] == {"code": "unavailable"}
    preflight_line = await server.handle_line(
        request_line(
            "restore_preflight",
            "req-preflight",
            candidate_id=candidate_id,
            accounts=[
                {
                    "account_id": "acct-a",
                    "environment": "paper",
                    "key": key,
                    "secret": secret,
                }
            ],
        )
    )
    preflight = decode(preflight_line)["ok"]
    assert preflight["eligible"] is True
    assert preflight["completion_token"]
    assert key not in preflight_line.decode()
    assert secret not in preflight_line.decode()

    reader = asyncio.StreamReader()
    reader.feed_data(
        request_line(
            "complete_restore_candidate",
            "req-complete",
            candidate_id=candidate_id,
            completion_token=preflight["completion_token"],
        )
        + b"\n"
    )
    reader.feed_eof()
    writer = _CollectingWriter()
    await server.serve(reader, writer)
    assert len(writer.lines) == 1
    assert decode(writer.lines[0])["ok"] == {
        "type": "restore_activated",
        "candidate_id": candidate_id,
    }
    assert key not in b"".join(writer.lines).decode()
    assert secret not in b"".join(writer.lines).decode()
    assert events[-3:] == ["secrets-registered", "preflight", "completed"]


async def test_gated_restore_preflight_accepts_candidate_without_accounts(store):
    from copytrading_engine.execution.application.restore_preflight import RestorePreflightResult

    candidate_id = str(uuid4())

    class Trading:
        def register_restore_secrets(self, values: tuple[str, ...]) -> None:
            assert values == ()

    class Preflight:
        def preflight_restore_candidate(self, requested_id, credentials):
            assert requested_id == candidate_id
            assert credentials == ()
            return RestorePreflightResult(candidate_id, 0, ())

    class NoPendingWork:
        async def process_pending(self, *, max_items):
            raise AssertionError("gated bootstrap must not recover archived work")

    server = PipeServer(
        NoPendingWork(),
        EngineQueries(store, store.installation.instance_id),
        trading=services(Trading()),
        restore_preflight=Preflight(),
        restore_gated=True,
    )
    response = decode(
        await server.handle_line(
            request_line(
                "restore_preflight",
                "req-preflight-empty",
                candidate_id=candidate_id,
                accounts=[],
            )
        )
    )

    assert response["ok"]["eligible"] is True
    assert response["ok"]["checked_account_count"] == 0
    assert response["ok"]["completion_token"]


class _CollectingWriter:
    def __init__(self) -> None:
        self.lines: list[bytes] = []

    def write(self, data: bytes) -> None:
        self.lines.append(data)

    async def drain(self) -> None:
        return None


def test_every_contract_request_has_a_handler(store):
    server = _server(store)

    union, _discriminator = get_args(RequestType)
    assert set(server._handlers) == set(get_args(union))


async def test_shared_request_fixtures_decode_with_the_python_boundary(store):
    server = PipeServer(
        SelfTestService(store, SelfTestParser()),
        EngineQueries(store, store.installation.instance_id),
    )
    request = (CONTRACTS / "submit-self-test.json").read_bytes()
    unknown = (CONTRACTS / "unknown-version-request.json").read_bytes()
    malformed = (CONTRACTS / "malformed.json").read_bytes()

    accepted = decode(await server.handle_line(request))
    rejected_unknown = decode(await server.handle_line(unknown))
    rejected_malformed = decode(await server.handle_line(malformed))

    assert accepted["ok"]["workflow"]["stage"] == "captured"
    assert rejected_unknown == json.loads((CONTRACTS / "unknown-version.json").read_bytes())
    assert rejected_malformed["error"] == {"code": "invalid_request"}
    assert await store.pending_async() == ("sim-1",)


async def test_unknown_version_is_echoed_and_rejected_without_creating_work(store):
    server = _server(store)
    line = json.dumps(
        {
            "version": 2,
            "request_id": "req-unknown-version",
            "operation": "submit_self_test",
            "command": {
                "command_id": "sim-1",
                "text": "Bought AAPL 1/6 at 200",
                "destination_ids": ["self-test-a"],
            },
        }
    ).encode()

    response = decode(await server.handle_line(line))

    assert response == {
        "version": 2,
        "request_id": "req-unknown-version",
        "error": {"code": "invalid_request"},
    }
    assert await store.pending_async() == ()


@pytest.mark.parametrize("version", [True, 1.0])
async def test_submit_requires_an_actual_integer_version(store, version):
    server = _server(store)
    request = json.dumps(
        {
            "version": version,
            "request_id": "req-invalid-version-type",
            "operation": "submit_self_test",
            "command": {
                "command_id": "sim-1",
                "text": "Bought AAPL 1/6 at 200",
                "destination_ids": ["self-test-a"],
            },
        }
    ).encode()

    response = decode(await server.handle_line(request))

    assert response["error"] == {"code": "invalid_request"}
    assert await store.pending_async() == ()


async def test_extra_fields_and_unknown_operations_are_rejected(store):
    server = _server(store)
    extra = request_line("get_status", "req-extra", secret="do-not-return")
    unknown = request_line("restart", "req-unknown")

    extra_response = decode(await server.handle_line(extra))
    unknown_response = decode(await server.handle_line(unknown))

    assert extra_response["error"] == {"code": "invalid_request"}
    assert unknown_response["error"] == {"code": "invalid_request"}
    assert "do-not-return" not in json.dumps(extra_response)
    assert await store.pending_async() == ()


async def test_malformed_and_overlong_lines_receive_bounded_invalid_responses(store):
    server = _server(store)

    malformed = decode(await server.handle_line(b'{"version":1,"request_id":'))
    overlong = decode(await server.handle_line(b"x" * (MAX_REQUEST_LINE_BYTES + 1)))

    assert malformed == {
        "version": 1,
        "request_id": "",
        "error": {"code": "invalid_request"},
    }
    assert overlong["error"] == {"code": "invalid_request"}
    assert len(json.dumps(overlong).encode()) < 256
    assert await store.pending_async() == ()


async def test_unrepresentable_headers_return_errors_and_do_not_end_the_stream(store):
    server = _server(store)
    oversized_integer = b'{"version":' + b"9" * 5000 + b',"request_id":"req-big"}'
    lone_surrogate = b'{"version":1,"request_id":"\\ud800","operation":"get_status"}'
    valid_status = request_line("get_status", "req-after-malformed")
    reader = asyncio.StreamReader()
    reader.feed_data(b"\n".join((oversized_integer, lone_surrogate, valid_status)) + b"\n")
    reader.feed_eof()
    writer = _CollectingWriter()

    await server.serve(reader, writer)

    responses = [decode(line) for line in writer.lines]
    assert responses[0] == {
        "version": 1,
        "request_id": "",
        "error": {"code": "invalid_request"},
    }
    assert responses[1] == {
        "version": 1,
        "request_id": "",
        "error": {"code": "invalid_request"},
    }
    assert responses[2]["ok"]["type"] == "status"
    assert responses[2]["request_id"] == "req-after-malformed"


async def test_workflow_not_found_and_identity_conflict_use_declared_error_codes(store):
    server = _server(store)
    command = {
        "command_id": "sim-1",
        "text": "Bought AAPL 1/6 at 200",
        "destination_ids": ["self-test-a"],
    }
    await server.handle_line(request_line("submit_self_test", "req-accept", command=command))
    changed = {**command, "text": "different"}
    conflict = decode(
        await server.handle_line(request_line("submit_self_test", "req-conflict", command=changed))
    )
    missing = decode(
        await server.handle_line(request_line("get_workflow", "req-missing", command_id="absent"))
    )

    assert conflict["error"] == {"code": "identity_conflict"}
    assert missing["error"] == {"code": "not_found"}


async def test_status_response_is_tagged_and_reports_degraded_telemetry(store):
    server = _server(store)
    response = decode(await server.handle_line(request_line("get_status", "req-status")))

    assert response["version"] == 1
    assert response["request_id"] == "req-status"
    assert response["ok"]["type"] == "status"
    assert response["ok"]["status"] == {
        "instance_id": store.installation.instance_id,
        "state": "running",
        "accepted": 0,
        "pending": 0,
        "completed": 0,
        "telemetry_state": "degraded",
        "telemetry_dropped": 0,
        "telemetry_error_code": None,
        "diagnostic_capture": {
            "source_events": 0,
            "source_event_gaps": 0,
            "model_requests": 0,
            "model_request_gaps": 0,
            "model_responses": 0,
            "model_response_gaps": 0,
        },
    }


async def test_closed_storage_maps_to_unavailable_without_exception_details(tmp_path):
    with Installation(tmp_path / "application.db") as installation:
        store = SQLiteSelfTestStore(installation)
        store.__enter__()
        instance_id = installation.instance_id
        store.close()
    server = PipeServer(SelfTestService(store, SelfTestParser()), EngineQueries(store, instance_id))

    response = decode(await server.handle_line(request_line("get_status", "req-storage")))

    assert response == {
        "version": 1,
        "request_id": "req-storage",
        "error": {"code": "unavailable"},
    }


class _RefusingBackup(_BackupRestore):
    async def create_backup(self, destination: Path) -> BackupManifest:
        raise BackupManifestError("backup destination already exists")


async def test_backup_refusals_reach_the_app_as_a_readable_reason(store, tmp_path):
    server = PipeServer(
        SelfTestService(store, SelfTestParser()),
        EngineQueries(store, store.installation.instance_id),
        backup_restore=_RefusingBackup(tmp_path / ".restore-staging"),
    )
    refused = decode(
        await server.handle_line(
            request_line("create_backup", "req-exists", destination=str(tmp_path / "b.zip"))
        )
    )
    assert refused["error"] == {
        "code": "invalid_request",
        "message": "Backup destination already exists.",
    }
