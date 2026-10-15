"""Drive the engine's request server the way the app does, from inside the server process."""

import asyncio
import json
import time
import uuid
from collections.abc import Awaitable, Callable
from typing import Any

from pydantic import BaseModel, ConfigDict

from copytrading_engine.control.wire import ProposalView
from copytrading_engine.headless.config import AgentAccess, ServerSetup
from copytrading_engine.headless.owner import CopyingStatus, EntriesChanged, proposal_from_engine
from copytrading_engine.host.pipe.server import PipeServer
from copytrading_engine.trading.domain.config import TradingSecrets

# The ok body of an engine reply. It stays inside this module: callers get typed views.
type Reply = dict[str, Any]


class ConnectionCheck(BaseModel):
    model_config = ConfigDict(frozen=True, extra="ignore")

    name: str
    state: str
    subject: str | None = None
    environment: str | None = None
    reason_code: str | None = None

    @property
    def passed(self) -> bool:
        return self.state in {"ready", "not_configured"}


class SetupReport(BaseModel):
    """The setup check, as the app's Check Setup shows it."""

    model_config = ConfigDict(frozen=True, extra="ignore")

    activatable: bool
    checks: tuple[ConnectionCheck, ...] = ()


class ExampleResult(BaseModel):
    model_config = ConfigDict(frozen=True, extra="ignore")

    example_index: int
    expected_action: str
    expected_symbol: str
    matches: bool
    review_reasons: tuple[str, ...] = ()


class ExampleReview(BaseModel):
    """How the model read one guru's examples; a different reading blocks the start."""

    model_config = ConfigDict(frozen=True, extra="ignore")

    guru_id: str
    automatic_activation_allowed: bool
    examples: tuple[ExampleResult, ...] = ()


ACTIVATION_TIMEOUT_SECONDS = 120.0


class EngineRefused(Exception):
    """The engine answered a request with an error code; the message says which."""

    def __init__(self, operation: str, code: str, message: str | None = None) -> None:
        detail = f"{operation} failed: {code}" + (f" ({message})" if message else "")
        super().__init__(detail)
        self.code = code


class SetupNotReady(Exception):
    """The setup check found problems, so copying did not start."""

    def __init__(self, report: SetupReport) -> None:
        super().__init__("The setup check did not pass.")
        self.report = report


