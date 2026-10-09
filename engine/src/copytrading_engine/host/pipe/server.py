"""Strict bounded JSON-line IPC over inherited private standard pipes."""

import asyncio
import json
import logging
from dataclasses import asdict
from typing import Protocol

from pydantic import ValidationError

from copytrading_engine.assistant.service import AssistantService
from copytrading_engine.backup.manifest import BackupManifestError
from copytrading_engine.backup.service import BackupRestoreService
from copytrading_engine.control.service import ControlService
from copytrading_engine.execution.application.restore_preflight import RestoreCandidatePreflight
from copytrading_engine.execution.domain.lifecycle import AccountControlConflict
from copytrading_engine.host.errors import (
    ForeignInstallation,
    IdentityConflict,
    InstallationAlreadyRunning,
    InvalidCommand,
    StoreClosed,
    StoreUnavailable,
    UnknownSchemaVersion,
    WorkflowNotFound,
)
from copytrading_engine.host.pipe.handlers.accounts import AccountHandlers
from copytrading_engine.host.pipe.handlers.assistant import AssistantHandlers
from copytrading_engine.host.pipe.handlers.control import ControlHandlers
from copytrading_engine.host.pipe.handlers.manual import ManualOrderHandlers
from copytrading_engine.host.pipe.handlers.profiles import ProfileHandlers
from copytrading_engine.host.pipe.handlers.restore import BackupRestoreHandlers
from copytrading_engine.host.pipe.handlers.trading import TradingLifecycleHandlers
from copytrading_engine.host.pipe.requests import (
    REQUEST_ADAPTER,
    AbortRestoreCandidateRequest,
    AssistantAskRequest,
    AssistantCancelRequest,
    AssistantResetRequest,
    AssistantTurnRequest,
    CheckConnectionRequest,
    CompleteRestoreCandidateRequest,
    ConfirmManualOrdersRequest,
    ControlAccountRequest,
    CreateBackupRequest,
    EvaluateHistoricalProfileRequest,
    GetAccountFeedRequest,
    GetAccountsRequest,
    GetEquityHistoryRequest,
    GetManualCommandRequest,
    GetSourceActivityRequest,
    GetStatusRequest,
    GetTradingActivationRequest,
    GetTradingStatusRequest,
    GetWorkflowRequest,
    LearnGuruPlaybookRequest,
    ListManualCommandsRequest,
    PauseTradingRequest,
    PipeRequest,
    PrepareRestoreCandidateRequest,
    PreviewManualOrderRequest,
    PreviewRestoreRequest,
    ReplayGuruPostsRequest,
    RequestHandler,
    ResolveOwnershipRequest,
    RestoreCandidateStatusRequest,
    RestorePreflightRequest,
    SaveManualCorrectionRequest,
    StartTradingRequest,
    StopRequest,
    SubmitRequest,
    UpdateAccountLimitsRequest,
    ValidateTradingRequest,
)
from copytrading_engine.host.pipe.responses import ErrorCode, reply, workflow_payload
from copytrading_engine.host.pipe.services import TradingServices
from copytrading_engine.host.pipe.session import PipeSession
from copytrading_engine.host.self_test.model import SubmitSelfTest
from copytrading_engine.host.self_test.service import SelfTestService
from copytrading_engine.host.status import EngineQueries, EngineState
from copytrading_engine.shared.owner_facing import OwnerFacingError

log = logging.getLogger(__name__)

MAX_REQUEST_LINE_BYTES = 1024 * 1024
_READ_CHUNK_BYTES = 64 * 1024
_PROCESS_LIMIT = 100
# An assistant failure ends that one request as `unavailable`, never the pipe.
ASSISTANT_REQUESTS = (
    AssistantAskRequest,
    AssistantTurnRequest,
    AssistantCancelRequest,
    AssistantResetRequest,
)


class _Output(Protocol):
    def write(self, data: bytes) -> None: ...

    async def drain(self) -> None: ...


