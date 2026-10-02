"""Contract response lines: one JSON object per reply, with a result or an error."""

import json
from dataclasses import asdict
from typing import Literal

from copytrading_engine.host.self_test.model import WorkflowView
from copytrading_engine.trading.domain.status import TradingStatus

type ErrorCode = Literal["invalid_request", "identity_conflict", "unavailable", "not_found"]


def workflow_payload(workflow: WorkflowView) -> dict[str, object]:
    return {
        "command_id": workflow.command_id,
        "stage": workflow.stage.value,
        "outcomes": [
            {"account_id": outcome.account_id, "result": outcome.result}
            for outcome in workflow.outcomes
        ],
        "trace_id": workflow.trace_id,
    }


def trading_reply(version: int, request_id: str, status: TradingStatus) -> bytes:
    value = asdict(status)
    value["oldest_pending_source_at"] = (
        status.oldest_pending_source_at.isoformat() if status.oldest_pending_source_at else None
    )
    value["oldest_pending_signal_at"] = (
        status.oldest_pending_signal_at.isoformat() if status.oldest_pending_signal_at else None
    )
    return reply(
        version,
        request_id,
        ok={"type": "trading_status", "trading": value},
    )


def reply(
    version: int,
    request_id: str,
    *,
    ok: dict[str, object] | None = None,
    error: ErrorCode | None = None,
    message: str | None = None,
) -> bytes:
    if (ok is None) == (error is None):
        raise ValueError("a response must contain exactly one of ok or error")
    envelope: dict[str, object] = {"version": version, "request_id": request_id}
    if ok is not None:
        envelope["ok"] = ok
    else:
        envelope["error"] = (
            {"code": error} if message is None else {"code": error, "message": message}
        )
    return (json.dumps(envelope, separators=(",", ":"), ensure_ascii=False) + "\n").encode()