class HeadlessEngine:
    """One request at a time into the engine, exactly as the app's pipe delivered them."""

    def __init__(
        self,
        server: PipeServer,
        setup: ServerSetup,
        secrets: TradingSecrets,
        *,
        clock: Callable[[], float] = time.monotonic,
        sleep: Callable[[float], Awaitable[None]] = asyncio.sleep,
    ) -> None:
        self._server = server
        self._setup = setup
        self._secrets = secrets
        self._lock = asyncio.Lock()
        self._clock = clock
        self._sleep = sleep

    @property
    def agent_access(self) -> AgentAccess:
        return self._setup.agent_access

    async def request(self, operation: str, **fields: object) -> Reply:
        """Send one request and return its ok body, or raise EngineRefused.

        The engine's own request validation runs on every call, as it does for the app; the
        lock keeps the one-request-at-a-time order the app's pipe guaranteed.
        """
        envelope = {"version": 1, "request_id": uuid.uuid4().hex, "operation": operation}
        line = json.dumps(envelope | fields, separators=(",", ":")).encode()
        async with self._lock:
            raw = await self._server.handle_line(line)
        response = json.loads(raw)
        if "error" in response:
            error = response["error"]
            raise EngineRefused(operation, error.get("code", "unknown"), error.get("message"))
        return response["ok"]

    async def validate(self) -> SetupReport:
        """Check every connection and the setup; nothing is saved or traded."""
        report, _token = await self._validate()
        return report

    async def review_examples(self) -> tuple[ExampleReview, ...]:
        """Have the model read each guru's examples, as Check Setup does in the app."""
        configuration = self._setup.configuration
        reviews = []
        for profile in configuration.profiles:
            if not profile.examples:
                continue
            route = next(r for r in configuration.routes if r.guru_id == profile.guru_id)
            reply = await self.request(
                "review_profile_examples",
                profile=profile.model_dump(mode="json"),
                provider=configuration.provider.model_dump(mode="json"),
                provider_api_key=self._secrets.provider_api_key.get_secret_value(),
                destinations=[item.model_dump(mode="json") for item in route.connections],
            )
            reviews.append(ExampleReview.model_validate(reply["review"]))
        return tuple(reviews)

    async def start(self) -> None:
        """Check the setup, start copying, and wait until the engine reports it running."""
        report, token = await self._validate()
        if token is None:
            raise SetupNotReady(report)
        activation_id = str(uuid.uuid4())
        await self.request(
            "start_trading",
            configuration=self._configuration(),
            secrets=self._secret_values(),
            validation_token=token,
            activation_id=activation_id,
        )
        deadline = self._clock() + ACTIVATION_TIMEOUT_SECONDS
        while True:
            reply = await self.request("get_trading_activation", activation_id=activation_id)
            activation = reply["activation"]
            if activation["phase"] != "starting":
                if activation["phase"] != "ready":
                    raise EngineRefused(
                        "start_trading", activation.get("error_code") or activation["phase"]
                    )
                return
            if self._clock() > deadline:
                raise EngineRefused("start_trading", "activation_timeout")
            await self._sleep(0.5)

    async def status(self) -> CopyingStatus:
        return CopyingStatus.model_validate((await self.request("get_trading_status"))["trading"])

    async def pause(self) -> CopyingStatus:
        return CopyingStatus.model_validate((await self.request("pause_trading"))["trading"])

    async def set_entries(self, account_id: str, *, enabled: bool) -> EntriesChanged:
        command = {
            "command_id": f"server-{uuid.uuid4().hex}",
            "account_id": account_id,
            "action": "resume" if enabled else "pause",
        }
        control = (await self.request("control_account", command=command))["control"]
        return EntriesChanged(account_id=account_id, entry_permission=control["entry_permission"])

    async def proposals(self) -> tuple[ProposalView, ...]:
        items = (await self.request("list_proposals"))["proposals"]
        return tuple(proposal_from_engine(item) for item in items)

    async def approve(self, proposal_id: str, digest: str) -> ProposalView:
        reply = await self.request("approve_proposal", proposal_id=proposal_id, digest=digest)
        return proposal_from_engine(reply["proposal"])

    async def reject(self, proposal_id: str) -> ProposalView:
        reply = await self.request("reject_proposal", proposal_id=proposal_id)
        return proposal_from_engine(reply["proposal"])

    async def relay_agent_line(self, line: str, caller_pid: int | None) -> str:
        """One agent request, with the owner's chosen access, answered as a contract line."""
        if self.agent_access == "off":
            raise EngineRefused("control", "access_off")
        context = {
            "access_level": self.agent_access,
            "unlocked": True,
            "caller_pid": caller_pid,
            "caller_path": None,
        }
        reply = await self.request("control", line=line, context=context)
        return reply["line"]

    async def _validate(self) -> tuple[SetupReport, str | None]:
        reply = await self.request(
            "validate_trading",
            configuration=self._configuration(),
            secrets=self._secret_values(),
        )
        return SetupReport.model_validate(reply["report"]), reply.get("activation_token")

    def _configuration(self) -> Reply:
        return self._setup.configuration.model_dump(mode="json")

    def _secret_values(self) -> Reply:
        secrets = self._secrets
        return {
            "discord_token": secrets.discord_token.get_secret_value(),
            "provider_api_key": secrets.provider_api_key.get_secret_value(),
            "brokers": [
                {
                    "account_id": broker.account_id,
                    "key": broker.key.get_secret_value(),
                    "secret": broker.secret.get_secret_value(),
                }
                for broker in secrets.brokers
            ],
            "notification_token": (
                None
                if secrets.notification_token is None
                else secrets.notification_token.get_secret_value()
            ),
        }
