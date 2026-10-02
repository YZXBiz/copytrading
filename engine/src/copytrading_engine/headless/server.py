"""Compose the engine in this process, start copying, and serve until asked to stop."""

import asyncio
import contextlib
import signal
import tempfile
import uuid
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path

from copytrading_engine.bootstrap import compose_engine, persist_installation_id
from copytrading_engine.control.wire import MAX_LINE_BYTES
from copytrading_engine.headless.config import ServerSetup
from copytrading_engine.headless.engine import ExampleReview, HeadlessEngine, SetupReport
from copytrading_engine.headless.owner import (
    Approve,
    AskStatus,
    ListProposals,
    OwnerAnswer,
    OwnerRequest,
    Pause,
    ProposalChanged,
    Proposals,
    Reject,
    Resume,
    SetEntries,
)
from copytrading_engine.headless.sockets import (
    MAX_OWNER_LINE_BYTES,
    OwnerHandler,
    agent_handler,
    open_socket,
    owner_handler,
    prepare_private_directory,
)
from copytrading_engine.trading.domain.config import TradingSecrets

type Say = Callable[[str], None]

STATUS_INTERVAL_SECONDS = 30.0


@dataclass(frozen=True)
class ServerPaths:
    """Everything the server keeps, under one owner-only root."""

    root: Path

    @property
    def data(self) -> Path:
        return self.root / "data"

    @property
    def support(self) -> Path:
        return self.root / "support"

    @property
    def logs(self) -> Path:
        return self.root / "logs"

    @property
    def control(self) -> Path:
        return self.root / "control"

    @property
    def agent_socket(self) -> Path:
        return self.control / "cli.sock"

    @property
    def owner_socket(self) -> Path:
        return self.control / "owner.sock"

    def prepare(self) -> None:
        """Create every folder owner-only, refusing any that someone else could reach."""
        for directory in (self.root, self.data, self.support, self.logs, self.control):
            prepare_private_directory(directory)

    def installation_id(self) -> str:
        """This server's lasting identity, created on first use; the engine checks it."""
        identity = self.support / "installation-id"
        instance_id = (
            identity.read_text(encoding="ascii").strip() if identity.exists() else str(uuid.uuid4())
        )
        persist_installation_id(self.support, instance_id)
        return instance_id


class _Discard:
    """The engine's reply stream has no reader here: requests arrive from the sockets."""

    def write(self, data: bytes) -> None:
        return None

    async def drain(self) -> None:
        return None


@dataclass(frozen=True)
class CheckResult:
    report: SetupReport
    reviews: tuple[ExampleReview, ...]

    @property
    def passed(self) -> bool:
        return self.report.activatable and all(
            review.automatic_activation_allowed for review in self.reviews
        )


async def check_setup(setup: ServerSetup, secrets: TradingSecrets) -> CheckResult:
    """Run the app's setup check in a throwaway state folder; nothing is saved or traded."""
    with tempfile.TemporaryDirectory(prefix="copytrading-check-") as scratch:
        paths = ServerPaths(Path(scratch).resolve())
        paths.prepare()
        async with compose_engine(
            paths.data,
            paths.installation_id(),
            diagnostics_directory=paths.logs,
            owner_support_directory=paths.support,
        ) as server:
            engine = HeadlessEngine(server, setup, secrets)
            return CheckResult(await engine.validate(), await engine.review_examples())


async def run_server(
    setup: ServerSetup,
    secrets: TradingSecrets,
    paths: ServerPaths,
    *,
    say: Say,
    stop: asyncio.Event | None = None,
    install_signal_handlers: bool = True,
) -> None:
    """Start copying, serve the sockets, and wind down like the app does on quit."""
    paths.prepare()
    stop = stop or asyncio.Event()
    async with compose_engine(
        paths.data,
        paths.installation_id(),
        diagnostics_directory=paths.logs,
        owner_support_directory=paths.support,
    ) as server:
        engine = HeadlessEngine(server, setup, secrets)
        say("Checking the setup and starting to copy…")
        await engine.start()
        reader = asyncio.StreamReader()
        serving = asyncio.create_task(server.serve(reader, _Discard()))
        sockets: list[asyncio.Server] = []
        watcher: asyncio.Task[None] | None = None
        try:
            sockets.append(
                await open_socket(
                    paths.owner_socket,
                    owner_handler(_owner_requests(engine, say)),
                    limit=MAX_OWNER_LINE_BYTES,
                )
            )
            if engine.agent_access != "off":
                sockets.append(
                    await open_socket(
                        paths.agent_socket, agent_handler(engine), limit=MAX_LINE_BYTES
                    )
                )
            if install_signal_handlers:
                loop = asyncio.get_running_loop()
                for signum in (signal.SIGINT, signal.SIGTERM):
                    loop.add_signal_handler(signum, stop.set)
            configuration = setup.configuration
            say(
                f"Copying {len(configuration.profiles)} guru(s) into "
                f"{len(configuration.accounts)} account(s). Agents: {engine.agent_access}. "
                f"State: {paths.root}"
            )
            say("New accounts start with entries off: `copytrading-server entries enable ID`.")
            watcher = asyncio.create_task(_report_changes(engine, say))
            await stop.wait()
            say("Stopping: pausing copying and finishing in-flight work…")
        finally:
            if watcher is not None:
                watcher.cancel()
                with contextlib.suppress(asyncio.CancelledError):
                    await watcher
            for listener in sockets:
                listener.close()
                await listener.wait_closed()
            for path in (paths.agent_socket, paths.owner_socket):
                path.unlink(missing_ok=True)
            # End of input is how the app says goodbye: the engine pauses and drains.
            reader.feed_eof()
            await serving
    say("Stopped.")


def _owner_requests(engine: HeadlessEngine, say: Say) -> OwnerHandler:
    async def handle(request: OwnerRequest) -> OwnerAnswer:
        match request:
            case AskStatus():
                return await engine.status()
            case SetEntries(account=account, enabled=enabled):
                changed = await engine.set_entries(account, enabled=enabled)
                say(f"Entries {'enabled' if enabled else 'disabled'} for {account}.")
                return changed
            case ListProposals():
                return Proposals(items=await engine.proposals())
            case Approve(proposal_id=proposal_id, digest=digest):
                proposal = await engine.approve(proposal_id, digest)
                say(f"Approved {proposal_id}: {proposal.state}.")
                return ProposalChanged(proposal=proposal)
            case Reject(proposal_id=proposal_id):
                proposal = await engine.reject(proposal_id)
                say(f"Rejected {proposal_id}.")
                return ProposalChanged(proposal=proposal)
            case Pause():
                status = await engine.pause()
                say("Copying paused.")
                return status
            case Resume():
                await engine.start()
                say("Copying resumed.")
                return await engine.status()

    return handle


async def _report_changes(engine: HeadlessEngine, say: Say) -> None:
    """Print a line whenever copying's state, an account, or the work done changes."""
    last: str | None = None
    while True:
        await asyncio.sleep(STATUS_INTERVAL_SECONDS)
        try:
            line = (await engine.status()).summary()
        except Exception:  # noqa: BLE001 - a status line is best effort; the engine logs the cause
            continue
        if line != last:
            say(line)
            last = line
