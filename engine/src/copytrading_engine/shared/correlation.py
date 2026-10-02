"""Persisted workflow lineage propagated through one async attempt."""

from contextvars import ContextVar, Token
from dataclasses import dataclass
from types import TracebackType
from typing import Self


@dataclass(frozen=True, slots=True)
class WorkflowAttempt:
    workflow_id: str
    trace_id: str
    destination_id: str | None
    attempt: int


_CURRENT_ATTEMPT: ContextVar[WorkflowAttempt | None] = ContextVar(
    "copytrading_engine_workflow_attempt", default=None
)


class _BoundAttempt:
    def __init__(self, value: WorkflowAttempt) -> None:
        self._value = value
        self._token: Token[WorkflowAttempt | None] | None = None

    def __enter__(self) -> Self:
        self._token = _CURRENT_ATTEMPT.set(self._value)
        return self

    def __exit__(
        self,
        exc_type: type[BaseException] | None,
        exc_value: BaseException | None,
        traceback: TracebackType | None,
    ) -> None:
        if self._token is not None:
            _CURRENT_ATTEMPT.reset(self._token)


def bind_workflow_attempt(value: WorkflowAttempt) -> _BoundAttempt:
    """Bind durable correlation only for this task's provider/account call."""
    return _BoundAttempt(value)


def current_workflow_attempt() -> WorkflowAttempt | None:
    return _CURRENT_ATTEMPT.get()
