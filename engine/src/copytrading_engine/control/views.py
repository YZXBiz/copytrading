"""Present engine results through the control contract.

Only the fields an operator or agent needs cross this boundary. Broker identities,
configuration fingerprints and raw payload evidence stay inside the engine.
"""

from copytrading_engine.control import wire
from copytrading_engine.control.proposals import (
    Closed,
    ConfirmManualOrder,
    Finished,
    Pending,
    Proposal,
    ResumeAccount,
    Running,
    SetRecovery,
)
from copytrading_engine.execution.domain.lifecycle import AccountControlResult
from copytrading_engine.execution.domain.manual_commands import (
    ManualCommandPage,
    ManualCommandResult,
    ManualOrderPreview,
)
from copytrading_engine.execution.presentation.operator_views import (
    AccountEventPage,
    AccountOverview,
    AccountOverviewPage,
    AccountUnavailable,
    DestinationView,
)
from copytrading_engine.trading.domain.status import TradingStatus
from copytrading_engine.trading.presentation.operator_models import SourceActivityPage


def processing(status: TradingStatus) -> wire.ProcessingView:
    return wire.ProcessingView(
        state=status.state,
        source_connected=status.source_connected,
        model_ready=status.model_ready,
        pending_source=status.pending_source,
        pending_signals=status.pending_signals,
        processed_signals=status.processed_signals,
        error_code=status.error_code,
    )


def status(engine_state: str, trading: TradingStatus) -> wire.StatusView:
    return wire.StatusView(
        engine_state=engine_state,
        processing=processing(trading),
        accounts=tuple(
            wire.AccountStateView(
                account_id=account.id,
                run_state=account.state,
                entry_permission=account.entry_permission,
                recovery_preference=account.recovery_preference,
                readiness=account.readiness,
                risk_status=account.account_risk_status,
                activity_status=account.account_activity_status,
                error_code=account.error_code,
            )
            for account in trading.accounts
        ),
    )


def _unavailable(items: tuple[AccountUnavailable, ...]) -> tuple[wire.UnavailableAccountView, ...]:
    return tuple(
        wire.UnavailableAccountView(account_id=item.account_id, reason=item.reason)
        for item in items
    )


def _account(item: AccountOverview) -> wire.AccountView:
    return wire.AccountView(
        account_id=item.account_id,
        environment=item.environment,
        entry_permission=item.entry_permission,
        recovery_preference=item.recovery_preference,
        readiness=item.readiness,
        risk_status=item.account_risk_status,
        risk_reason=item.account_risk_reason,
        activity_status=item.account_activity_status,
        activity_reason=item.account_activity_reason,
        total_exposure_usd=item.total_exposure_usd,
        positions=tuple(
            wire.PositionView(
                symbol=position.symbol,
                owned_qty=position.owned_qty,
                external_qty=position.external_qty,
                lots=tuple(
                    wire.LotView(
                        lot_id=lot.lot_id,
                        source_id=lot.source_id,
                        guru_id=lot.guru_id,
                        posted_at=lot.posted_at,
                        untrusted_source_text=lot.excerpt,
                        bought_at=lot.bought_at,
                        original_qty=lot.original_qty,
                        remaining_qty=lot.remaining_qty,
                        average_price=lot.average_price,
                    )
                    for lot in position.lots
                ),
            )
            for position in item.positions
        ),
        ownership_incidents=len(item.ownership_incidents),
        pending_orders=item.pending_orders,
        balance=None
        if item.balance is None
        else wire.BalanceView(
            equity=item.balance.equity,
            day_change_usd=item.balance.day_change_usd,
            cash=item.balance.cash,
            buying_power=item.balance.buying_power,
            observed_at=item.balance.observed_at,
        ),
    )


def accounts(page: AccountOverviewPage) -> wire.AccountsPage:
    return wire.AccountsPage(
        items=tuple(_account(item) for item in page.items),
        next_before_account_id=page.next_before_account_id,
        unavailable=_unavailable(page.unavailable_accounts),
    )


def _destination(item: DestinationView) -> wire.DestinationView:
    return wire.DestinationView(
        account_id=item.account_id,
        environment=item.environment,
        status=item.status,
        instruction_outcomes=item.instruction_outcomes,
        orders=tuple(
            wire.OrderView(
                client_id=order.client_id,
                symbol=order.symbol,
                side=order.side,
                status=order.status,
                quantity=order.quantity,
                filled_quantity=order.filled_quantity,
                average_fill_price=order.average_fill_price,
            )
            for order in item.orders
        ),
    )


