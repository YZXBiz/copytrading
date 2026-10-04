"""Human-readable parser decisions; transport and persistence are separate adapters."""

import hashlib
from datetime import datetime

from pydantic import AwareDatetime, TypeAdapter

from copytrading_engine.parsing.diagnostics import ValidationIssue
from copytrading_engine.shared.notification_models import NotificationIntent, NotificationPayload
from copytrading_engine.shared.signals import StockSignal

_SOURCE_TIMESTAMP_SERIALIZER = TypeAdapter(AwareDatetime)


def _serialize_source_timestamp(value: datetime) -> str:
    serialized = _SOURCE_TIMESTAMP_SERIALIZER.dump_python(value, mode="json")
    if not isinstance(serialized, str):
        raise TypeError("Source timestamp did not serialize to text")
    return serialized


def review_notification(
    key: str,
    result: StockSignal,
    issues: tuple[ValidationIssue, ...],
    *,
    observed_at: datetime | None = None,
) -> NotificationIntent:
    # Explanations are bounded source/model data; the Telegram renderer HTML-escapes them.
    reasons = {
        "invalid_model_output": "Model output failed schema validation",
        "model_output_budget_exceeded": "Model output exceeded the response budget",
        "provider_rejected": "Model provider rejected the request",
        "provider_key_rejected": "Model provider did not accept the API key",
        "provider_model_not_found": "Model provider has no model with that name",
        "decode_attempts_exhausted": "Model requests failed after bounded retries",
        "stale_signal": "Signal exceeded the permitted processing age",
        "future_signal": "Source timestamp is ahead of the parser clock beyond the allowed skew",
        "daily_model_request_budget_exhausted": "Daily model request budget exhausted",
        "evidence_validation_failed": "Extracted trade did not pass source-evidence checks",
        "source_not_configured": "Source has no configured parsing route",
        "no_text_to_decode": "Signal contained no text to interpret",
    }
    reason = result.reason if result.reason in reasons else "ambiguous_signal"
    explanations = {
        "entry_has_lot_reference": "A buy was incorrectly tied to an existing lot",
        "exit_missing_lot_reference": "An exit did not identify the original entry lot",
        "price_not_grounded": "The extracted price could not be verified in the source",
        "price_occurrence_reused": "One quoted price was incorrectly used for two roles",
        "action_not_grounded": "The proposed trade action was not supported by the source",
    }
    detail = "; ".join(
        f"{explanations.get(issue.code, 'Validation rejected this field')} "
        f"({issue.path}: {issue.code})"
        for issue in issues[:3]
    )
    source_at = _serialize_source_timestamp(result.timestamp)
    observed_at_text = observed_at.isoformat() if observed_at is not None else None
    return NotificationIntent(
        key=key,
        stream_id=key,
        payload=NotificationPayload(
            labels={
                "alertname": "SignalNeedsReview",
                "system": "copytrade",
                "job": "stock-parser",
                "severity": "warning",
                "signal_id": key,
            },
            annotations={
                "summary": "Signal needs review — automatic trading skipped",
                "evidence": reasons.get(reason, result.reason)
                + (f". Validation: {detail}" if detail else "")
                + ".",
                "impact": "The parser emitted no trade instructions for this signal. "
                "No order can be created from this parser result.",
                "action": (
                    "Check the source timestamp and host clock before deciding what to do. "
                    "Do not rewrite timestamps or replay the alert as a fresh trade."
                    if reason == "future_signal"
                    else "Inspect this signal before deciding what to do. "
                    "Do not replay an old alert as a fresh trade."
                ),
                "signal_id": key,
                "trace_id": hashlib.sha256(key.encode()).hexdigest()[:32],
                "reason": reason,
                "source_time": source_at,
                **({"observed_time": observed_at_text} if observed_at_text is not None else {}),
                "source_excerpt": " ".join(result.text.split())[:240],
            },
            starts_at=observed_at if observed_at is not None else result.timestamp,
        ),
    )


def decision_notification(
    key: str,
    result: StockSignal,
    issues: tuple[ValidationIssue, ...],
    *,
    observed_at: datetime | None = None,
) -> NotificationIntent:
    if result.decision == "review":
        return review_notification(key, result, issues, observed_at=observed_at)
    trade = result.decision == "trade"
    lines = []
    for instruction in result.instructions:
        action = {"buy": "BUY", "reduce": "TRIM", "close": "EXIT"}[instruction.action]
        line = f"{action} {instruction.symbol} at source price ${instruction.price}"
        if instruction.action != "buy":
            line += f"; original entry ${instruction.entry_price}"
            if instruction.action == "reduce":
                line += f"; fraction of original lot: {instruction.fraction}"
        lines.append(line)
    detail = "\n".join(lines)
    if len(detail) > 1800:
        detail = detail[:1800] + "… Full instructions are in the signal trace."
    source_at = _serialize_source_timestamp(result.timestamp)
    observed_at_text = observed_at.isoformat() if observed_at is not None else None
    return NotificationIntent(
        key=key,
        stream_id=key,
        payload=NotificationPayload(
            labels={
                "alertname": "SignalDecision",
                "system": "copytrade",
                "job": "stock-parser",
                "severity": "info",
                "signal_id": key,
                "notification_id": key,
            },
            annotations={
                "summary": "Trade signal parsed" if trade else "Signal ignored — no trade",
                "evidence": detail if trade else result.reason,
                "impact": "Parsing is complete. Risk checks and broker execution are separate; "
                "this message does not confirm an order or fill."
                if trade
                else "No order will be created from this parser decision.",
                "source_excerpt": " ".join(result.text.split())[:240],
                "signal_id": key,
                "source_time": source_at,
                **({"observed_time": observed_at_text} if observed_at_text is not None else {}),
                "trace_id": hashlib.sha256(key.encode()).hexdigest()[:32],
            },
            starts_at=observed_at if observed_at is not None else result.timestamp,
        ),
    )
