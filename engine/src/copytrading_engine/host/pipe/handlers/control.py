"""Agent control through the app: commands, proposals, and the audit trail."""

from copytrading_engine.control.proposals import ProposalRefused
from copytrading_engine.control.service import ControlService
from copytrading_engine.host.pipe.requests import (
    AgentAuditRequest,
    ApproveProposalRequest,
    ControlRequest,
    DiscardProposalsRequest,
    ListProposalsRequest,
    PipeRequest,
    RejectProposalRequest,
    RequestHandler,
)
from copytrading_engine.host.pipe.responses import ErrorCode, reply
from copytrading_engine.host.pipe.session import PipeSession


class ControlHandlers:
    """Route agent control lines to the control service, stamped with the engine state."""

    def __init__(
        self,
        *,
        control: ControlService | None,
        session: PipeSession,
    ) -> None:
        self._control = control
        self._session = session

    def handlers(self) -> dict[type[PipeRequest], RequestHandler]:
        return {
            ControlRequest: self._handle_control,
            ListProposalsRequest: self._handle_control,
            ApproveProposalRequest: self._handle_control,
            RejectProposalRequest: self._handle_control,
            DiscardProposalsRequest: self._handle_control,
            AgentAuditRequest: self._handle_control,
        }

    async def _handle_control(
        self,
        request: ControlRequest
        | ListProposalsRequest
        | ApproveProposalRequest
        | RejectProposalRequest
        | DiscardProposalsRequest
        | AgentAuditRequest,
    ) -> bytes:
        """Serve agent control; only the app, after owner authentication, approves."""
        control = self._control
        if control is None:
            return reply(request.version, request.request_id, error="unavailable")
        if isinstance(request, ControlRequest):
            response = await control.handle(
                request.line, request.context, engine_state=self._session.state
            )
            return reply(
                request.version,
                request.request_id,
                # The exact contract line, so the app relays bytes it never reinterprets.
                ok={"type": "control", "line": response.model_dump_json()},
            )
        if isinstance(request, ListProposalsRequest):
            return reply(
                request.version,
                request.request_id,
                ok={
                    "type": "proposals",
                    "proposals": [item.model_dump(mode="json") for item in control.proposals()],
                },
            )
        if isinstance(request, AgentAuditRequest):
            entries = await control.audit_entries(request.limit)
            return reply(
                request.version,
                request.request_id,
                ok={
                    "type": "agent_audit",
                    "entries": [
                        {
                            "at": entry.at.isoformat(),
                            "actor": entry.actor,
                            "caller_pid": entry.caller_pid,
                            "caller_path": entry.caller_path,
                            "operation": entry.operation,
                            "tier": entry.tier,
                            "outcome": entry.outcome,
                            "proposal_id": entry.proposal_id,
                        }
                        for entry in entries
                    ],
                },
            )
        if isinstance(request, DiscardProposalsRequest):
            count = await control.discard_pending()
            return reply(
                request.version,
                request.request_id,
                ok={"type": "proposals_discarded", "count": count},
            )
        try:
            if isinstance(request, ApproveProposalRequest):
                proposal = await control.approve(request.proposal_id, request.digest)
            else:
                proposal = await control.reject(request.proposal_id)
        except ProposalRefused as refused:
            code: ErrorCode = "not_found" if refused.code == "not_found" else "invalid_request"
            return reply(request.version, request.request_id, error=code)
        return reply(
            request.version,
            request.request_id,
            ok={"type": "proposal", "proposal": proposal.model_dump(mode="json")},
        )
