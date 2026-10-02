"""Local engine composition root and inherited-pipe lifecycle."""

import argparse
import asyncio
import os
import sys
import uuid
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from pathlib import Path
from typing import cast

from copytrading_engine.assistant.service import AssistantService
from copytrading_engine.backup.restore.gate import (
    restore_manual_disabled,
    restore_manual_disabled_path,
)
from copytrading_engine.backup.restore.inspector import SQLiteRestoreCandidateInspector
from copytrading_engine.backup.schema_catalog import (
    create_application_schema,
    current_operational_schema_catalog,
)
from copytrading_engine.backup.service import BackupRestoreService
from copytrading_engine.control.service import ControlService
from copytrading_engine.control.sqlite import SQLiteControlAudit
from copytrading_engine.diagnostics.capture import DiagnosticEngineQueries, DiagnosticWorkflowStore
from copytrading_engine.diagnostics.telemetry.config import TelemetryConfig
from copytrading_engine.diagnostics.telemetry.local import LocalTelemetry
from copytrading_engine.execution.adapters.alpaca.broker import AlpacaBroker, AlpacaCredentials
from copytrading_engine.execution.adapters.restore_preparer import prepare_restored_account
from copytrading_engine.execution.adapters.sqlite_ledger import current_execution_snapshot_schema
from copytrading_engine.execution.application.restore_preflight import (
    RestoreBrokerCredential,
    RestoreCandidatePreflight,
)
from copytrading_engine.host.errors import (
    ForeignInstallation,
    IdentityConflict,
    InstallationAlreadyRunning,
    InvalidCommand,
    StoreUnavailable,
    UnknownSchemaVersion,
    WorkflowError,
)
from copytrading_engine.host.installation import Installation
from copytrading_engine.host.pipe.server import PipeServer
from copytrading_engine.host.pipe.services import TradingServices
from copytrading_engine.host.self_test.parser import SelfTestParser
from copytrading_engine.host.self_test.service import SelfTestService
from copytrading_engine.host.self_test.store import SQLiteSelfTestStore
from copytrading_engine.trading.adapters.telemetry import TradingTelemetry
from copytrading_engine.trading.entrypoints.runtime import TradingRuntime

_STARTUP_RECOVERY_LIMIT = 100


class _PipeOutput(asyncio.Protocol):
    def __init__(self) -> None:
        self._transport: asyncio.WriteTransport | None = None
        self._ready = asyncio.Event()
        self._ready.set()
        self._failure: Exception | None = None

    def connection_made(self, transport: asyncio.BaseTransport) -> None:
        self._transport = cast(asyncio.WriteTransport, transport)

    def pause_writing(self) -> None:
        self._ready.clear()

    def resume_writing(self) -> None:
        self._ready.set()

    def connection_lost(self, exc: Exception | None) -> None:
        self._failure = exc
        self._ready.set()

    def write(self, data: bytes) -> None:
        if self._transport is None:
            raise StoreUnavailable("standard output pipe is unavailable")
        self._transport.write(data)

    async def drain(self) -> None:
        await self._ready.wait()
        if self._failure is not None:
            raise StoreUnavailable("standard output pipe is unavailable") from self._failure


def main() -> int:
    parser = argparse.ArgumentParser(prog="copytrading-engine")
    parser.add_argument("--data-dir", required=True, type=Path)
    parser.add_argument("--instance-id", required=True)
    args = parser.parse_args()
    try:
        instance_id = _canonical_instance_id(args.instance_id)
        data_dir = args.data_dir.expanduser().resolve()
        owner_support_directory = owner_support_root()
        persist_installation_id(owner_support_directory, instance_id)
        asyncio.run(_run(data_dir, instance_id))
    except ForeignInstallation, IdentityConflict:
        print("engine startup failed code=identity_conflict", file=sys.stderr)
        return 1
    except InstallationAlreadyRunning, UnknownSchemaVersion:
        print("engine startup failed code=unavailable", file=sys.stderr)
        return 1
    except InvalidCommand, ValueError:
        print("engine startup failed code=invalid_request", file=sys.stderr)
        return 2
    except OSError, StoreUnavailable, WorkflowError:
        print("engine startup failed code=unavailable", file=sys.stderr)
        return 1
    except Exception:  # noqa: BLE001 - last-resort exit code; details stay off stderr
        print("engine failed code=internal_error", file=sys.stderr)
        return 1
    return 0


async def _run(data_dir: Path, instance_id: str) -> None:
    async with compose_engine(
        data_dir,
        instance_id,
        diagnostics_directory=diagnostics_state_root(),
        owner_support_directory=owner_support_root(),
    ) as server:
        await _serve_stdio(server)


