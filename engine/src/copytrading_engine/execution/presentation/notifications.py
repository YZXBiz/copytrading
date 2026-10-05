"""Translate committed execution facts into notifications; never infer a fill from an intent."""

import hashlib
from decimal import Decimal

from copytrading_engine.execution.domain.events import (
    CancelRequested,
    JournalEvent,
    LateOrderIncidentCleared,
    LateOrderIncidentOpened,
    LateOrderIncidentReopened,
    Message,
    MessageDone,
    OrderIntentReleased,
    OrderUpdate,
    SubmissionAborted,
    SubmissionUncertain,
    SubmitError,
)
from copytrading_engine.execution.domain.events import Skipped as SkippedEvent
from copytrading_engine.execution.domain.ledger_state import HELD_FOR_OWNER, LedgerSnapshot
from copytrading_engine.execution.domain.order_lifecycle import OrderStatus
from copytrading_engine.execution.domain.progress import Skipped as SkippedInstruction
from copytrading_engine.shared.notification_models import NotificationIntent, NotificationPayload

REASONS = {
    "insufficient_cash": "Insufficient cash for this entry",
    "daily_loss_cap": "Daily loss limit reached; new entries are blocked",
    "daily_entry_cap": "Daily entry limit reached",
    "symbol_exposure_cap": "Symbol exposure limit reached",
    "total_exposure_cap": "Total exposure limit reached",
    "symbol_and_total_exposure_cap": "Symbol and total exposure limits reached",
    "account_blocked": "The broker account is blocked from trading",
    "halted": "New entries are paused by the operator",
    "stopping": "Execution is stopping before order submission",
    "session_changed": "The eligible market session changed before order submission",
    "stale": "The signal exceeded the permitted age",
    "out_of_order": "A newer trade signal was already processed",
    "missing_or_ambiguous_lot": "No unique copier-owned lot matches the quoted entry price",
    "unsupported_asset": "The broker does not support trading this asset",
    "outside_session": "The broker session is not eligible for this order",
    "below_minimum_quantity": "The allowed size is below the asset's minimum quantity",
    "position_mismatch": "Broker holdings do not match the copier ledger",
    "portfolio_mismatch": "New entry blocked: account holdings do not match the copier ledger",
    "external_open_order": "An external order already exists for this asset",
    "insufficient_owned_shares": "The copier does not own enough shares for this exit",
    "duplicate": "This instruction duplicates a recent signal",
    "price_moved": "The market is too far from the guru's price, so this account didn't buy on "
    "its own. Open Activity to copy or skip it; it expires when its trading day ends",
    "approval_required": "This account asks you to approve every order, so it didn't send "
    "this one. Open Activity to approve or skip it; it expires when its trading day ends",
}