class PipeServer:
    """Serve one request per line while keeping database and pipe work separate."""

    def __init__(
        self,
        service: SelfTestService,
        queries: EngineQueries,
        trading: TradingServices | None = None,
        backup_restore: BackupRestoreService | None = None,
        restore_preflight: RestoreCandidatePreflight | None = None,
        *,
        restore_gated: bool = False,
        control: ControlService | None = None,
        assistant: AssistantService | None = None,
    ) -> None:
        self._service = service
        self._queries = queries
        self._trading = trading
        self._assistant = assistant
        self._restore_gated = restore_gated
        self._session = PipeSession()
        areas = (
            TradingLifecycleHandlers(trading=trading),
            AccountHandlers(trading=trading),
            ManualOrderHandlers(trading=trading),
            ProfileHandlers(trading=trading),
            BackupRestoreHandlers(
                backup_restore=backup_restore,
                restore_preflight=restore_preflight,
                trading=trading,
                restore_gated=restore_gated,
                session=self._session,
            ),
            ControlHandlers(control=control, session=self._session),
            AssistantHandlers(assistant=assistant),
        )
        self._handlers: dict[type[PipeRequest], RequestHandler] = {
            SubmitRequest: self._on_submit,
            GetStatusRequest: self._on_get_status,
            GetWorkflowRequest: self._on_get_workflow,
            StopRequest: self._on_stop,
        }
        for area in areas:
            self._handlers |= area.handlers()

    async def handle_line(self, raw_line: bytes, *, overlong: bool = False) -> bytes:
        """Validate one request and return a single contract response line."""
        if overlong or len(raw_line.rstrip(b"\r\n")) > MAX_REQUEST_LINE_BYTES:
            return reply(1, "", error="invalid_request")

        payload: object
        try:
            payload = json.loads(raw_line)
        except UnicodeDecodeError, TypeError, ValueError, RecursionError:
            return reply(1, "", error="invalid_request")

        version, request_id = _header(payload)
        if not isinstance(payload, dict) or type(payload.get("version")) is not int:
            return reply(version, request_id, error="invalid_request")
        try:
            request = REQUEST_ADAPTER.validate_json(raw_line)
        except ValidationError:
            return reply(version, request_id, error="invalid_request")

        if self._restore_gated and not isinstance(
            request,
            (
                GetStatusRequest,
                GetWorkflowRequest,
                GetTradingStatusRequest,
                GetTradingActivationRequest,
                RestoreCandidateStatusRequest,
                AbortRestoreCandidateRequest,
                RestorePreflightRequest,
                CompleteRestoreCandidateRequest,
                StopRequest,
            ),
        ):
            return reply(request.version, request.request_id, error="unavailable")

        try:
            return await self._handlers[type(request)](request)
        except IdentityConflict:
            code: ErrorCode = "identity_conflict"
        except AccountControlConflict:
            code = "identity_conflict"
        except KeyError:
            code = "not_found"
        except WorkflowNotFound:
            code = "not_found"
        except InvalidCommand:
            code = "invalid_request"
        except ValueError as exc:
            # Only sentences written for the owner are recorded; other messages may carry input.
            owner_facing = isinstance(exc, OwnerFacingError | BackupManifestError)
            log.warning(
                "request_refused operation=%s error=%s reason=%s",
                type(request).__name__,
                type(exc).__name__,
                str(exc)[:160] if owner_facing else "",
            )
            if isinstance(exc, OwnerFacingError):
                # A sentence written for the owner is said as written, whatever was asked.
                return reply(
                    request.version,
                    request.request_id,
                    error="invalid_request",
                    message=str(exc),
                )
            if isinstance(
                request,
                (
                    SaveManualCorrectionRequest,
                    PreviewManualOrderRequest,
                    ConfirmManualOrdersRequest,
                    GetManualCommandRequest,
                    ListManualCommandsRequest,
                    EvaluateHistoricalProfileRequest,
                    LearnGuruPlaybookRequest,
                    ReplayGuruPostsRequest,
                    CreateBackupRequest,
                    PreviewRestoreRequest,
                    PrepareRestoreCandidateRequest,
                    RestorePreflightRequest,
                    CompleteRestoreCandidateRequest,
                ),
            ):
                message = str(exc)
                if isinstance(exc, OwnerFacingError):
                    return reply(
                        request.version,
                        request.request_id,
                        error="invalid_request",
                        message=message,
                    )
                if isinstance(exc, BackupManifestError):
                    # Backup and restore reasons are fixed sentences without absolute paths.
                    return reply(
                        request.version,
                        request.request_id,
                        error="invalid_request",
                        message=f"{message[:1].upper()}{message[1:]}.",
                    )
                if "identity conflicts" in message:
                    code = "identity_conflict"
                elif (
                    "unavailable" in message
                    or "not available" in message
                    or "incomplete" in message
                ):
                    code = "unavailable"
                else:
                    code = "invalid_request"
                return reply(request.version, request.request_id, error=code)
            if isinstance(request, ASSISTANT_REQUESTS):
                code = "unavailable"
            elif isinstance(
                request,
                (
                    StartTradingRequest,
                    ValidateTradingRequest,
                    CheckConnectionRequest,
                    UpdateAccountLimitsRequest,
                    ControlAccountRequest,
                    ResolveOwnershipRequest,
                ),
            ):
                code = "invalid_request"
            else:
                raise
        except (
            ForeignInstallation,
            InstallationAlreadyRunning,
            StoreClosed,
            StoreUnavailable,
            UnknownSchemaVersion,
        ):
            code = "unavailable"
        except Exception as exc:
            # One request's failure is answered, never fatal: a correction or a manual order that
            # trips on bad local state must not take copying down with it. Messages may carry
            # input, so only the type is recorded.
            log.error(
                "request_failed operation=%s error=%s", type(request).__name__, type(exc).__name__
            )
            if not isinstance(
                request,
                (
                    SaveManualCorrectionRequest,
                    PreviewManualOrderRequest,
                    ConfirmManualOrdersRequest,
                    GetManualCommandRequest,
                    ListManualCommandsRequest,
                    GetTradingStatusRequest,
                    StartTradingRequest,
                    ValidateTradingRequest,
                    CheckConnectionRequest,
                    PauseTradingRequest,
                    UpdateAccountLimitsRequest,
                    ControlAccountRequest,
                    ResolveOwnershipRequest,
                    GetAccountsRequest,
                    GetSourceActivityRequest,
                    EvaluateHistoricalProfileRequest,
                    LearnGuruPlaybookRequest,
                    ReplayGuruPostsRequest,
                    GetAccountFeedRequest,
                    GetEquityHistoryRequest,
                    CreateBackupRequest,
                    PreviewRestoreRequest,
                    PrepareRestoreCandidateRequest,
                    RestorePreflightRequest,
                    CompleteRestoreCandidateRequest,
                    *ASSISTANT_REQUESTS,
                ),
            ):
                raise
            code = "unavailable"
        return reply(request.version, request.request_id, error=code)

    async def _on_submit(self, request: SubmitRequest) -> bytes:
        command = SubmitSelfTest(
            command_id=request.command.command_id,
            text=request.command.text,
            destination_ids=tuple(request.command.destination_ids),
        )
        workflow = await self._service.submit(command)
        self._session.process_after_reply = True
        return reply(
            request.version,
            request.request_id,
            ok={"type": "workflow", "workflow": workflow_payload(workflow)},
        )

    async def _on_get_status(self, request: GetStatusRequest) -> bytes:
        status = await self._queries.status(self._session.state)
        return reply(
            request.version,
            request.request_id,
            ok={"type": "status", "status": asdict(status)},
        )

    async def _on_get_workflow(self, request: GetWorkflowRequest) -> bytes:
        workflow = await self._queries.workflow(request.command_id)
        return reply(
            request.version,
            request.request_id,
            ok={"type": "workflow", "workflow": workflow_payload(workflow)},
        )

    async def _on_stop(self, request: StopRequest) -> bytes:
        self._session.stop()
        return reply(
            request.version,
            request.request_id,
            ok={"type": "stopping"},
        )

    @property
    def engine_state(self) -> EngineState:
        """The session's lifecycle state, for the services that stamp it on what they do."""
        return self._session.state

    async def _end_assistant(self) -> None:
        if self._assistant is not None:
            await self._assistant.reset()

    async def _wind_down(self) -> None:
        """Pause copying, then end any assistant turn, even if pausing fails."""
        try:
            if self._trading is not None and not self._restore_gated:
                await self._trading.lifecycle.pause()
        finally:
            await self._end_assistant()

    async def serve(self, reader: asyncio.StreamReader, writer: _Output) -> None:
        """Read bounded lines and drain every response asynchronously."""
        lines = _BoundedLineReader(reader)
        while True:
            item = await lines.read_line()
            if item is None:
                await self._wind_down()
                if not self._restore_gated:
                    await self._service.process_pending(max_items=_PROCESS_LIMIT)
                return

            raw_line, overlong = item
            response = await self.handle_line(raw_line, overlong=overlong)
            writer.write(response)
            await writer.drain()

            if self._session.process_after_reply:
                self._session.process_after_reply = False
                await self._service.process_pending(max_items=1)
            if self._session.stop_after_reply:
                self._session.stop_after_reply = False
                await self._wind_down()
                if not self._restore_gated:
                    await self._service.process_pending(max_items=_PROCESS_LIMIT)
                return


