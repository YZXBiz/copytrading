"""Preview and explicitly confirm the owner's sale of one copied lot."""

import datetime as dt
import hashlib
import logging
from collections.abc import Callable
from decimal import Decimal
from typing import Literal

from copytrading_engine.execution.application.engine import CopyEngine
from copytrading_engine.execution.application.manual_commands import (
    facts_digest,
    owner_order_status,
)
from copytrading_engine.execution.application.ports import BrokerError, QuoteBroker
from copytrading_engine.execution.domain.ledger_state import LedgerSnapshot
from copytrading_engine.execution.domain.lot_sales import (
    LotSaleConfirmation,
    LotSalePreview,
    LotSalePreviewRequest,
    LotSaleRecord,
    LotSaleResult,
)
from copytrading_engine.execution.domain.manual_commands import ManualCheck
from copytrading_engine.execution.domain.market import Quote
from copytrading_engine.execution.domain.pricing import quote_problem
from copytrading_engine.execution.domain.values import BrokerAccountNumber
from copytrading_engine.shared.signals import Instruction

LOT_SALE_PREVIEW_TTL_SECONDS = 30
log = logging.getLogger(__name__)


class LotSaleApplication:
    """Account-local lot sales; every state change goes through TradingLedger.

    A sale plans through the same decision as a copied exit, so it gets the same session,
    asset, position, and open-order checks, and it submits through the same guarded path.
    """

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

    def preview(self, request: LotSalePreviewRequest, now: dt.datetime) -> LotSalePreview:
        existing = self.engine.ledger.snapshot().lot_sale_previews.get(request.preview_id)
        if existing is not None:
            if existing.request != request:
                raise ValueError("Lot sale preview identity conflicts with another request")
            return existing
        return self.engine.ledger.save_lot_sale_preview(self._evaluate(request, now))

    def confirm(self, request: LotSaleConfirmation, now: dt.datetime) -> LotSaleResult:
        snapshot = self.engine.ledger.snapshot()
        previous = snapshot.lot_sales.get(request.command_id)
        if previous is not None:
            if previous.request != request:
                raise ValueError("Lot sale identity conflicts with different content")
            self.engine.reconcile(now)
            return self.result(request.command_id)
        preview = snapshot.lot_sale_previews.get(request.preview_id)
        if preview is None or preview.request.account_id != request.account_id:
            raise ValueError("Lot sale preview is unavailable")

        # Read prior broker outcomes before a second action; never resubmit a known intent.
        self.engine.reconcile(now)
        current = self._evaluate(preview.request, now)
        reason = self._confirmation_block(preview, current, now)
        if reason is not None:
            self.engine.ledger.reject_lot_sale(
                LotSaleRecord(
                    request=request,
                    lot_id=preview.request.lot_id,
                    confirmed_at=now,
                    state="rejected",
                    reason=reason,
                )
            )
            return self.result(request.command_id)

        assert preview.plan is not None
        client_id = "lotsale-" + hashlib.sha256(request.command_id.encode()).hexdigest()[:40]
        _, order = self.engine.ledger.prepare_lot_sale(
            LotSaleRecord(
                request=request,
                lot_id=preview.request.lot_id,
                confirmed_at=now,
                state="prepared",
                client_id=client_id,
            ),
            preview.plan,
        )
        self.engine.submit_manual_prepared(
            order,
            now,
            halted=self.halted,
            entry_block_reason=self.entry_block_reason,
            stopping=self.stopping,
        )
        return self.result(request.command_id)

    def result(self, command_id: str) -> LotSaleResult:
        return lot_sale_result_from_snapshot(self.engine.ledger.snapshot(), command_id)

    def _confirmation_block(
        self, saved: LotSalePreview, fresh: LotSalePreview, now: dt.datetime
    ) -> str | None:
        if saved.expires_at <= now:
            return "preview_expired"
        if saved.request.account_id != self.local_account_id:
            return "account_changed"
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

    def _evaluate(self, request: LotSalePreviewRequest, now: dt.datetime) -> LotSalePreview:
        snapshot = self.engine.ledger.snapshot()
        if request.account_id != self.local_account_id:
            raise ValueError("Lot sale account identity mismatch")
        if (
            snapshot.account_id != self.broker_account_id
            or snapshot.environment != self.environment
        ):
            raise ValueError("Lot sale broker identity mismatch")
        lot = snapshot.lots.get(request.lot_id)
        buy = snapshot.orders.get(request.lot_id)
        if lot is None or buy is None or lot.remaining_qty <= 0:
            raise ValueError("Lot is unavailable")

        checks: list[ManualCheck] = []
        reasons: list[str] = []
        account = self.engine.broker.account()
        if account.id != self.broker_account_id or not account.active:
            reasons.append("account_unavailable")
            checks.append(
                ManualCheck(name="account", status="blocked", reason="account_unavailable")
            )
        else:
            checks.append(ManualCheck(name="account", status="passed"))

        if self.recovery_ready():
            checks.append(ManualCheck(name="permission", status="passed"))
        else:
            reasons.append("recovery_pending")
            checks.append(
                ManualCheck(name="permission", status="blocked", reason="recovery_pending")
            )

        if any(
            sale.lot_id == request.lot_id
            and sale.client_id is not None
            and self.engine.ledger.order(sale.client_id).pending
            for sale in snapshot.lot_sales.values()
        ):
            reasons.append("related_manual_action")
            checks.append(
                ManualCheck(name="prior_action", status="blocked", reason="related_manual_action")
            )
        else:
            checks.append(ManualCheck(name="prior_action", status="passed"))

        quote: Quote | None = None
        bid: Decimal | None = None
        quote_reason: str | None = None
        broker = self.engine.broker
        if not isinstance(broker, QuoteBroker):
            quote_reason = "quote_unavailable"
        else:
            try:
                quote = broker.quote(lot.symbol)
                bid = quote.bid
                quote_reason = quote_problem(quote, bid, now)
            except BrokerError:
                quote_reason = "quote_unavailable"
            except Exception as exc:  # noqa: BLE001 - unexpected preview failures become a reason
                _report_unexpected_preview_failure("quote", exc)
                quote_reason = "preview_unavailable"
        if quote_reason is not None:
            quote, bid = (quote, bid) if bid is not None and bid > 0 else (None, None)
            reasons.append(quote_reason)
            checks.append(ManualCheck(name="quote", status="blocked", reason=quote_reason))
        else:
            checks.append(ManualCheck(name="quote", status="passed"))

        decision = None
        decision_failure: str | None = None
        if bid is not None and bid > 0:
            instruction = Instruction(
                action="close",
                symbol=lot.symbol,
                price=bid,
                entry_price=lot.entry_price,
                fraction=Decimal(1),
            )
            try:
                decision = self.engine.decide(
                    instruction,
                    buy.message_id,
                    lot.source_key,
                    now,
                    halted=self.halted(),
                    manual=True,
                    chosen_lot=request.lot_id,
                    chosen_qty=request.qty,
                )
            except BrokerError:
                decision_failure = "market_facts_unavailable"
            except Exception as exc:  # noqa: BLE001 - unexpected preview failures become a reason
                _report_unexpected_preview_failure("decision", exc)
                decision_failure = "preview_unavailable"
        if decision_failure is not None:
            reasons.append(decision_failure)
        elif decision is not None and decision.plan is None:
            reasons.append(decision.reason)
        ready = decision is not None and decision.plan is not None
        checks.append(
            ManualCheck(
                name="risk",
                status="passed" if ready else "blocked",
                reason=None
                if ready
                else (
                    decision.reason if decision is not None else decision_failure or quote_reason
                ),
            )
        )

        plan = decision.plan if decision is not None and not reasons else None
        session = decision.plan.session if decision is not None and decision.plan else None
        facts = {
            "account": account.standing(),
            "positions": [item.holding() for item in broker.positions()],
            "open_orders": [item.model_dump(mode="json") for item in broker.open_orders()],
            "lot": lot.model_dump(mode="json"),
            "pending": [item.model_dump(mode="json") for item in self.engine.pending()],
            "control": snapshot.control.model_dump(mode="json"),
            "external_positions": {
                key: item.model_dump(mode="json")
                for key, item in snapshot.external_positions.items()
            },
            "ownership_incidents": sorted(
                key for key, item in snapshot.ownership_incidents.items() if not item.resolved
            ),
            "late_order_incidents": sorted(
                key for key, item in snapshot.late_order_incidents.items() if item.unresolved
            ),
            "session": session.value if session is not None else None,
            "reasons": sorted(set(reasons)),
        }
        return LotSalePreview(
            request=request,
            broker_account_id=self.broker_account_id,
            environment=self.environment,
            symbol=lot.symbol,
            lot_remaining_qty=lot.remaining_qty,
            created_at=now,
            expires_at=now + dt.timedelta(seconds=LOT_SALE_PREVIEW_TTL_SECONDS),
            session=session,
            quote=quote,
            fresh_price=bid,
            plan=plan,
            checks=tuple(checks),
            reasons=tuple(sorted(set(reasons))),
            facts_sha256=facts_digest(facts),
        )


def lot_sale_result_from_snapshot(snapshot: LedgerSnapshot, command_id: str) -> LotSaleResult:
    """Project one durable lot sale and its latest order evidence into the read contract."""
    sale = snapshot.lot_sales[command_id]
    if sale.state == "rejected":
        return LotSaleResult(sale=sale, status="rejected", reason=sale.reason)
    assert sale.client_id is not None
    order = snapshot.orders[sale.client_id]
    status = owner_order_status(order)
    return LotSaleResult(
        sale=sale,
        status=status,
        reason=order.raw_broker_status if status == "broker_rejected" else None,
        client_id=order.client_id,
        broker_order_id=order.broker_id,
        order_status=order.status,
        filled_qty=order.filled_qty,
        filled_avg_price=order.filled_avg_price,
    )


def _report_unexpected_preview_failure(stage: str, error: Exception) -> None:
    """Log only static context and the exception type; never expose its text."""
    log.error(
        "Unexpected lot sale preview failure (stage=%s, error_type=%s)",
        stage,
        type(error).__name__,
    )
