"""Which control operations may run, which need the owner, and how fast callers may ask."""

import datetime as dt
from collections import deque
from dataclasses import dataclass
from typing import Final, Literal, assert_never

from copytrading_engine.control.wire import ErrorCode, Operation

type Tier = Literal["read", "safer", "approval"]
type AccessLevel = Literal["read_pause", "propose"]

RATE_LIMIT: Final = 30
RATE_WINDOW: Final = dt.timedelta(seconds=10)


def tier(operation: Operation) -> Tier:
    """Classify every operation; adding one without a tier fails type checking."""
    match operation:
        case (
            "get_status"
            | "list_accounts"
            | "list_activity"
            | "list_account_events"
            | "list_manual_commands"
            | "get_manual_command"
            | "preview_manual_order"
            | "list_proposals"
            | "get_proposal"
        ):
            return "read"
        case "pause_processing" | "pause_account":
            return "safer"
        case "propose_resume_account" | "propose_recovery_preference" | "propose_manual_order":
            return "approval"
        case _:
            assert_never(operation)


@dataclass(frozen=True, slots=True)
class Run:
    """Perform the operation now."""


@dataclass(frozen=True, slots=True)
class Propose:
    """Record a proposal; only the owner's approval performs it."""


@dataclass(frozen=True, slots=True)
class Refuse:
    code: ErrorCode


type Decision = Run | Propose | Refuse


def decide(operation: Operation, access: AccessLevel, *, unlocked: bool) -> Decision:
    """Pausing is always allowed; everything else needs an unlocked app, and proposals need
    the owner to have granted the propose level."""
    kind = tier(operation)
    if kind == "safer":
        return Run()
    if not unlocked:
        return Refuse("locked")
    if kind == "read":
        return Run()
    if access != "propose":
        return Refuse("forbidden")
    return Propose()


class RateWindow:
    """Admit at most `limit` requests in any trailing `window`."""

    def __init__(self, limit: int = RATE_LIMIT, window: dt.timedelta = RATE_WINDOW) -> None:
        if limit < 1:
            raise ValueError("A rate window must admit at least one request")
        self._limit = limit
        self._window = window
        self._admitted: deque[dt.datetime] = deque()

    def admit(self, now: dt.datetime) -> bool:
        while self._admitted and now - self._admitted[0] >= self._window:
            self._admitted.popleft()
        if len(self._admitted) >= self._limit:
            return False
        self._admitted.append(now)
        return True


def describe_refusal(code: ErrorCode) -> str:
    """A message a person or agent can act on."""
    match code:
        case "access_off":
            return "Agent access is turned off in CopyTrading."
        case "locked":
            return "Unlock CopyTrading first."
        case "forbidden":
            return "Agent access allows reading and pausing only; proposals are not enabled."
        case "invalid_request":
            return "The request is not valid."
        case "not_found":
            return "Nothing matches that identifier."
        case "unavailable":
            return "The engine cannot answer right now."
        case "busy":
            return "Too many requests; wait a few seconds."
        case "cooling_down":
            return "Proposals are paused after repeated rejections; try again later."
        case "proposal_limit":
            return "A proposal of this kind is already waiting for the owner."
        case "conflict":
            return "The proposal changed or is no longer waiting."
        case "expired":
            return "The proposal expired before the owner approved it."
        case "rejected":
            return "The owner rejected the proposal."
        case _:
            assert_never(code)
