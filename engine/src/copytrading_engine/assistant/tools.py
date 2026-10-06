"""The assistant's hands: each tool is one agent-control request, audited under its caller name."""

import datetime as dt
import json
import uuid
from collections.abc import Callable, Mapping

from copytrading_engine.assistant import insights
from copytrading_engine.assistant.conversation import AssistantLink, Turn
from copytrading_engine.control import wire
from copytrading_engine.control.service import ControlContext, ControlService

# The audit trail names the caller of every control request; the assistant is one, in process.
ASSISTANT_CALLER = "CopyTrading Assistant"
CONTEXT = ControlContext(access_level="propose", unlocked=True, caller_path=ASSISTANT_CALLER)

# What each tool did, added once it has done it.
STEP = {
    "get_status": "Checked whether copying is running",
    "list_accounts": "Looked at your accounts",
    "list_activity": "Read recent posts",
    "list_account_events": "Read {account_id}'s history",
    "list_proposals": "Checked what is waiting for you",
    "pause_processing": "Paused copying",
    "pause_account": "Paused new entries for {account_id}",
    "propose_resume_account": "Asked you to approve resuming {account_id}",
    "propose_recovery_preference": "Asked you to approve {account_id}'s after-restart setting",
    "guru_record": "Added up {guru}'s calls",
    "explain_skip": "Looked at that post",
}

# What each tool tried, when the engine refused it, so a refusal never reads as done.
REFUSED_STEP = {
    "get_status": "Couldn't check whether copying is running",
    "list_accounts": "Couldn't look at your accounts",
    "list_activity": "Couldn't read recent posts",
    "list_account_events": "Couldn't read {account_id}'s history",
    "list_proposals": "Couldn't check what is waiting for you",
    "pause_processing": "Couldn't pause copying",
    "pause_account": "Couldn't pause new entries for {account_id}",
    "propose_resume_account": "Couldn't ask you to approve resuming {account_id}",
    "propose_recovery_preference": (
        "Couldn't ask you to approve {account_id}'s after-restart setting"
    ),
    "explain_skip": "Couldn't find that post",
}


# A turn the owner cancelled, or that was dropped, must never reach the engine.
CANCELLED = {"refused": "cancelled"}


class AssistantTools:
    def __init__(
        self,
        control: ControlService,
        operator: insights.Operator,
        turn: Turn,
        *,
        engine_state: Callable[[], str],
        now: Callable[[], dt.datetime],
        guru_names: Mapping[str, str] | None = None,
    ) -> None:
        self._control = control
        self._operator = operator
        self._turn = turn
        self._engine_state = engine_state
        self._now = now
        self._guru_names = dict(guru_names or {})

    def _guru(self, guru: str) -> tuple[str, str]:
        """The guru's id and display name, whether the model passed the id or the name."""
        if guru in self._guru_names:
            return guru, self._guru_names[guru]
        wanted = guru.strip().casefold()
        for guru_id, name in self._guru_names.items():
            if name.strip().casefold() == wanted:
                return guru_id, name
        return guru, guru

    async def _ask(self, operation: str, **values: object) -> dict:
        if self._turn.cancelled:
            return CANCELLED
        line = json.dumps(
            {
                "schema_version": wire.SCHEMA_VERSION,
                "request_id": f"a-{uuid.uuid4().hex[:12]}",
                "operation": operation,
                **values,
            }
        )
        response = await self._control.handle(line, CONTEXT, engine_state=self._engine_state())
        if response.error is not None:
            self._turn.add_step(REFUSED_STEP[operation].format(**values))
            return {"refused": response.error.code}
        assert response.ok is not None
        self._turn.add_step(STEP[operation].format(**values))
        result = response.ok.model_dump(mode="json")
        if isinstance(response.ok, wire.ProposalView):
            # The proposal card already names the account, so it carries no extra link.
            self._turn.add_proposal(response.ok.proposal_id)
        elif "account_id" in values:
            account_id = str(values["account_id"])
            self._turn.add_link(AssistantLink(kind="account", id=account_id, title=account_id))
        return result

    async def get_status(self) -> dict:
        return await self._ask("get_status")

    async def list_accounts(self) -> dict:
        return await self._ask("list_accounts")

    async def list_activity(self, limit: int = 25) -> dict:
        return await self._ask("list_activity", limit=limit)

    async def list_account_events(self, account_id: str, limit: int = 25) -> dict:
        return await self._ask("list_account_events", account_id=account_id, limit=limit)

    async def list_proposals(self) -> dict:
        return await self._ask("list_proposals")

    async def pause_processing(self) -> dict:
        return await self._ask("pause_processing")

    async def pause_account(self, account_id: str) -> dict:
        return await self._ask("pause_account", account_id=account_id)

    async def propose_resume_account(self, account_id: str) -> dict:
        return await self._ask("propose_resume_account", account_id=account_id)

    async def propose_recovery_preference(self, account_id: str, preference: str) -> dict:
        return await self._ask(
            "propose_recovery_preference", account_id=account_id, preference=preference
        )

    async def guru_record(self, guru_id: str, days: int = 7) -> dict:
        if self._turn.cancelled:
            return CANCELLED
        guru_id, name = self._guru(guru_id)
        record = await insights.guru_record(self._operator, guru_id, days, self._now())
        self._turn.add_step(STEP["guru_record"].format(guru=name))
        self._turn.add_link(AssistantLink(kind="guru", id=guru_id, title=name))
        return record.model_dump(mode="json") | {"guru_name": name}

    async def explain_skip(self, source_id: str) -> dict:
        if self._turn.cancelled:
            return CANCELLED
        try:
            explanation = await insights.explain_skip(self._operator, source_id)
        except KeyError:
            self._turn.add_step(REFUSED_STEP["explain_skip"])
            return {"refused": "not_found"}
        self._turn.add_step(STEP["explain_skip"])
        self._turn.add_link(AssistantLink(kind="post", id=source_id, title="Open in Activity"))
        return explanation.model_dump(mode="json")
