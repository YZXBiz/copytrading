"""The owner socket's contract: what the owner may ask a running server, and its answers.

Requests and answers are typed and checked where they cross the socket, so the server never
acts on a malformed line and the command line never reads the engine's internal JSON.
Proposals reuse the agent contract's own view, so both sides describe one approval the same way.
"""

import json
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, StrictBool, TypeAdapter

from copytrading_engine.control.wire import ProposalView


class _Message(BaseModel):
    model_config = ConfigDict(frozen=True, extra="forbid", hide_input_in_errors=True)


# Requests


class AskStatus(_Message):
    op: Literal["status"] = "status"


class SetEntries(_Message):
    op: Literal["entries"] = "entries"
    account: str = Field(pattern=r"^[a-zA-Z0-9_-]{1,64}$")
    enabled: StrictBool


class ListProposals(_Message):
    op: Literal["proposals"] = "proposals"


class Approve(_Message):
    """Approve exactly the proposal the owner was shown: its id and its digest."""

    op: Literal["approve"] = "approve"
    proposal_id: str = Field(pattern=r"^p-[0-9a-f]{12}$")
    digest: str = Field(pattern=r"^[0-9a-f]{64}$")


class Reject(_Message):
    op: Literal["reject"] = "reject"
    proposal_id: str = Field(pattern=r"^p-[0-9a-f]{12}$")


class Pause(_Message):
    op: Literal["pause"] = "pause"


class Resume(_Message):
    op: Literal["resume"] = "resume"


type OwnerRequest = Annotated[
    AskStatus | SetEntries | ListProposals | Approve | Reject | Pause | Resume,
    Field(discriminator="op"),
]
OWNER_REQUEST: TypeAdapter[OwnerRequest] = TypeAdapter(OwnerRequest)


# Answers


class AccountLine(BaseModel):
    """One account as the owner needs it; the engine's other status fields are ignored."""

    model_config = ConfigDict(frozen=True, extra="ignore")

    id: str
    state: str
    entry_permission: str
    error_code: str | None = None


class CopyingStatus(BaseModel):
    model_config = ConfigDict(frozen=True, extra="ignore")

    type: Literal["copying_status"] = "copying_status"
    state: str
    source_connected: bool
    model_ready: bool
    processed_signals: int
    error_code: str | None = None
    accounts: tuple[AccountLine, ...] = ()

    def summary(self) -> str:
        """One line for a log: copying's state, work done, and each account."""
        accounts = ", ".join(
            f"{account.id} {account.state}"
            + (" (entries on)" if account.entry_permission == "enabled" else "")
            for account in self.accounts
        )
        problem = f"; problem: {self.error_code.replace('_', ' ')}" if self.error_code else ""
        return (
            f"Copying {self.state}; {self.processed_signals} post(s) handled; {accounts}{problem}"
        )


class EntriesChanged(_Message):
    type: Literal["entries_changed"] = "entries_changed"
    account_id: str
    entry_permission: str


class Proposals(_Message):
    type: Literal["proposals"] = "proposals"
    items: tuple[ProposalView, ...]


class ProposalChanged(_Message):
    type: Literal["proposal_changed"] = "proposal_changed"
    proposal: ProposalView


class Refused(_Message):
    """The server could not do what was asked; the reason is plain text."""

    type: Literal["refused"] = "refused"
    reason: str


type OwnerAnswer = Annotated[
    CopyingStatus | EntriesChanged | Proposals | ProposalChanged | Refused,
    Field(discriminator="type"),
]
OWNER_ANSWER: TypeAdapter[OwnerAnswer] = TypeAdapter(OwnerAnswer)


def encode(message: BaseModel) -> bytes:
    return message.model_dump_json().encode() + b"\n"


def proposal_from_engine(value: object) -> ProposalView:
    """The engine's proposal JSON, checked against the published agent contract."""
    return ProposalView.model_validate_json(json.dumps(value))
