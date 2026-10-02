"""Owner-approved proposals: what an agent asked for, and whether it may run.

A proposal is created by an agent and performed only after the owner approves the exact
content they saw. Approval is accepted once, while the proposal is pending, before it
expires, and only with the digest of that content. Proposals live in memory: they last
minutes and end with the app's lock; durable facts belong to the audit trail and ledger.
"""

import datetime as dt
import hashlib
import json
import secrets
from collections import deque
from collections.abc import Callable
from dataclasses import asdict, dataclass, replace
from decimal import Decimal
from typing import Final, Literal
from uuid import uuid4

from copytrading_engine.control.wire import ErrorCode, RecoveryPreference

PROPOSAL_LIFETIME: Final = dt.timedelta(minutes=5)
REJECTION_LIMIT: Final = 3
REJECTION_WINDOW: Final = dt.timedelta(minutes=10)
COOLDOWN: Final = dt.timedelta(minutes=10)
RETENTION: Final = dt.timedelta(hours=1)


@dataclass(frozen=True, slots=True)
class ResumeAccount:
    account_id: str


@dataclass(frozen=True, slots=True)
class SetRecovery:
    account_id: str
    preference: RecoveryPreference


@dataclass(frozen=True, slots=True)
class ConfirmManualOrder:
    account_id: str
    preview_id: str
    environment: Literal["paper", "live"]
    symbol: str
    side: Literal["buy", "sell"]
    order_type: Literal["limit", "market"]
    quantity: Decimal
    limit_price: Decimal | None


type Subject = ResumeAccount | SetRecovery | ConfirmManualOrder
type Kind = Literal["resume_account", "set_recovery", "confirm_manual_order"]
type Outcome = Literal["succeeded", "failed", "outcome_unknown"]


def kind_of(subject: Subject) -> Kind:
    match subject:
        case ResumeAccount():
            return "resume_account"
        case SetRecovery():
            return "set_recovery"
        case ConfirmManualOrder():
            return "confirm_manual_order"


def digest(subject: Subject) -> str:
    """A stable fingerprint of exactly what the owner is asked to approve."""
    content = {"kind": kind_of(subject), **asdict(subject)}
    encoded = json.dumps(content, sort_keys=True, separators=(",", ":"), default=str)
    return hashlib.sha256(encoded.encode()).hexdigest()


@dataclass(frozen=True, slots=True)
class Caller:
    pid: int | None
    path: str | None


@dataclass(frozen=True, slots=True)
class Pending:
    pass


@dataclass(frozen=True, slots=True)
class Running:
    approved_at: dt.datetime


@dataclass(frozen=True, slots=True)
class Finished:
    result: Outcome
    code: str | None
    finished_at: dt.datetime


@dataclass(frozen=True, slots=True)
class Closed:
    reason: Literal["rejected", "expired", "discarded"]
    closed_at: dt.datetime


type State = Pending | Running | Finished | Closed


@dataclass(frozen=True, slots=True)
class Proposal:
    proposal_id: str
    subject: Subject
    digest: str
    command_id: str
    caller: Caller
    created_at: dt.datetime
    expires_at: dt.datetime
    state: State

    @property
    def kind(self) -> Kind:
        return kind_of(self.subject)


class ProposalRefused(Exception):
    """A proposal cannot be created or advanced; `code` says why."""

    def __init__(self, code: ErrorCode) -> None:
        super().__init__(code)
        self.code: ErrorCode = code