@asynccontextmanager
async def compose_engine(
    data_dir: Path,
    instance_id: str,
    *,
    diagnostics_directory: Path,
    owner_support_directory: Path,
) -> AsyncIterator[PipeServer]:
    """The whole engine behind one request server, shut down cleanly on exit.

    The app drives it over an inherited pipe; the headless server drives the same requests
    from its sockets.
    """
    restore_gate = restore_manual_disabled_path(owner_support_directory)
    telemetry = LocalTelemetry(TelemetryConfig.from_environment(diagnostics_directory))
    trading_telemetry = TradingTelemetry(sink=telemetry)
    trading = TradingRuntime(
        data_dir,
        telemetry=trading_telemetry,
        restore_gate_path=restore_gate,
    )
    restore_gated = restore_manual_disabled(restore_gate)
    backup_restore = BackupRestoreService(
        data_dir,
        trading.maintenance_fence,
        schema_catalog=current_operational_schema_catalog,
        snapshot_schema=current_execution_snapshot_schema,
        owner_support_directory=owner_support_directory,
        account_preparer=prepare_restored_account,
    )
    restore_preflight = RestoreCandidatePreflight(
        SQLiteRestoreCandidateInspector(backup_restore),
        _restore_evidence_broker,
    )
    installation = Installation(
        data_dir / "application.db",
        instance_id=instance_id,
        lock_path=owner_support_directory / ".engine.lock",
        read_only=restore_gated,
    )
    try:
        with installation, SQLiteSelfTestStore(installation) as store:
            if not restore_gated:
                create_application_schema(data_dir / "application.db")
            diagnostic_store = DiagnosticWorkflowStore(store, telemetry)
            service = SelfTestService(diagnostic_store, SelfTestParser())
            queries = DiagnosticEngineQueries(store, installation.instance_id, telemetry)
            await _process_pending_if_allowed(
                service,
                restore_gate,
                max_items=_STARTUP_RECOVERY_LIMIT,
            )
            control_audit = (
                None
                if restore_gated
                else await SQLiteControlAudit.open(data_dir / "application.db")
            )
            control = (
                None
                if control_audit is None
                else ControlService(trading, trading.operator, trading.manual, control_audit)
            )
            assistant = (
                None
                if control is None
                else AssistantService(
                    control,
                    trading.operator,
                    engine_state=lambda: server.engine_state,
                    register_secrets=telemetry.register_secrets,
                )
            )
            server = PipeServer(
                service,
                queries,
                TradingServices.of(trading),
                backup_restore,
                restore_preflight,
                restore_gated=restore_gated,
                control=control,
                assistant=assistant,
            )
            try:
                yield server
            finally:
                await trading.shutdown()
                if control_audit is not None:
                    await control_audit.close()
    finally:
        telemetry.close(timeout_seconds=5.0)


def _restore_evidence_broker(
    credential: RestoreBrokerCredential,
) -> AlpacaBroker:
    return AlpacaBroker(
        AlpacaCredentials(key=credential.key, secret=credential.secret),
        credential.environment,
    )


def diagnostics_state_root() -> Path:
    return _required_directory("COPYTRADING_DESKTOP_DIAGNOSTICS_STATE_DIR")


def owner_support_root() -> Path:
    return _required_directory("COPYTRADING_DESKTOP_OWNER_SUPPORT_DIR")


def _required_directory(variable: str) -> Path:
    """The app names every state root; the engine never derives one from --data-dir."""
    value = os.environ.get(variable)
    if not value:
        raise ValueError(f"{variable} is required")
    return Path(value)


async def _process_pending_if_allowed(
    service: SelfTestService,
    restore_gate: Path,
    *,
    max_items: int = _STARTUP_RECOVERY_LIMIT,
) -> None:
    if restore_manual_disabled(restore_gate):
        return
    await service.process_pending(max_items=max_items)


async def _serve_stdio(server: PipeServer) -> None:
    loop = asyncio.get_running_loop()
    reader = asyncio.StreamReader(limit=64 * 1024)
    reader_protocol = asyncio.StreamReaderProtocol(reader)
    read_transport, _ = await loop.connect_read_pipe(lambda: reader_protocol, sys.stdin.buffer)
    output = _PipeOutput()
    write_transport, _ = await loop.connect_write_pipe(lambda: output, sys.stdout.buffer)
    try:
        await server.serve(reader, output)
    finally:
        read_transport.close()
        write_transport.close()


def _canonical_instance_id(value: str) -> str:
    try:
        canonical = str(uuid.UUID(value))
    except (ValueError, AttributeError) as exc:
        raise InvalidCommand("instance ID must be a UUID") from exc
    if value.lower() != canonical:
        raise InvalidCommand("instance ID must use canonical UUID formatting")
    return canonical


def persist_installation_id(owner_support_directory: Path, instance_id: str) -> None:
    try:
        owner_support_directory.mkdir(mode=0o700, parents=True, exist_ok=True)
        os.chmod(owner_support_directory, 0o700)
        identity_path = owner_support_directory / "installation-id"
        try:
            descriptor = os.open(
                identity_path,
                os.O_CREAT | os.O_EXCL | os.O_WRONLY,
                0o600,
            )
        except FileExistsError:
            existing = identity_path.read_text(encoding="ascii").strip()
            if _canonical_instance_id(existing) != instance_id:
                raise ForeignInstallation(
                    "data directory belongs to a different installation"
                ) from None
            return

        with os.fdopen(descriptor, "w", encoding="ascii") as identity_file:
            identity_file.write(instance_id + "\n")
            identity_file.flush()
            os.fsync(identity_file.fileno())
        os.chmod(identity_path, 0o600)
        directory_fd = os.open(owner_support_directory, os.O_RDONLY)
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
    except ForeignInstallation, InvalidCommand:
        raise
    except OSError as exc:
        raise StoreUnavailable("installation identity is unavailable") from exc