class _BoundedLineReader:
    def __init__(self, reader: asyncio.StreamReader) -> None:
        self._reader = reader
        self._buffer = bytearray()

    async def read_line(self) -> tuple[bytes, bool] | None:
        line = bytearray()
        overlong = False
        while True:
            newline = self._buffer.find(b"\n")
            if newline >= 0:
                segment = self._buffer[:newline]
                del self._buffer[: newline + 1]
                if not overlong and len(line) + len(segment) <= MAX_REQUEST_LINE_BYTES:
                    line.extend(segment)
                    if line.endswith(b"\r"):
                        line.pop()
                    return bytes(line), False
                return b"", True

            if self._buffer:
                segment = bytes(self._buffer)
                self._buffer.clear()
                if not overlong:
                    if len(line) + len(segment) > MAX_REQUEST_LINE_BYTES:
                        line.clear()
                        overlong = True
                    else:
                        line.extend(segment)

            chunk = await self._reader.read(_READ_CHUNK_BYTES)
            if not chunk:
                if overlong:
                    return b"", True
                if line:
                    return bytes(line), False
                return None
            self._buffer.extend(chunk)


def _header(payload: object) -> tuple[int, str]:
    if not isinstance(payload, dict):
        return 1, ""
    version_value = payload.get("version")
    version = version_value if type(version_value) is int else 1
    request_value = payload.get("request_id")
    request_id = ""
    if isinstance(request_value, str) and len(request_value) <= 128:
        try:
            request_value.encode("utf-8")
        except UnicodeEncodeError:
            pass
        else:
            request_id = request_value
    return version, request_id
