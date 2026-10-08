"""A fake engine and a fake app relay for agent-control tests.

Engine results come from the app's contract fixtures, so the control views are checked
against the same shapes the native app decodes.
"""

import asyncio
import datetime as dt
import json
import os
import tempfile
from collections.abc import AsyncIterator, Callable
from contextlib import asynccontextmanager
from dataclasses import dataclass, field, replace
from pathlib import Path
from typing import Any

from copytrading_engine.control.audit import AuditEntry
from copytrading_engine.control.policy import AccessLevel, RateWindow
from copytrading_engine.control.proposals import ProposalBook
from copytrading_engine.control.service import ControlContext, ControlService
from copytrading_engine.execution.domain.lifecycle import (
    AccountControlCommand,
    AccountControlResult,
)
from copytrading_engine.execution.domain.manual_commands import (
    ManualCommandPage,
    ManualCommandPageRequest,
    ManualCommandResult,
    ManualCommandsOutcome,
    ManualConfirmationRequest,
    ManualOrderPreview,
    ManualPreviewRequest,
)
from copytrading_engine.execution.presentation.operator_views import (
    AccountEventPage,
    AccountOverviewPage,
)
from copytrading_engine.host.installation import Installation
from copytrading_engine.host.pipe.server import PipeServer
from copytrading_engine.host.self_test.parser import SelfTestParser
from copytrading_engine.host.self_test.service import SelfTestService
from copytrading_engine.host.self_test.store import SQLiteSelfTestStore
from copytrading_engine.host.status import EngineQueries
from copytrading_engine.trading.domain.status import AccountStatus, TradingStatus
from copytrading_engine.trading.presentation.operator_models import SourceActivityPage

from ..contracts import CONTRACTS

# The manual preview fixture expires at 15:00:33Z, so proposals built from it are valid now.
NOW = dt.datetime(2026, 9, 26, 15, 0, 10, tzinfo=dt.UTC)
BROKER_IDENTITIES = ("broker-123", "broker-paper")

# The raw journal an agent reads through the control socket; the app reads the feed instead.
ACCOUNT_EVENTS = {
    "account_id": "paper",
    "items": [
        {
            "sequence": 10,
            "at": "2026-09-26T15:02:00Z",
            "kind": "account_control_changed",
            "reason": "set_recovery",
            "status": "automatic",
        },
        {
            "sequence": 9,
            "at": "2026-09-26T14:59:00Z",
            "kind": "skipped",
            "message_id": "discord:demo:signal-7",
            "reason": "account_paused",
        },
    ],
    "next_before_seq": 9,
}


def fixture(name: str, key: str) -> dict[str, Any]:
    return json.loads((CONTRACTS / f"{name}.json").read_text())["ok"][key]


class Clock:
    def __init__(self, now: dt.datetime = NOW) -> None:
        self.now = now

    def __call__(self) -> dt.datetime:
        return self.now

    def advance(self, **delta: float) -> None:
        self.now += dt.timedelta(**delta)


class FakeEngine:
    """Plays the trading runtime's processing, operator, and manual roles."""

    def __init__(self) -> None:
        self.calls: list[tuple[str, object]] = []
        self.failure: Exception | None = None
        self.trading = TradingStatus(
            state="running",
            configured_accounts=1,
            active_accounts=1,
            source_connected=True,
            model_ready=True,
            accounts=(AccountStatus(id="paper", state="running", entry_permission="paused"),),
        )

    def status(self) -> TradingStatus:
        return self.trading

    async def pause(self) -> TradingStatus:
        self.calls.append(("pause", None))
        self.trading = replace(self.trading, state="paused")
        return self.trading

    async def account_overviews(
        self, before_account_id: str | None, limit: int
    ) -> AccountOverviewPage:
        return AccountOverviewPage.model_validate_json(
            json.dumps(fixture("account-overviews-response", "accounts"))
        )

    async def source_activity(self, before_seq: int | None, limit: int) -> SourceActivityPage:
        return SourceActivityPage.model_validate_json(
            json.dumps(fixture("source-activity-response", "activity"))
        )

    async def account_events(
        self, account_id: str, before_seq: int | None, limit: int
    ) -> AccountEventPage:
        if account_id != "paper":
            raise KeyError(account_id)
        return AccountEventPage.model_validate_json(json.dumps(ACCOUNT_EVENTS))

    async def list_manual_commands(self, request: ManualCommandPageRequest) -> ManualCommandPage:
        return ManualCommandPage.model_validate_json(
            json.dumps(fixture("manual-command-page-response", "commands"))
        )

    async def manual_command_result(self, account_id: str, command_id: str) -> ManualCommandResult:
        return ManualCommandResult.model_validate_json(
            json.dumps(fixture("manual-command-response", "command"))
        )

    async def control_account(self, command: AccountControlCommand) -> AccountControlResult:
        self.calls.append(("control_account", command))
        if self.failure is not None:
            raise self.failure
        return AccountControlResult(
            command=command,
            applied_at=NOW,
            entry_permission="paused" if command.action == "pause" else "enabled",
            recovery_preference=command.recovery_preference or "manual",
        )

    async def preview_manual_order(self, request: ManualPreviewRequest) -> ManualOrderPreview:
        preview = fixture("manual-preview-response", "preview")
        preview["request"] = request.model_dump(mode="json")
        return ManualOrderPreview.model_validate_json(json.dumps(preview))

    async def confirm_manual_orders(
        self, requests: tuple[ManualConfirmationRequest, ...]
    ) -> ManualCommandsOutcome:
        self.calls.append(("confirm_manual_orders", requests))
        if self.failure is not None:
            raise self.failure
        (request,) = requests
        outcome = fixture("manual-confirmation-response", "commands")["outcomes"][0]
        outcome["command_id"] = request.command_id
        outcome["result"]["command"]["request"] = request.model_dump(mode="json")
        return ManualCommandsOutcome.model_validate_json(json.dumps({"outcomes": [outcome]}))

    def actions(self) -> list[tuple[str, object]]:
        """Calls that change an account or place an order (pausing excluded)."""
        return [
            call
            for call in self.calls
            if call[0] == "confirm_manual_orders"
            or (
                call[0] == "control_account"
                and isinstance(call[1], AccountControlCommand)
                and call[1].action != "pause"
            )
        ]