def execution_notification(
    snapshot: LedgerSnapshot, event: JournalEvent
) -> NotificationIntent | None:
    payload = event.payload
    signal_id = getattr(payload, "message_id", None)
    if signal_id is None or signal_id not in snapshot.messages:
        return None
    message = snapshot.messages[signal_id]
    client_id = getattr(payload, "client_id", None)
    order = snapshot.orders.get(client_id) if client_id is not None else None
    category = "info"
    key = f"{signal_id}:{payload.kind}"
    detail = ""
    if isinstance(payload, Message) and payload.status in {"stale", "out_of_order"}:
        title = "Trade skipped"
        detail = REASONS[payload.status]
    elif isinstance(payload, Message) and payload.status == "review_required":
        title = "Waiting for you"
        detail = (
            "The post names no size and this account waits for you on such calls. "
            "Open Activity to copy or skip it; it expires when its trading day ends"
        )
        category = "warning"
    elif isinstance(payload, SkippedEvent):
        part = payload.part
        instruction = message.instructions[part]
        reason = payload.reason
        waits = reason in HELD_FOR_OWNER
        title = f"{instruction.symbol} — {'waiting for you' if waits else 'trade skipped'}"
        detail = REASONS.get(reason, reason.replace("_", " "))
        for breach in payload.exposure or ():
            detail += (
                f". {breach.scope.capitalize()} cost exposure "
                f"${format(breach.current.normalize(), 'f')} + proposed budget "
                f"${format(breach.proposed.normalize(), 'f')} "
                f"> ${format(breach.limit.normalize(), 'f')} limit"
            )
        key += f":{part}"
    elif isinstance(payload, MessageDone) and any(
        isinstance(part, SkippedInstruction) and part.reason == "duplicate"
        for part in message.parts
    ):
        title = "Duplicate instruction skipped"
        detail = REASONS["duplicate"]
    elif order is not None:
        side = order.side.upper()
        key = f"{order.client_id}:{payload.kind}"
        if isinstance(payload, OrderUpdate):
            state = order.status.value
            if order.status is OrderStatus.UNRECOGNIZED:
                raw_status = order.raw_broker_status or payload.raw_broker_status
                key += f":{state}:{raw_status}:{order.filled_qty.normalize()}"
                title = f"{side} {order.symbol} — broker status quarantined"
                detail = (
                    f"Alpaca reported unrecognized status '{raw_status}'. "
                    "This order remains reserved and will be reconciled. No cancellation "
                    "or resubmission was requested."
                )
                category = "warning"
            else:
                key += f":{state}:{order.filled_qty.normalize()}"
            titles = {
                "pending_new": "submission received — acceptance pending",
                "new": "order accepted",
                "accepted": "order accepted",
                "partially_filled": "partially filled",
                "filled": "filled",
                "canceled": "canceled",
                "expired": "expired",
                "rejected": "rejected",
                "pending_cancel": "cancellation pending",
                "done_for_day": "done for day",
                "replaced": "replaced",
                "stopped": "stopped",
                "suspended": "suspended",
                "calculated": "calculated",
                "accepted_for_bidding": "accepted for bidding",
            }
            if order.status is not OrderStatus.UNRECOGNIZED:
                title = f"{side} {order.symbol} — {titles.get(state, state.replace('_', ' '))}"
                if state in {"rejected", "canceled", "expired", "suspended", "stopped"}:
                    category = "warning"
                pricing = (
                    "Market order." if order.type == "market" else f"Limit: ${order.limit_price}."
                )
                detail = f"Filled: {order.filled_qty} of {order.qty} shares. {pricing}"
                average = payload.filled_avg_price
                if average is not None and order.filled_qty:
                    total = (Decimal(str(average)) * order.filled_qty).quantize(Decimal("0.01"))
                    detail += f" Average fill: ${average}. Filled value: ${total}."
        elif isinstance(payload, OrderIntentReleased):
            key += f":{event.at.isoformat()}"
            title = f"{side} {order.symbol} — uncertain intent released"
            detail = (
                f"Client order ID {order.client_id} was released by "
                f"{payload.evidence.actor} "
                f"after broker-history review: {payload.evidence.reason}. "
                "The original signal will not be resubmitted; broker lookup continues."
            )
            category = "warning"
        elif isinstance(payload, (LateOrderIncidentOpened, LateOrderIncidentReopened)):
            key += f":{event.at.isoformat()}"
            action = "reopened" if isinstance(payload, LateOrderIncidentReopened) else "opened"
            raw_status = order.raw_broker_status or payload.raw_broker_status
            title = f"{side} {order.symbol} — late broker order incident {action}"
            detail = (
                f"Released client ID {order.client_id} appeared at Alpaca as broker order "
                f"{order.broker_id} with status '{raw_status}' and "
                f"{order.filled_qty} filled shares. "
                "All new buys are halted until offline operator clearance follows a fresh matched "
                "position audit. Reconciliation and safe matched-lot exits continue."
            )
            category = "critical"
        elif isinstance(payload, LateOrderIncidentCleared):
            key += f":{event.at.isoformat()}"
            title = f"{side} {order.symbol} — late broker order incident cleared"
            audit_ref = payload.evidence.matched_audit_ref or "recorded evidence"
            detail = (
                f"{payload.evidence.actor} cleared client ID {order.client_id} after a "
                f"matched position audit ({audit_ref}). "
                f"Reason: {payload.evidence.reason}."
            )
        elif isinstance(payload, (SubmissionUncertain, SubmitError)):
            title = f"{side} {order.symbol} — submission {order.status}"
            detail = "Broker reconciliation will determine the outcome. Do not submit a duplicate."
            if order.status == "rejected":
                http_status = payload.http_status if isinstance(payload, SubmitError) else None
                detail = f"Alpaca rejected submission (HTTP {http_status})."
            key += f":{order.status}"
            category = "warning"
        elif isinstance(payload, SubmissionAborted):
            title = f"{side} {order.symbol} — trade skipped before submission"
            detail = REASONS.get(payload.reason, payload.reason)
            detail += ". No broker request was sent."
            category = "warning"
        elif isinstance(payload, CancelRequested):
            title = f"{side} {order.symbol} — cancellation requested"
            detail = "Cancellation is not yet confirmed. An order update will report the result."
        else:
            return None
    else:
        return None
    return NotificationIntent(
        key=key,
        stream_id=signal_id,
        payload=NotificationPayload(
            labels={
                "alertname": "TradeActivity",
                "system": "copytrade",
                "job": "execution",
                "severity": category,
                "signal_id": signal_id,
                "notification_id": key,
            },
            annotations={
                "summary": title,
                "evidence": detail,
                "source_excerpt": " ".join(message.text.split())[:240],
                "signal_id": signal_id,
                "source_time": message.timestamp.isoformat(),
                "trace_id": hashlib.sha256(signal_id.encode()).hexdigest()[:32],
            },
            starts_at=event.at,
        ),
    )
