"""Serve agent control requests: decide, then read, pause, or propose, and audit every step."""

import datetime as dt
import json
from collections import OrderedDict
from collections.abc import Callable
from typing import Final, Protocol
from uuid import uuid4

from pydantic import BaseModel, ConfigDict, Field, ValidationError

from copytrading_engine.control import views, wire
from copytrading_engine.control.audit import Actor, AuditEntry, ControlAudit
from copytrading_engine.control.policy import (
    AccessLevel,
    Propose,
    RateWindow,
    Refuse,
    Run,
    decide,
    describe_refusal,
    tier,
)
from copytrading_engine.control.proposals import (
    Caller,
    ConfirmManualOrder,
    Outcome,
    Proposal,
    ProposalBook,
    ProposalRefused,
    ResumeAccount,
    SetRecovery,
    Subject,
)
from copytrading_engine.execution.domain.lifecycle import (
    AccountControlCommand,
    AccountControlConflict,
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
from copytrading_engine.trading.domain.status import TradingStatus
from copytrading_engine.trading.presentation.operator_models import SourceActivityPage

PREVIEW_CACHE_SIZE: Final = 32
AGENT_ACTOR: Final = "agent"


class ProcessingControl(Protocol):
    def status(self) -> TradingStatus: ...

    async def pause(self) -> TradingStatus: ...


class OperatorQueries(Protocol):
    async def account_overviews(
        self, before_account_id: str | None, limit: int
    ) -> AccountOverviewPage: ...

    async def source_activity(self, before_seq: int | None, limit: int) -> SourceActivityPage: ...

    async def account_events(
        self, account_id: str, before_seq: int | None, limit: int
    ) -> AccountEventPage: ...

    async def list_manual_commands(
        self, request: ManualCommandPageRequest
    ) -> ManualCommandPage: ...


class ManualControl(Protocol):
    async def control_account(self, command: AccountControlCommand) -> AccountControlResult: ...

    async def preview_manual_order(self, request: ManualPreviewRequest) -> ManualOrderPreview: ...

    async def confirm_manual_orders(
        self, requests: tuple[ManualConfirmationRequest, ...]
    ) -> ManualCommandsOutcome: ...

    async def manual_command_result(
        self, account_id: str, command_id: str
    ) -> ManualCommandResult: ...


class ControlContext(BaseModel):
    """What the app knows about a request: the owner's access choice, lock, and caller."""

    model_config = ConfigDict(frozen=True, extra="forbid", strict=True)

    access_level: AccessLevel
    unlocked: bool
    caller_pid: int | None = Field(default=None, ge=1)
    caller_path: str | None = Field(default=None, min_length=1, max_length=4096)


def _utc_now() -> dt.datetime:
    return dt.datetime.now(dt.UTC)


class ControlService:
    def __init__(
        self,
        processing: ProcessingControl,
        operator: OperatorQueries,
        manual: ManualControl,
        audit: ControlAudit,
        *,
        clock: Callable[[], dt.datetime] = _utc_now,
        book: ProposalBook | None = None,
        rate: RateWindow | None = None,
    ) -> None:
        self._processing = processing
        self._operator = operator
        self._manual = manual
        self._audit = audit
        self._clock = clock
        self._book = book if book is not None else ProposalBook(clock)
        self._rate = rate if rate is not None else RateWindow()
        self._previews: OrderedDict[str, ManualOrderPreview] = OrderedDict()

    async def handle(
        self, line: str, context: ControlContext, *, engine_state: str
    ) -> wire.Response:
        """Answer one agent request line with exactly one contract response."""
        caller = Caller(context.caller_pid, context.caller_path)
        request_id = _request_id(line)
        if len(line.encode()) > wire.MAX_LINE_BYTES:
            return await self._refused(request_id, caller, "invalid", None, "invalid_request")
        try:
            request = wire.REQUEST.validate_json(line)
        except ValidationError:
            return await self._refused(request_id, caller, "invalid", None, "invalid_request")
        operation = request.operation
        kind = tier(operation)
        # Pausing only reduces risk, so a flood of other requests never blocks it.
        if kind != "safer" and not self._rate.admit(self._clock()):
            return await self._refused(request_id, caller, operation, kind, "busy")

        decision = decide(operation, context.access_level, unlocked=context.unlocked)
        try:
            match decision:
                case Refuse(code=code):
                    return await self._refused(request_id, caller, operation, kind, code)
                case Run():
                    result = await self._run(request, engine_state)
                    outcome = "ok"
                    proposal_id = None
                case Propose():
                    proposal = self._propose(request, caller)
                    result = views.proposal(proposal)
                    outcome = "proposed"
                    proposal_id = proposal.proposal_id
        except ProposalRefused as refused:
            return await self._refused(request_id, caller, operation, kind, refused.code)
        except KeyError:
            return await self._refused(request_id, caller, operation, kind, "not_found")
        except AccountControlConflict:
            return await self._refused(request_id, caller, operation, kind, "conflict")
        except ValueError:
            return await self._refused(request_id, caller, operation, kind, "invalid_request")
        except Exception:  # noqa: BLE001 - an engine failure becomes a contract error, never a crash
            return await self._refused(request_id, caller, operation, kind, "unavailable")
        await self._record("agent", caller, operation, kind, outcome, proposal_id)
        return wire.Response(request_id=request_id, ok=result)

    async def approve(self, proposal_id: str, approved_digest: str) -> wire.ProposalView:
        """Perform an approved proposal exactly once; called only by the app after owner auth."""
        proposal = self._book.begin(proposal_id, approved_digest)
        owner = Caller(None, None)
        await self._record("owner", owner, "approve_proposal", "approval", "approved", proposal_id)
        result: Outcome
        code: str | None
        try:
            result, code = await self._perform(proposal)
        except KeyError:
            result, code = "failed", "not_found"
        except AccountControlConflict:
            result, code = "failed", "conflict"
        except ValueError:
            result, code = "failed", "invalid_request"
        except Exception:  # noqa: BLE001 - an unconfirmed broker effect is reported as unknown
            result, code = "outcome_unknown", None
        finished = self._book.finish(proposal_id, result, code)
        await self._record("owner", owner, "perform_proposal", "approval", result, proposal_id)
        return views.proposal(finished)

    async def reject(self, proposal_id: str) -> wire.ProposalView:
        rejected = self._book.reject(proposal_id)
        await self._record(
            "owner", Caller(None, None), "reject_proposal", "approval", "rejected", proposal_id
        )
        return views.proposal(rejected)

    async def audit_entries(self, limit: int) -> tuple[AuditEntry, ...]:
        """The newest decisions, for the owner's audit list in the app."""
        return await self._audit.recent(limit)

    def proposals(self) -> tuple[wire.ProposalView, ...]:
        return tuple(views.proposal(item) for item in self._book.all())

    async def discard_pending(self) -> int:
        count = self._book.discard_pending()
        if count:
            await self._record(
                "owner", Caller(None, None), "discard_proposals", None, f"discarded:{count}", None
            )
        return count

    async def _run(self, request: wire.Request, engine_state: str) -> wire.Result:
        match request:
            case wire.GetStatus():
                return views.status(engine_state, self._processing.status())
            case wire.ListAccounts(before_account_id=before, limit=limit):
                return views.accounts(await self._operator.account_overviews(before, limit))
            case wire.ListActivity(before_seq=before, limit=limit):
                return views.activity(await self._operator.source_activity(before, limit))
            case wire.ListAccountEvents(account_id=account_id, before_seq=before, limit=limit):
                return views.account_events(
                    await self._operator.account_events(account_id, before, limit)
                )
            case wire.ListManualCommands() as page:
                return views.manual_commands(
                    await self._operator.list_manual_commands(
                        ManualCommandPageRequest(
                            account_id=page.account_id,
                            source_id=page.source_id,
                            before_command_id=page.before_command_id,
                            limit=page.limit,
                        )
                    )
                )
            case wire.GetManualCommand(account_id=account_id, command_id=command_id):
                result = await self._manual.manual_command_result(account_id, command_id)
                return wire.ManualCommand(command=views.manual_command(result))
            case wire.PreviewManualOrder() as ask:
                preview = await self._manual.preview_manual_order(
                    ManualPreviewRequest(
                        preview_id=f"agent-{uuid4().hex}",
                        account_id=ask.account_id,
                        correction_id=ask.correction_id,
                        instruction_index=ask.instruction_index,
                    )
                )
                self._remember(preview)
                return views.manual_preview(preview)
            case wire.ListProposals():
                return wire.ProposalsPage(items=self.proposals())
            case wire.GetProposal(proposal_id=proposal_id):
                return views.proposal(self._book.get(proposal_id))
            case wire.PauseProcessing():
                return wire.ProcessingPaused(
                    processing=views.processing(await self._processing.pause())
                )
            case wire.PauseAccount(account_id=account_id):
                result = await self._manual.control_account(
                    AccountControlCommand(
                        command_id=f"agent-{uuid4().hex}", account_id=account_id, action="pause"
                    )
                )
                return views.account_control(result)
            case (
                wire.ProposeResumeAccount()
                | wire.ProposeRecoveryPreference()
                | wire.ProposeManualOrder()
            ):
                raise ValueError("Approval-tier requests are proposed, never run directly")

    def _propose(self, request: wire.Request, caller: Caller) -> Proposal:
        subject: Subject
        expires_by = None
        match request:
            case wire.ProposeResumeAccount(account_id=account_id):
                self._require_account(account_id)
                subject = ResumeAccount(account_id)
            case wire.ProposeRecoveryPreference(account_id=account_id, preference=preference):
                self._require_account(account_id)
                subject = SetRecovery(account_id, preference)
            case wire.ProposeManualOrder(account_id=account_id, preview_id=preview_id):
                preview = self._previews.get(preview_id)
                if preview is None or preview.request.account_id != account_id:
                    raise KeyError(preview_id)
                if preview.plan is None:
                    raise ValueError("A blocked preview cannot be proposed")
                subject = ConfirmManualOrder(
                    account_id=account_id,
                    preview_id=preview_id,
                    environment=preview.environment,
                    symbol=preview.plan.symbol,
                    side=preview.plan.side,
                    order_type=preview.plan.type,
                    quantity=preview.plan.qty,
                    limit_price=preview.plan.limit_price,
                )
                expires_by = preview.expires_at
            case _:
                raise ValueError("Only approval-tier requests become proposals")
        return self._book.propose(subject, caller, expires_by=expires_by)

    async def _perform(self, proposal: Proposal) -> tuple[Outcome, str | None]:
        match proposal.subject:
            case ResumeAccount(account_id=account_id):
                await self._manual.control_account(
                    AccountControlCommand(
                        command_id=proposal.command_id, account_id=account_id, action="resume"
                    )
                )
                return "succeeded", None
            case SetRecovery(account_id=account_id, preference=preference):
                await self._manual.control_account(
                    AccountControlCommand(
                        command_id=proposal.command_id,
                        account_id=account_id,
                        action="set_recovery",
                        recovery_preference=preference,
                    )
                )
                return "succeeded", None
            case ConfirmManualOrder(account_id=account_id, preview_id=preview_id):
                outcome = await self._manual.confirm_manual_orders(
                    (
                        ManualConfirmationRequest(
                            command_id=proposal.command_id,
                            preview_id=preview_id,
                            account_id=account_id,
                            actor=AGENT_ACTOR,
                        ),
                    )
                )
                return _manual_outcome(outcome, account_id, proposal.command_id)

    def _require_account(self, account_id: str) -> None:
        if all(account.id != account_id for account in self._processing.status().accounts):
            raise KeyError(account_id)

    def _remember(self, preview: ManualOrderPreview) -> None:
        now = self._clock()
        for key in [key for key, item in self._previews.items() if item.expires_at <= now]:
            del self._previews[key]
        self._previews[preview.request.preview_id] = preview
        while len(self._previews) > PREVIEW_CACHE_SIZE:
            self._previews.popitem(last=False)

    async def _refused(
        self,
        request_id: str,
        caller: Caller,
        operation: str,
        kind: str | None,
        code: wire.ErrorCode,
    ) -> wire.Response:
        await self._record("agent", caller, operation, kind, code, None)
        return wire.Response(
            request_id=request_id,
            error=wire.ErrorBody(code=code, message=describe_refusal(code)),
        )

    async def _record(
        self,
        actor: Actor,
        caller: Caller,
        operation: str,
        kind: str | None,
        outcome: str,
        proposal_id: str | None,
    ) -> None:
        await self._audit.record(
            AuditEntry(
                at=self._clock(),
                actor=actor,
                caller_pid=caller.pid,
                caller_path=caller.path,
                operation=operation,
                tier=kind if kind in ("read", "safer", "approval") else None,
                outcome=outcome,
                proposal_id=proposal_id,
            )
        )


def _manual_outcome(
    outcome: ManualCommandsOutcome, account_id: str, command_id: str
) -> tuple[Outcome, str | None]:
    matching = [
        item
        for item in outcome.outcomes
        if item.account_id == account_id and item.command_id == command_id
    ]
    if len(matching) != 1:
        return "outcome_unknown", None
    item = matching[0]
    if item.result is None:
        return "failed", item.error
    match item.result.status:
        case "prepared" | "accepted" | "partially_filled" | "filled":
            return "succeeded", item.result.status
        case "uncertain":
            return "outcome_unknown", item.result.status
        case "rejected" | "broker_rejected" | "cancelled" | "expired":
            return "failed", item.result.reason or item.result.status


def _request_id(line: str) -> str:
    """Echo a well-formed request ID even when the rest of the request is invalid."""
    try:
        payload = json.loads(line)
    except ValueError, RecursionError:
        return ""
    value = payload.get("request_id") if isinstance(payload, dict) else None
    return value if isinstance(value, str) and 0 < len(value) <= 128 else ""