@dataclass
class MemoryAudit:
    entries: list[AuditEntry] = field(default_factory=list)

    async def record(self, entry: AuditEntry) -> None:
        self.entries.append(entry)

    async def recent(self, limit: int) -> tuple[AuditEntry, ...]:
        return tuple(reversed(self.entries))[:limit]


def service(
    engine: FakeEngine | None = None,
    audit: MemoryAudit | None = None,
    clock: Clock | None = None,
    rate: RateWindow | None = None,
) -> tuple[ControlService, FakeEngine, MemoryAudit, Clock]:
    engine = engine or FakeEngine()
    audit = audit or MemoryAudit()
    clock = clock or Clock()
    control = ControlService(
        engine, engine, engine, audit, clock=clock, book=ProposalBook(clock), rate=rate
    )
    return control, engine, audit, clock


def context(access: AccessLevel = "propose", *, unlocked: bool = True) -> ControlContext:
    return ControlContext(
        access_level=access, unlocked=unlocked, caller_pid=4242, caller_path="/usr/bin/agent"
    )


@dataclass
class Relay:
    """Stands in for the app: accepts socket lines and forwards them to a relay function."""

    path: Path
    access: AccessLevel = "propose"
    unlocked: bool = True


@asynccontextmanager
async def app_socket(
    forward: Callable[[str, ControlContext], Any],
) -> AsyncIterator[Relay]:
    """Serve the control socket from a short owner-only directory, as the app will."""
    # Socket paths are short on macOS; /private/tmp is the real /tmp there, and Linux has /tmp.
    short = "/private/tmp" if Path("/private/tmp").is_dir() else "/tmp"
    directory = Path(tempfile.mkdtemp(prefix="spc-", dir=short))
    os.chmod(directory, 0o700)
    relay = Relay(directory / "cli.sock")

    async def handle(reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        line = (await reader.readline()).decode().rstrip("\n")
        answer = await forward(
            line,
            ControlContext(
                access_level=relay.access,
                unlocked=relay.unlocked,
                caller_pid=os.getpid(),
                caller_path="/usr/bin/agent",
            ),
        )
        writer.write(answer.encode() + b"\n")
        await writer.drain()
        writer.close()

    server = await asyncio.start_unix_server(handle, path=str(relay.path))
    try:
        yield relay
    finally:
        server.close()
        await server.wait_closed()
        relay.path.unlink(missing_ok=True)
        directory.rmdir()


@asynccontextmanager
async def running_app(database: Path, control: ControlService) -> AsyncIterator[Relay]:
    """A real PipeServer behind a fake app socket: the path every CLI and MCP call takes."""
    with Installation(database) as installation, SQLiteSelfTestStore(installation) as store:
        server = PipeServer(
            SelfTestService(store, SelfTestParser()),
            EngineQueries(store, installation.instance_id),
            control=control,
        )

        async def forward(line: str, relay_context: ControlContext) -> str:
            request = {
                "version": 1,
                "request_id": "relay",
                "operation": "control",
                "line": line,
                "context": relay_context.model_dump(mode="json"),
            }
            reply = json.loads(await server.handle_line(json.dumps(request).encode()))
            return reply["ok"]["line"]

        async with app_socket(forward) as relay:
            yield relay