def activity(page: SourceActivityPage) -> wire.ActivityPage:
    return wire.ActivityPage(
        items=tuple(
            wire.ActivityItem(
                sequence=item.sequence,
                source_id=item.source_id,
                source_at=item.source_at,
                captured_at=item.captured_at,
                parse_status=item.parse_status,
                delivery_status=item.delivery_status,
                decision=item.decision,
                parser_reason=item.parser_reason,
                guru_id=item.guru_id,
                untrusted_source_text=item.text,
                understood_as=tuple(
                    wire.InstructionItem(
                        action=instruction.action,
                        symbol=instruction.symbol,
                        price=instruction.price,
                        fraction=instruction.fraction,
                    )
                    for instruction in item.instructions
                ),
                destinations=tuple(_destination(target) for target in item.destinations),
            )
            for item in page.items
        ),
        rejected=tuple(
            wire.RejectedActivityItem(
                source_id=item.source_id, rejected_at=item.rejected_at, reason=item.reason
            )
            for item in page.rejected_items
        ),
        next_before_seq=page.next_before_seq,
        unavailable=_unavailable(page.unavailable_accounts),
    )


def account_events(page: AccountEventPage) -> wire.AccountEventsPage:
    return wire.AccountEventsPage(
        account_id=page.account_id,
        items=tuple(
            wire.AccountEventView(
                sequence=item.sequence,
                at=item.at,
                kind=item.kind,
                message_id=item.message_id,
                order_id=item.order_id,
                reason=item.reason,
                status=item.status,
            )
            for item in page.items
        ),
        next_before_seq=page.next_before_seq,
    )


def manual_command(result: ManualCommandResult) -> wire.ManualCommandView:
    record = result.command
    return wire.ManualCommandView(
        command_id=record.request.command_id,
        account_id=record.request.account_id,
        source_id=record.source_id,
        correction_id=record.correction_id,
        instruction_index=record.instruction_index,
        actor=record.request.actor,
        confirmed_at=record.confirmed_at,
        status=result.status,
        reason=result.reason,
        client_id=result.client_id,
    )


def manual_commands(page: ManualCommandPage) -> wire.ManualCommandsPage:
    return wire.ManualCommandsPage(
        account_id=page.account_id,
        source_id=page.source_id,
        items=tuple(manual_command(item) for item in page.items),
        next_before_command_id=page.next_before_command_id,
    )


def manual_preview(preview: ManualOrderPreview) -> wire.ManualPreview:
    instruction = preview.instruction
    plan = preview.plan
    return wire.ManualPreview(
        preview_id=preview.request.preview_id,
        account_id=preview.request.account_id,
        environment=preview.environment,
        source_age_seconds=preview.source_age_seconds,
        created_at=preview.created_at,
        expires_at=preview.expires_at,
        instruction=wire.InstructionView(
            action=instruction.action,
            symbol=instruction.symbol,
            price=instruction.price,
            entry_price=instruction.entry_price,
            fraction=instruction.fraction,
        ),
        fresh_price=preview.fresh_price,
        plan=None
        if plan is None
        else wire.OrderPlanView(
            side=plan.side,
            type=plan.type,
            quantity=plan.qty,
            limit_price=plan.limit_price,
            session=plan.session.value,
        ),
        checks=tuple(
            wire.CheckView(name=check.name, status=check.status, reason=check.reason)
            for check in preview.checks
        ),
        reasons=preview.reasons,
    )


def account_control(result: AccountControlResult) -> wire.AccountControlView:
    return wire.AccountControlView(
        account_id=result.command.account_id,
        entry_permission=result.entry_permission,
        recovery_preference=result.recovery_preference,
        applied_at=result.applied_at,
    )


def proposal(item: Proposal) -> wire.ProposalView:
    subject: wire.ResumeAccountSubject | wire.RecoverySubject | wire.ManualOrderSubject
    match item.subject:
        case ResumeAccount(account_id=account_id):
            subject = wire.ResumeAccountSubject(account_id=account_id)
        case SetRecovery(account_id=account_id, preference=preference):
            subject = wire.RecoverySubject(account_id=account_id, preference=preference)
        case ConfirmManualOrder() as order:
            subject = wire.ManualOrderSubject(
                account_id=order.account_id,
                preview_id=order.preview_id,
                environment=order.environment,
                symbol=order.symbol,
                side=order.side,
                order_type=order.order_type,
                quantity=order.quantity,
                limit_price=order.limit_price,
            )
    outcome = None
    match item.state:
        case Pending():
            state = "pending"
        case Running():
            state = "running"
        case Finished(result=result, code=code):
            state = result
            outcome = wire.ProposalOutcome(status=result, code=code, command_id=item.command_id)
        case Closed(reason=reason):
            state = reason
    return wire.ProposalView(
        proposal_id=item.proposal_id,
        state=state,
        subject=subject,
        digest=item.digest,
        command_id=item.command_id,
        created_at=item.created_at,
        expires_at=item.expires_at,
        requested_by=wire.CallerView(pid=item.caller.pid, path=item.caller.path),
        outcome=outcome,
    )