class ProposalBook:
    """Hold proposals and enforce their limits; every transition is synchronous."""

    def __init__(
        self,
        clock: Callable[[], dt.datetime],
        *,
        lifetime: dt.timedelta = PROPOSAL_LIFETIME,
        rejection_limit: int = REJECTION_LIMIT,
        rejection_window: dt.timedelta = REJECTION_WINDOW,
        cooldown: dt.timedelta = COOLDOWN,
    ) -> None:
        self._clock = clock
        self._lifetime = lifetime
        self._rejection_limit = rejection_limit
        self._rejection_window = rejection_window
        self._cooldown = cooldown
        self._proposals: dict[str, Proposal] = {}
        self._rejections: deque[dt.datetime] = deque()
        self._cooling_until: dt.datetime | None = None

    def propose(
        self,
        subject: Subject,
        caller: Caller,
        *,
        expires_by: dt.datetime | None = None,
    ) -> Proposal:
        now = self._clock()
        self._expire(now)
        if self._cooling_until is not None and now < self._cooling_until:
            raise ProposalRefused("cooling_down")
        kind = kind_of(subject)
        if any(
            item.kind == kind and isinstance(item.state, Pending)
            for item in self._proposals.values()
        ):
            raise ProposalRefused("proposal_limit")
        expires_at = now + self._lifetime
        if expires_by is not None:
            expires_at = min(expires_at, expires_by)
        if expires_at <= now:
            raise ProposalRefused("expired")
        proposal = Proposal(
            proposal_id=f"p-{secrets.token_hex(6)}",
            subject=subject,
            digest=digest(subject),
            command_id=f"agent-{uuid4().hex}",
            caller=caller,
            created_at=now,
            expires_at=expires_at,
            state=Pending(),
        )
        self._proposals[proposal.proposal_id] = proposal
        return proposal

    def get(self, proposal_id: str) -> Proposal:
        self._expire(self._clock())
        try:
            return self._proposals[proposal_id]
        except KeyError:
            raise ProposalRefused("not_found") from None

    def all(self) -> tuple[Proposal, ...]:
        self._expire(self._clock())
        return tuple(sorted(self._proposals.values(), key=lambda item: item.created_at))

    def pending(self) -> tuple[Proposal, ...]:
        return tuple(item for item in self.all() if isinstance(item.state, Pending))

    def begin(self, proposal_id: str, approved_digest: str) -> Proposal:
        """Accept the owner's approval once; the caller then performs the action."""
        proposal = self.get(proposal_id)
        if isinstance(proposal.state, Closed) and proposal.state.reason == "expired":
            raise ProposalRefused("expired")
        if not isinstance(proposal.state, Pending):
            raise ProposalRefused("conflict")
        if approved_digest != proposal.digest:
            raise ProposalRefused("conflict")
        return self._store(replace(proposal, state=Running(self._clock())))

    def finish(
        self,
        proposal_id: str,
        result: Outcome,
        code: str | None = None,
    ) -> Proposal:
        proposal = self._proposals[proposal_id]
        if not isinstance(proposal.state, Running):
            raise ProposalRefused("conflict")
        return self._store(replace(proposal, state=Finished(result, code, self._clock())))

    def reject(self, proposal_id: str) -> Proposal:
        proposal = self.get(proposal_id)
        if not isinstance(proposal.state, Pending):
            raise ProposalRefused("conflict")
        now = self._clock()
        while self._rejections and now - self._rejections[0] >= self._rejection_window:
            self._rejections.popleft()
        self._rejections.append(now)
        if len(self._rejections) >= self._rejection_limit:
            self._cooling_until = now + self._cooldown
            self._rejections.clear()
        return self._store(replace(proposal, state=Closed("rejected", now)))

    def discard_pending(self) -> int:
        """Close every waiting proposal, as when the app locks or quits."""
        now = self._clock()
        waiting = [item for item in self._proposals.values() if isinstance(item.state, Pending)]
        for item in waiting:
            self._store(replace(item, state=Closed("discarded", now)))
        return len(waiting)

    def _expire(self, now: dt.datetime) -> None:
        for item in list(self._proposals.values()):
            if isinstance(item.state, Pending) and now >= item.expires_at:
                self._store(replace(item, state=Closed("expired", now)))
            elif isinstance(item.state, Finished | Closed) and now - item.created_at > RETENTION:
                del self._proposals[item.proposal_id]

    def _store(self, proposal: Proposal) -> Proposal:
        self._proposals[proposal.proposal_id] = proposal
        return proposal
