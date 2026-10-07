"""Preview and explicitly confirm immutable reviewed order corrections."""

import datetime as dt
import hashlib
import json
import logging
from collections.abc import Callable
from decimal import Decimal
from typing import Literal

from copytrading_engine.execution.application.engine import CopyEngine
from copytrading_engine.execution.application.ports import BrokerError, QuoteBroker
from copytrading_engine.execution.domain.ledger_state import LedgerSnapshot
from copytrading_engine.execution.domain.manual_commands import (
    ManualCheck,
    ManualCommandPage,
    ManualCommandRecord,
    ManualCommandResult,
    ManualConfirmationRequest,
    ManualCorrectionRecord,
    ManualOrderPreview,
    ManualPreviewRequest,
)
from copytrading_engine.execution.domain.market import Quote
from copytrading_engine.execution.domain.order_lifecycle import OrderStatus
from copytrading_engine.execution.domain.orders import OrderRecord
from copytrading_engine.execution.domain.pricing import quote_problem
from copytrading_engine.execution.domain.sessions import Session, trade_date
from copytrading_engine.execution.domain.values import BrokerAccountNumber

MANUAL_PREVIEW_TTL_SECONDS = 30
log = logging.getLogger(__name__)


class ManualTradingApplication:
    """Account-local manual workflow; all state changes go through TradingLedger."""

    def __init__(
        self,
        engine: CopyEngine,
        *,
        local_account_id: str,
        broker_account_id: BrokerAccountNumber,
        environment: Literal["paper", "live"],
        halted: Callable[[], bool],
        entry_block_reason: Callable[[], str | None],
        recovery_ready: Callable[[], bool],
        stopping: Callable[[], bool],
    ) -> None:
        self.engine = engine
        self.local_account_id = local_account_id
        self.broker_account_id = broker_account_id
        self.environment = environment
        self.halted = halted
        self.entry_block_reason = entry_block_reason
        self.recovery_ready = recovery_ready
        self.stopping = stopping

    def record_correction(self, correction: ManualCorrectionRecord) -> ManualCorrectionRecord:
        if self.local_account_id not in correction.selected_account_ids:
            raise ValueError("Manual correction does not select this account")
        return self.engine.ledger.record_manual_correction(correction)

    def preview(self, request: ManualPreviewRequest, now: dt.datetime) -> ManualOrderPreview:
        existing = self.engine.ledger.snapshot().manual_previews.get(request.preview_id)
        if existing is not None:
            if existing.request != request:
                raise ValueError("Manual preview identity conflicts with another request")
            return existing
        preview = self._evaluate(request, now)
        return self.engine.ledger.save_manual_preview(preview)

    def confirm(self, request: ManualConfirmationRequest, now: dt.datetime) -> ManualCommandResult:
        snapshot = self.engine.ledger.snapshot()
        previous = snapshot.manual_commands.get(request.command_id)
        if previous is not None:
            if previous.request != request:
                raise ValueError("Manual command identity conflicts with different content")
            self.engine.reconcile(now)
            return self.result(request.command_id)

        preview = snapshot.manual_previews.get(request.preview_id)
        if preview is None:
            raise ValueError("Manual preview is unavailable")
        correction = snapshot.manual_corrections.get(preview.request.correction_id)
        if correction is None:
            raise ValueError("Manual correction is unavailable")

        # Reconciliation is a read of prior broker outcomes before considering a
        # second action. It also converts a never acknowledged submit into durable
        # uncertainty; this path never resubmits an existing command.
        self.engine.reconcile(now)
        current = self._evaluate(preview.request, now)
        reason = self._confirmation_block(preview, current, correction, now)
        if reason is not None:
            rejected = ManualCommandRecord(
                request=request,
                correction_id=correction.correction_id,
                source_id=correction.source_id,
                instruction_index=preview.request.instruction_index,
                confirmed_at=now,
                state="rejected",
                reason=reason,
            )
            self.engine.ledger.reject_manual_command(rejected)
            return self.result(request.command_id)

        assert preview.plan is not None
        client_id = "manual-" + hashlib.sha256(request.command_id.encode()).hexdigest()[:40]
        prepared = ManualCommandRecord(
            request=request,
            correction_id=correction.correction_id,
            source_id=correction.source_id,
            instruction_index=preview.request.instruction_index,
            confirmed_at=now,
            state="prepared",
            client_id=client_id,
        )
        _, order = self.engine.ledger.prepare_manual_command(prepared, preview.plan)
        # prepare_manual_command atomically saves the command and intent. The
        # existing guarded submit path owns the only broker mutation.
        self.engine.submit_manual_prepared(
            order,
            now,
            halted=self.halted,
            entry_block_reason=self.entry_block_reason,
            stopping=self.stopping,
        )
        return self.result(request.command_id)

    def result(self, command_id: str) -> ManualCommandResult:
        snapshot = self.engine.ledger.snapshot()
        return manual_command_result_from_snapshot(snapshot, command_id)

    def command_page(
        self,
        source_id: str,
        *,
        before_command_id: str | None = None,
        limit: int = 50,
    ) -> ManualCommandPage:
        """List durable source-scoped command results newest first with a stable cursor."""
        return manual_command_page_from_snapshot(
            self.engine.ledger.snapshot(),
            account_id=self.local_account_id,
            source_id=source_id,
            before_command_id=before_command_id,
            limit=limit,
        )

    def _confirmation_block(
        self,
        saved: ManualOrderPreview,
        fresh: ManualOrderPreview,
        correction: ManualCorrectionRecord,
        now: dt.datetime,
    ) -> str | None:
        instruction = correction.instructions[saved.request.instruction_index]
        if saved.expires_at <= now:
            return "preview_expired"
        if (
            saved.request.account_id != self.local_account_id
            or correction.correction_id != saved.request.correction_id
            or correction.revision != saved.correction_revision
            or instruction != saved.instruction
        ):
            return "correction_changed"
        if saved.configuration_sha256 != fresh.configuration_sha256:
            return "configuration_changed"
        if saved.facts_sha256 != fresh.facts_sha256:
            return "account_facts_changed"
        if (
            fresh.reasons
            or saved.plan is None
            or fresh.plan is None
            or not saved.plan.still_allowed_by(fresh.plan)
        ):
            return fresh.reasons[0] if fresh.reasons else "plan_changed"
        return None

    def _evaluate(
        self,
        request: ManualPreviewRequest,
        now: dt.datetime,
        *,
        check_permission: bool = True,
    ) -> ManualOrderPreview:
        snapshot = self.engine.ledger.snapshot()
        if request.account_id != self.local_account_id:
            raise ValueError("Manual preview account identity mismatch")
        correction = snapshot.manual_corrections.get(request.correction_id)
        if correction is None or self.local_account_id not in correction.selected_account_ids:
            raise ValueError("Manual correction is unavailable for this account")
        if request.instruction_index >= len(correction.instructions):
            raise ValueError("Corrected instruction index is invalid")
        if (
            snapshot.account_id != self.broker_account_id
            or snapshot.environment != self.environment
        ):
            raise ValueError("Manual preview broker identity mismatch")

        instruction = correction.instructions[request.instruction_index]
        message = self.engine.ledger.message(correction.source_id)
        source_age = max(0, int((now - correction.source_at).total_seconds()))
        config_sha = facts_digest(self.engine.config.model_dump(mode="json"))
        reasons: list[str] = []
        # A call waits for the owner only through its own trading day (ADR-0007).
        if trade_date(now) != trade_date(correction.source_at):
            reasons.append("waiting_expired")
            checks = [ManualCheck(name="source", status="blocked", reason="waiting_expired")]
        else:
            checks = [ManualCheck(name="source", status="passed")]
        checks.append(ManualCheck(name="account", status="passed"))

        account = self.engine.broker.account()
        if account.id != self.broker_account_id or not account.active:
            reasons.append("account_unavailable")
            checks.append(
                ManualCheck(name="account", status="blocked", reason="account_unavailable")
            )

        if instruction.action == "buy" and check_permission:
            permission_reason = self.entry_block_reason()
            if permission_reason:
                reasons.append(permission_reason)
                checks.append(
                    ManualCheck(name="permission", status="blocked", reason=permission_reason)
                )
            elif self.halted():
                reasons.append("halted")
                checks.append(ManualCheck(name="permission", status="blocked", reason="halted"))
            else:
                checks.append(ManualCheck(name="permission", status="passed"))
        elif instruction.action != "buy" and not self.recovery_ready():
            reasons.append("recovery_pending")
            checks.append(
                ManualCheck(name="permission", status="blocked", reason="recovery_pending")
            )
        else:
            checks.append(ManualCheck(name="permission", status="passed"))

        session: Session | None = None
        decision = None
        decision_failure: str | None = None
        try:
            decision = self.engine.decide(
                instruction,
                correction.source_id,
                message.source_key,
                now,
                halted=self.halted(),
                manual=True,
            )
            session = decision.plan.session if decision.plan is not None else None
        except BrokerError:
            decision_failure = "market_facts_unavailable"
            reasons.append(decision_failure)
        except Exception as exc:  # noqa: BLE001 - unexpected preview failures become a reason
            self._report_unexpected_preview_failure("decision", exc)
            decision_failure = "preview_unavailable"
            reasons.append(decision_failure)
        if decision is not None and decision.plan is None and decision.reason != "ready":
            reasons.append(decision.reason)
        checks.append(
            ManualCheck(
                name="risk",
                status="passed"
                if decision is not None and decision.plan is not None
                else "blocked",
                reason=None
                if decision is not None and decision.plan is not None
                else (
                    decision.reason if decision else decision_failure or "market_facts_unavailable"
                ),
            )
        )

        # A post is acted on by hand once per stock and side: a second approval, even through a
        # new correction of the same post, must not buy again while the first order is open or
        # has filled.
        side = "buy" if instruction.action == "buy" else "sell"
        related_action = False
        for command in snapshot.manual_commands.values():
            if (
                command.source_id != correction.source_id
                or command.state != "prepared"
                or command.client_id is None
            ):
                continue
            earlier = self.engine.ledger.order(command.client_id)
            if (
                earlier.symbol == instruction.symbol
                and earlier.side == side
                and (earlier.pending or earlier.filled_qty > 0)
            ):
                related_action = True
                break
        if related_action:
            reasons.append("related_manual_action")
            checks.append(
                ManualCheck(name="prior_action", status="blocked", reason="related_manual_action")
            )
        else:
            checks.append(ManualCheck(name="prior_action", status="passed"))

        quote: Quote | None = None
        fresh_price: Decimal | None = None
        quote_reason: str | None = None
        broker = self.engine.broker
        if not isinstance(broker, QuoteBroker):
            quote_reason = "quote_unavailable"
        else:
            try:
                quote = broker.quote(instruction.symbol)
                fresh_price = quote.ask if instruction.action == "buy" else quote.bid
                quote_reason = quote_problem(quote, fresh_price, now)
            except BrokerError:
                quote_reason = "quote_unavailable"
            except Exception as exc:  # noqa: BLE001 - unexpected preview failures become a reason
                self._report_unexpected_preview_failure("quote", exc)
                quote_reason = "preview_unavailable"
        if quote_reason is not None:
            reasons.append(quote_reason)
            checks.append(ManualCheck(name="quote", status="blocked", reason=quote_reason))
        elif decision is not None and decision.plan is not None:
            if instruction.action == "buy":
                assert fresh_price is not None
                assert decision.plan.limit_price is not None
                if fresh_price > decision.plan.limit_price:
                    reasons.append("quote_above_limit")
                    checks.append(
                        ManualCheck(name="quote", status="blocked", reason="quote_above_limit")
                    )
                else:
                    checks.append(ManualCheck(name="quote", status="passed"))
            else:
                checks.append(ManualCheck(name="quote", status="passed"))
        else:
            checks.append(ManualCheck(name="quote", status="warning", reason="plan_unavailable"))

        if not self.recovery_ready():
            # A fresh broker view and ownership audit are required before any
            # manual order can use an account whose startup recovery is pending.
            if "recovery_pending" not in reasons:
                reasons.append("recovery_pending")

        plan = decision.plan if decision is not None else None
        if reasons:
            plan = None
        facts = {
            "account": account.standing(),
            "positions": [item.holding() for item in self.engine.broker.positions()],
            "open_orders": [
                item.model_dump(mode="json") for item in self.engine.broker.open_orders()
            ],
            "snapshot": {
                "control": snapshot.control.model_dump(mode="json"),
                "orders": [item.model_dump(mode="json") for item in snapshot.orders.values()],
                "lots": {key: item.model_dump(mode="json") for key, item in snapshot.lots.items()},
                "external_positions": {
                    key: item.model_dump(mode="json")
                    for key, item in snapshot.external_positions.items()
                },
                "ownership_incidents": {
                    key: item.model_dump(mode="json")
                    for key, item in snapshot.ownership_incidents.items()
                },
                "late_order_incidents": {
                    key: item.model_dump(mode="json")
                    for key, item in snapshot.late_order_incidents.items()
                },
            },
            "session": session.value if session is not None else None,
            "quote": {
                "feed": quote.feed,
                "bid": str(quote.bid) if quote and quote.bid is not None else None,
                "ask": str(quote.ask) if quote and quote.ask is not None else None,
            }
            if quote is not None
            else None,
            "reasons": sorted(set(reasons)),
        }
        return ManualOrderPreview(
            request=request,
            broker_account_id=self.broker_account_id,
            environment=self.environment,
            correction_revision=correction.revision,
            source_at=correction.source_at,
            source_age_seconds=source_age,
            instruction=instruction,
            created_at=now,
            expires_at=now + dt.timedelta(seconds=MANUAL_PREVIEW_TTL_SECONDS),
            session=session,
            quote=quote,
            fresh_price=fresh_price,
            plan=plan,
            checks=tuple(checks),
            reasons=tuple(sorted(set(reasons))),
            facts_sha256=facts_digest(facts),
            configuration_sha256=config_sha,
        )

    @staticmethod
    def _report_unexpected_preview_failure(stage: str, error: Exception) -> None:
        """Log only static context and the exception type; never expose its text."""
        log.error(
            "Unexpected manual preview failure (stage=%s, error_type=%s)",
            stage,
            type(error).__name__,
        )


def manual_command_result_from_snapshot(
    snapshot: LedgerSnapshot, command_id: str
) -> ManualCommandResult:
    """Project one durable command and its latest order evidence into the read contract."""
    command = snapshot.manual_commands[command_id]
    if command.state == "rejected":
        return ManualCommandResult(command=command, status="rejected", reason=command.reason)
    assert command.client_id is not None
    order = snapshot.orders[command.client_id]
    status = owner_order_status(order)
    return ManualCommandResult(
        command=command,
        status=status,
        reason=order.raw_broker_status if status == "broker_rejected" else None,
        client_id=order.client_id,
        broker_order_id=order.broker_id,
        order_status=order.status,
        filled_qty=order.filled_qty,
    )


def manual_command_page_from_snapshot(
    snapshot: LedgerSnapshot,
    *,
    account_id: str,
    source_id: str,
    before_command_id: str | None = None,
    limit: int = 50,
) -> ManualCommandPage:
    """Build a bounded source-scoped history page from one validated account snapshot.

    `account_id` is the app's name for the account; the snapshot records the broker's number.
    """
    if type(limit) is not int or not 1 <= limit <= 100:
        raise ValueError("Manual command page limit must be between 1 and 100")
    commands = [
        command for command in snapshot.manual_commands.values() if command.source_id == source_id
    ]
    commands.sort(
        key=lambda command: (command.confirmed_at, command.request.command_id), reverse=True
    )
    if before_command_id is not None:
        cursor = next(
            (command for command in commands if command.request.command_id == before_command_id),
            None,
        )
        if cursor is None:
            raise ValueError("Manual command page cursor is unavailable")
        cursor_key = (cursor.confirmed_at, cursor.request.command_id)
        commands = [
            command
            for command in commands
            if (command.confirmed_at, command.request.command_id) < cursor_key
        ]

    has_more = len(commands) > limit
    page_commands = commands[:limit]
    return ManualCommandPage(
        account_id=account_id,
        source_id=source_id,
        items=tuple(
            manual_command_result_from_snapshot(snapshot, command.request.command_id)
            for command in page_commands
        ),
        next_before_command_id=(
            page_commands[-1].request.command_id if has_more and page_commands else None
        ),
    )


def facts_digest(value: object) -> str:
    """A stable fingerprint of the facts a preview was decided on."""
    encoded = json.dumps(value, sort_keys=True, separators=(",", ":"), default=str).encode()
    return hashlib.sha256(encoded).hexdigest()


def owner_order_status(
    order: OrderRecord,
) -> Literal[
    "rejected",
    "prepared",
    "uncertain",
    "accepted",
    "partially_filled",
    "filled",
    "cancelled",
    "broker_rejected",
    "expired",
]:
    if order.status == OrderStatus.PREPARED:
        return "prepared"
    if order.status == OrderStatus.UNCERTAIN:
        return "uncertain"
    if order.status == OrderStatus.PARTIALLY_FILLED:
        return "partially_filled"
    if order.status == OrderStatus.FILLED:
        return "filled"
    if order.status in {OrderStatus.CANCELED, OrderStatus.REPLACED}:
        return "cancelled"
    if order.status == OrderStatus.EXPIRED:
        return "expired"
    if order.status == OrderStatus.REJECTED:
        return "broker_rejected"
    if order.status == OrderStatus.ABORTED_BEFORE_SUBMIT:
        return "rejected"
    return "accepted"
