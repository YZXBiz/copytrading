"""Trading state transitions; publish a new in-memory state only after durable commit."""

import datetime as dt
import hashlib
import logging
from decimal import Decimal
from typing import Literal, TypedDict, Unpack

from copytrading_engine.execution.application.ports import ExecutionObserver, LedgerRepository
from copytrading_engine.execution.domain.events import (
    AccountControlChanged,
    AccountInventoried,
    CashAnchorRecorded,
    Exposure,
    JournalEvent,
    LateOrderIncidentCleared,
    LateOrderIncidentOpened,
    LateOrderIncidentReopened,
    LotSalePrepared,
    LotSalePreviewed,
    LotSaleRejected,
    ManualCommandPrepared,
    ManualCommandRejected,
    ManualCorrectionRecorded,
    ManualOrderPreviewed,
    ManualSaleRecorded,
    Message,
    MessageDone,
    OrderIntentReleased,
    OrderPrepared,
    OrderUpdate,
    OwnershipIncidentOpened,
    OwnershipResolved,
    SubmissionAborted,
    SubmissionUncertain,
    SubmitError,
    SubmitStarted,
)
from copytrading_engine.execution.domain.events import Skipped as SkippedEvent
from copytrading_engine.execution.domain.ledger_state import (
    CashAnchor,
    LedgerSnapshot,
    MessageRecord,
    MessageStatus,
)
from copytrading_engine.execution.domain.lifecycle import (
    AccountControl,
    AccountControlCommand,
    AccountControlConflict,
    AccountControlResult,
)
from copytrading_engine.execution.domain.lot_sales import LotSalePreview, LotSaleRecord
from copytrading_engine.execution.domain.manual_commands import (
    ManualCommandRecord,
    ManualCorrectionRecord,
    ManualOrderPreview,
)
from copytrading_engine.execution.domain.market import BrokerOrder, Position
from copytrading_engine.execution.domain.order_lifecycle import (
    OrderStatus,
    is_pending,
    map_broker_status,
    validate_transition,
)
from copytrading_engine.execution.domain.orders import OrderPlan, OrderRecord, OwnedLot
from copytrading_engine.execution.domain.ownership import (
    ExternalPosition,
    OwnershipIncident,
    OwnershipResolution,
    OwnershipResolutionRequest,
)
from copytrading_engine.execution.domain.positions import PositionAudit
from copytrading_engine.execution.domain.progress import (
    InstructionProgress,
    OrderLinked,
    Pending,
    Skipped,
)
from copytrading_engine.execution.domain.recovery import (
    IncidentClearanceEvidence,
    LateOrderIncident,
    ManualSale,
    QuarantinedFill,
    ReleaseEvidence,
)
from copytrading_engine.execution.domain.sessions import trade_date
from copytrading_engine.execution.domain.sizing import DestinationSignal
from copytrading_engine.shared.signals import StockSignal

ZERO = Decimal(0)
log = logging.getLogger(__name__)


class _SnapshotChanges(TypedDict, total=False):
    account_id: str
    control: AccountControl
    messages: dict[str, MessageRecord]
    orders: dict[str, OrderRecord]
    lots: dict[str, OwnedLot]
    manual_sales: dict[str, ManualSale]
    release_evidence: dict[str, ReleaseEvidence]
    late_order_incidents: dict[str, LateOrderIncident]
    quarantined_fills: dict[str, QuarantinedFill]
    environment: Literal["paper", "live"]
    external_positions: dict[str, ExternalPosition]
    ownership_incidents: dict[str, OwnershipIncident]
    ownership_resolutions: dict[str, OwnershipResolution]
    manual_corrections: dict[str, ManualCorrectionRecord]
    manual_previews: dict[str, ManualOrderPreview]
    manual_commands: dict[str, ManualCommandRecord]
    lot_sale_previews: dict[str, LotSalePreview]
    lot_sales: dict[str, LotSaleRecord]


class _MessageChanges(TypedDict, total=False):
    status: MessageStatus
    parts: tuple[InstructionProgress, ...]
    cash_anchor: CashAnchor


class _OrderChanges(TypedDict, total=False):
    status: OrderStatus
    submit_started_at: dt.datetime
    raw_broker_status: str | None


class TradingLedger:
    """Own validated state, isolated from repository and caller-owned containers.

    Every transition validates the complete snapshot and commits it with a journal
    event before publishing it in memory. Failed persistence leaves state unchanged.
    """

    def __init__(self, repository: LedgerRepository, observer: ExecutionObserver) -> None:
        self._repository = repository
        self._snapshot = LedgerSnapshot.model_validate(repository.load().model_dump())
        self._observer = observer

    @property
    def account_id(self) -> str | None:
        return self._snapshot.account_id

    def snapshot(self) -> LedgerSnapshot:
        # Containers must not expose a second mutable owner of the aggregate.
        return self._snapshot.model_copy(deep=True)

    def orders(self) -> tuple[OrderRecord, ...]:
        return tuple(self._snapshot.orders.values())

    def lots(self) -> tuple[OwnedLot, ...]:
        return tuple(self._snapshot.lots.values())

    def message(self, key: str) -> MessageRecord:
        return self._snapshot.messages[key]

    def order(self, key: str) -> OrderRecord:
        return self._snapshot.orders[key]

    def queued(self) -> tuple[MessageRecord, ...]:
        return tuple(m for m in self._snapshot.messages.values() if m.status == "queued")

    def pending(self, symbol: str | None = None) -> tuple[OrderRecord, ...]:
        return tuple(
            o for o in self.orders() if o.pending and (symbol is None or o.symbol == symbol)
        )

    def owned(self, symbol: str) -> Decimal:
        return sum((lot.remaining_qty for lot in self.lots() if lot.symbol == symbol), ZERO)

    def expected_position(self, symbol: str) -> Decimal:
        external = self._snapshot.external_positions.get(symbol)
        return self.owned(symbol) + (external.qty if external is not None else ZERO)

    def unresolved_ownership(self, symbol: str) -> tuple[OwnershipIncident, ...]:
        return tuple(
            incident
            for incident in self._snapshot.ownership_incidents.values()
            if incident.symbol == symbol and not incident.resolved
        )

    def exposure(self, symbol: str | None = None) -> Decimal:
        owned = sum(
            (
                lot.remaining_qty * lot.average_price
                for lot in self.lots()
                if symbol is None or lot.symbol == symbol
            ),
            ZERO,
        )
        reserved = sum(
            (
                (o.qty - o.filled_qty) * o.limit_price
                for o in self.pending(symbol)
                if o.side == "buy" and o.limit_price is not None
            ),
            ZERO,
        )
        return owned + reserved

    def matching_lots(
        self, source: str, symbol: str, entry_price: Decimal
    ) -> tuple[tuple[str, OwnedLot], ...]:
        return tuple(
            (key, lot)
            for key, lot in self._snapshot.lots.items()
            if lot.source_key == source
            and lot.symbol == symbol
            and lot.entry_price == entry_price
            and lot.remaining_qty > 0
        )

    def _commit(self, state: LedgerSnapshot, event: JournalEvent) -> None:
        # Frozen models still contain mutable dictionaries. The port must not retain
        # an alias to the state we publish (including when save raises).
        self._repository.save(state.model_copy(deep=True), event)
        self._snapshot = state
        self._observer.event(event.payload.kind)
        log.info("%s %s", event.payload.kind, event.payload.model_dump(mode="json"))

    def record(self, event: JournalEvent) -> None:
        self._commit(self._snapshot, event)

    def account_control(
        self, command: AccountControlCommand, now: dt.datetime, *, local_account_id: str
    ) -> AccountControlResult:
        if command.account_id != local_account_id or self.account_id is None:
            raise ValueError("Account control identity mismatch")
        control = self._snapshot.control
        previous = control.commands.get(command.command_id)
        if previous is not None:
            if previous.command != command:
                raise AccountControlConflict("Account control command identity conflict")
            return previous
        permission = control.entry_permission
        preference = control.recovery_preference
        if command.action == "pause":
            permission = "paused"
        elif command.action == "resume":
            permission = "enabled"
        elif command.action == "restore_manual":
            permission = "disabled"
            preference = "manual"
        else:
            assert command.recovery_preference is not None
            preference = command.recovery_preference
        result = AccountControlResult(
            command=command,
            applied_at=now,
            entry_permission=permission,
            recovery_preference=preference,
        )
        updated = AccountControl(
            entry_permission=permission,
            recovery_preference=preference,
            commands=control.commands | {command.command_id: result},
        )
        self._commit(
            self._replace(control=updated),
            JournalEvent(at=now, payload=AccountControlChanged(result=result)),
        )
        return result

    def skip_unpermitted_buys(self, now: dt.datetime, reason: str) -> None:
        for message in self.queued():
            for index, instruction in enumerate(message.instructions):
                if instruction.action == "buy" and isinstance(
                    self.message(message.key).parts[index], Pending
                ):
                    self.skip(message.key, index, reason, now)
            if all(not isinstance(part, Pending) for part in self.message(message.key).parts):
                self.complete(message.key, now)

    def record_manual_sale(self, sale: ManualSale, actual_qty: Decimal | None = None) -> None:
        """Operator-only import of a verified broker fill; never submits an order."""
        existing = self._snapshot.manual_sales.get(sale.order.id)
        if existing is not None:
            if existing.model_dump(exclude={"recorded_at"}) != sale.model_dump(
                exclude={"recorded_at"}
            ):
                raise ValueError("Manual sale was already recorded with different evidence")
            return
        lot = self._snapshot.lots.get(sale.lot_id or "")
        if sale.lot_id is not None and (lot is None or lot.symbol != sale.order.symbol):
            raise ValueError("Manual sale does not match an owned lot")
        if self.pending(sale.order.symbol):
            raise ValueError("Reconcile pending copier orders before recording a manual sale")
        external = self._snapshot.external_positions.get(sale.order.symbol)
        ambiguous = sale.lot_id is None or (external is not None and external.qty > ZERO)
        if ambiguous:
            if actual_qty is None:
                raise ValueError("Manual sale requires fresh broker position evidence")
            if self.unresolved_ownership(sale.order.symbol):
                raise ValueError("Resolve existing symbol ownership before importing another sale")
            # A caller-supplied lot cannot choose the attribution of mixed holdings.
            if sale.lot_id is not None:
                raise ValueError("Mixed holdings require an unallocated manual sale")
            incident = OwnershipIncident(
                incident_id=sale.order.id,
                symbol=sale.order.symbol,
                expected_qty=self.expected_position(sale.order.symbol),
                actual_qty=actual_qty,
                observed_at=sale.recorded_at,
                cause="manual_sale",
            )
            state = self._replace(
                manual_sales=self._snapshot.manual_sales | {sale.order.id: sale},
                ownership_incidents=self._snapshot.ownership_incidents | {sale.order.id: incident},
            )
            previous_remaining_qty = None
            remaining_qty = None
        else:
            if lot is None or sale.order.filled_qty > lot.remaining_qty:
                raise ValueError("Manual sale exceeds remaining owned lot shares")
            updated = OwnedLot.model_validate(
                lot.model_dump() | {"remaining_qty": lot.remaining_qty - sale.order.filled_qty}
            )
            state = self._replace(
                lots=self._snapshot.lots | {sale.lot_id: updated},
                manual_sales=self._snapshot.manual_sales | {sale.order.id: sale},
            )
            incident = None
            previous_remaining_qty = lot.remaining_qty
            remaining_qty = updated.remaining_qty
        self._commit(
            state,
            JournalEvent(
                at=sale.recorded_at,
                payload=ManualSaleRecorded(
                    sale=sale,
                    previous_remaining_qty=previous_remaining_qty,
                    remaining_qty=remaining_qty,
                    ownership_incident=incident,
                ),
            ),
        )

    def record_manual_correction(
        self, correction: ManualCorrectionRecord
    ) -> ManualCorrectionRecord:
        """Persist this account's copy of a shared immutable correction."""
        correction = ManualCorrectionRecord.model_validate(correction.model_dump())
        existing = self._snapshot.manual_corrections.get(correction.correction_id)
        if existing is not None:
            if existing != correction:
                raise ValueError("Manual correction identity conflicts with different evidence")
            return existing
        message = self._snapshot.messages.get(correction.source_id)
        if (
            correction.correction_id in self._snapshot.manual_corrections
            or self.account_id not in correction.selected_account_ids
            or message is None
            or message.status != "review_required"
            or message.decision != "review"
            or message.timestamp != correction.source_at
            or message.text != correction.source_text
            or StockSignal.model_validate(
                {name: getattr(message, name) for name in StockSignal.model_fields}
            )
            != correction.accepted_interpretation
        ):
            raise ValueError("Manual correction does not match reviewed source evidence")
        if any(
            value.source_id == correction.source_id and value.revision == correction.revision
            for value in self._snapshot.manual_corrections.values()
        ):
            raise ValueError("Manual correction revision already exists")
        self._commit(
            self._replace(
                manual_corrections=self._snapshot.manual_corrections
                | {correction.correction_id: correction}
            ),
            JournalEvent(
                at=correction.recorded_at,
                payload=ManualCorrectionRecorded(correction=correction),
            ),
        )
        return correction

    def save_manual_preview(self, preview: ManualOrderPreview) -> ManualOrderPreview:
        """Save fresh preview evidence without touching the broker."""
        preview = ManualOrderPreview.model_validate(preview.model_dump())
        preview_id = preview.request.preview_id
        existing = self._snapshot.manual_previews.get(preview_id)
        if existing is not None:
            if existing.request != preview.request:
                raise ValueError("Manual preview identity conflicts with another request")
            return existing
        if preview.broker_account_id != self.account_id:
            raise ValueError("Manual preview belongs to another broker account")
        self._commit(
            self._replace(manual_previews=self._snapshot.manual_previews | {preview_id: preview}),
            JournalEvent(at=preview.created_at, payload=ManualOrderPreviewed(preview=preview)),
        )
        return preview

    def reject_manual_command(self, command: ManualCommandRecord) -> ManualCommandRecord:
        """Durably retain a blocked or stale confirmation under its stable ID."""
        command = ManualCommandRecord.model_validate(command.model_dump())
        previous = self._snapshot.manual_commands.get(command.request.command_id)
        if previous is not None:
            if previous != command:
                raise ValueError("Manual command identity conflicts with different content")
            return previous
        if command.state != "rejected":
            raise ValueError("Rejected command must not carry an order intent")
        self._validate_manual_command(command)
        self._commit(
            self._replace(
                manual_commands=self._snapshot.manual_commands
                | {command.request.command_id: command}
            ),
            JournalEvent(at=command.confirmed_at, payload=ManualCommandRejected(command=command)),
        )
        return command

    def prepare_manual_command(
        self, command: ManualCommandRecord, plan: OrderPlan
    ) -> tuple[ManualCommandRecord, OrderRecord]:
        """Atomically commit the manual command and its broker intent."""
        command = ManualCommandRecord.model_validate(command.model_dump())
        plan = OrderPlan.model_validate(plan.model_dump())
        previous = self._snapshot.manual_commands.get(command.request.command_id)
        if previous is not None:
            if previous != command:
                raise ValueError("Manual command identity conflicts with different content")
            if previous.client_id is None:
                raise ValueError("A rejected manual command cannot be prepared")
            return previous, self.order(previous.client_id)
        if command.state != "prepared" or command.client_id is None:
            raise ValueError("Prepared command requires a stable client order ID")
        self._validate_manual_command(command)
        preview = self._snapshot.manual_previews[command.request.preview_id]
        if preview.plan != plan or preview.plan is None:
            raise ValueError("Manual order plan differs from its saved preview")
        correction = self._snapshot.manual_corrections[command.correction_id]
        message = self.message(correction.source_id)
        if command.client_id in self._snapshot.orders:
            raise ValueError("Manual order intent identity already exists")
        if self.pending(plan.symbol):
            raise ValueError("A pending order already owns this symbol")
        if plan.side == "buy" and self._snapshot.entry_halted:
            raise ValueError("Unresolved late-order incidents halt new buy orders")
        order = OrderRecord(
            **plan.model_dump(),
            client_id=command.client_id,
            message_id=correction.source_id,
            instruction_index=command.instruction_index,
            source_key=message.source_key,
            status=OrderStatus.PREPARED,
            filled_qty=ZERO,
            broker_id=None,
            created_at=command.confirmed_at,
            day=trade_date(command.confirmed_at),
        )
        self._commit(
            self._replace(
                orders=self._snapshot.orders | {order.client_id: order},
                manual_commands=self._snapshot.manual_commands
                | {command.request.command_id: command},
            ),
            JournalEvent(
                at=command.confirmed_at,
                payload=ManualCommandPrepared(command=command, plan=plan),
            ),
        )
        return command, order

    def save_lot_sale_preview(self, preview: LotSalePreview) -> LotSalePreview:
        """Save fresh lot sale evidence without touching the broker."""
        preview = LotSalePreview.model_validate(preview.model_dump())
        preview_id = preview.request.preview_id
        existing = self._snapshot.lot_sale_previews.get(preview_id)
        if existing is not None:
            if existing.request != preview.request:
                raise ValueError("Lot sale preview identity conflicts with another request")
            return existing
        if preview.broker_account_id != self.account_id:
            raise ValueError("Lot sale preview belongs to another broker account")
        self._commit(
            self._replace(
                lot_sale_previews=self._snapshot.lot_sale_previews | {preview_id: preview}
            ),
            JournalEvent(at=preview.created_at, payload=LotSalePreviewed(preview=preview)),
        )
        return preview

    def reject_lot_sale(self, sale: LotSaleRecord) -> LotSaleRecord:
        """Durably retain a blocked or stale confirmation under its stable ID."""
        sale = LotSaleRecord.model_validate(sale.model_dump())
        previous = self._snapshot.lot_sales.get(sale.request.command_id)
        if previous is not None:
            if previous != sale:
                raise ValueError("Lot sale identity conflicts with different content")
            return previous
        if sale.state != "rejected":
            raise ValueError("A rejected lot sale must not carry an order intent")
        self._commit(
            self._replace(lot_sales=self._snapshot.lot_sales | {sale.request.command_id: sale}),
            JournalEvent(at=sale.confirmed_at, payload=LotSaleRejected(sale=sale)),
        )
        return sale

    def prepare_lot_sale(
        self, sale: LotSaleRecord, plan: OrderPlan
    ) -> tuple[LotSaleRecord, OrderRecord]:
        """Atomically commit the owner's lot sale and its broker intent.

        The order is filed under the post that bought the lot, so Activity shows the sale
        beside the buy, and it names the lot so the fill comes out of exactly those shares.
        """
        sale = LotSaleRecord.model_validate(sale.model_dump())
        plan = OrderPlan.model_validate(plan.model_dump())
        previous = self._snapshot.lot_sales.get(sale.request.command_id)
        if previous is not None:
            if previous != sale:
                raise ValueError("Lot sale identity conflicts with different content")
            if previous.client_id is None:
                raise ValueError("A rejected lot sale cannot be prepared")
            return previous, self.order(previous.client_id)
        if sale.state != "prepared" or sale.client_id is None:
            raise ValueError("A prepared lot sale requires a stable client order ID")
        preview = self._snapshot.lot_sale_previews.get(sale.request.preview_id)
        if preview is None or preview.plan is None or preview.plan != plan:
            raise ValueError("Lot sale order plan differs from its saved preview")
        if preview.request.lot_id != sale.lot_id or plan.lot_id != sale.lot_id:
            raise ValueError("Lot sale does not name its previewed lot")
        lot = self._snapshot.lots.get(sale.lot_id)
        if lot is None or lot.symbol != plan.symbol or plan.qty > lot.remaining_qty:
            raise ValueError("Lot sale exceeds the shares left in its lot")
        buy = self._snapshot.orders.get(sale.lot_id)
        if buy is None:
            raise ValueError("Lot sale has no buy on record to file it under")
        if sale.client_id in self._snapshot.orders:
            raise ValueError("Lot sale intent identity already exists")
        if self.pending(plan.symbol):
            raise ValueError("A pending order already owns this symbol")
        order = OrderRecord(
            **plan.model_dump(),
            client_id=sale.client_id,
            message_id=buy.message_id,
            instruction_index=buy.instruction_index,
            source_key=lot.source_key,
            status=OrderStatus.PREPARED,
            filled_qty=ZERO,
            broker_id=None,
            created_at=sale.confirmed_at,
            day=trade_date(sale.confirmed_at),
        )
        self._commit(
            self._replace(
                orders=self._snapshot.orders | {order.client_id: order},
                lot_sales=self._snapshot.lot_sales | {sale.request.command_id: sale},
            ),
            JournalEvent(at=sale.confirmed_at, payload=LotSalePrepared(sale=sale, plan=plan)),
        )
        return sale, order

    def _validate_manual_command(self, command: ManualCommandRecord) -> None:
        preview = self._snapshot.manual_previews.get(command.request.preview_id)
        correction = self._snapshot.manual_corrections.get(command.correction_id)
        if (
            preview is None
            or correction is None
            or command.request.account_id != self.account_id
            or preview.request.account_id != self.account_id
            or preview.request.correction_id != command.correction_id
            or preview.request.instruction_index != command.instruction_index
            or command.source_id != correction.source_id
        ):
            raise ValueError("Manual command does not match this account's saved preview")

    def _replace(self, **changes: Unpack[_SnapshotChanges]) -> LedgerSnapshot:
        return LedgerSnapshot.model_validate(self._snapshot.model_dump() | changes)

    def bind(
        self,
        account_id: str,
        now: dt.datetime,
        environment: Literal["paper", "live"] = "paper",
        positions: tuple[Position, ...] = (),
    ) -> None:
        if self.account_id and self.account_id != account_id:
            raise RuntimeError("This ledger belongs to a different broker account")
        if self.account_id and self._snapshot.environment is None:
            raise RuntimeError("Saved ledger is missing its broker environment")
        if self._snapshot.environment is not None and self._snapshot.environment != environment:
            raise RuntimeError("This ledger belongs to a different broker environment")
        if not self.account_id:
            inventory = {
                position.symbol: ExternalPosition(symbol=position.symbol, qty=position.qty)
                for position in positions
            }
            if len(inventory) != len(positions) or any(
                position.qty < ZERO for position in positions
            ):
                raise ValueError("Unsupported or duplicate initial broker positions")
            self._commit(
                self._replace(
                    account_id=account_id, environment=environment, external_positions=inventory
                ),
                JournalEvent(
                    at=now,
                    payload=AccountInventoried(
                        account_id=account_id, environment=environment, external_positions=inventory
                    ),
                ),
            )

    def open_ownership_incidents(self, audit: PositionAudit, now: dt.datetime) -> None:
        for comparison in audit.positions:
            if not comparison.mismatched or self.unresolved_ownership(comparison.symbol):
                continue
            revision = sum(
                incident.symbol == comparison.symbol
                for incident in self._snapshot.ownership_incidents.values()
            )
            identity = (
                "position-"
                + hashlib.sha256(
                    f"{comparison.symbol}:{comparison.expected}:{comparison.actual}:{revision}".encode()
                ).hexdigest()[:32]
            )
            incident = OwnershipIncident(
                incident_id=identity,
                symbol=comparison.symbol,
                expected_qty=comparison.expected,
                actual_qty=comparison.actual,
                observed_at=now,
                cause="position_mismatch",
            )
            self._commit(
                self._replace(
                    ownership_incidents=self._snapshot.ownership_incidents | {identity: incident}
                ),
                JournalEvent(at=now, payload=OwnershipIncidentOpened(incident=incident)),
            )

    def resolve_ownership(
        self, request: OwnershipResolutionRequest, checked_at: dt.datetime
    ) -> OwnershipResolution:
        request = OwnershipResolutionRequest.model_validate(request.model_dump())
        prior = self._snapshot.ownership_resolutions.get(request.resolution_id)
        if prior is not None:
            if prior.request != request:
                raise ValueError("Ownership resolution ID conflicts with different content")
            return prior
        if request.account_id != self.account_id:
            raise ValueError("Ownership resolution account identity mismatch")
        incident = self._snapshot.ownership_incidents.get(request.incident_id)
        if incident is None or incident.resolved or incident.symbol != request.symbol:
            raise ValueError("Unresolved symbol ownership incident is required")
        if checked_at <= incident.observed_at:
            raise ValueError("Ownership resolution requires newer broker evidence")
        if self.pending(request.symbol) or any(
            item.symbol == request.symbol and item.unresolved
            for item in self._snapshot.late_order_incidents.values()
        ):
            raise ValueError("Overlapping order uncertainty prevents ownership allocation")
        lot_ids = {key for key, lot in self._snapshot.lots.items() if lot.symbol == request.symbol}
        if set(request.lot_remaining) != lot_ids:
            raise ValueError("Ownership resolution must include every owned lot for the symbol")
        reductions = {}
        lots = self._snapshot.lots.copy()
        for key in lot_ids:
            before = lots[key]
            target = request.lot_remaining[key]
            if target > before.remaining_qty:
                raise ValueError("Ownership resolution cannot invent app-owned shares")
            reductions[key] = before.remaining_qty - target
            lots[key] = OwnedLot.model_validate(before.model_dump() | {"remaining_qty": target})
        allocation_revision = 1 + max(
            (
                prior.allocation_revision
                for prior in self._snapshot.ownership_resolutions.values()
                if prior.request.symbol == request.symbol
            ),
            default=0,
        )
        resolution = OwnershipResolution(
            request=request,
            checked_at=checked_at,
            lot_reductions=reductions,
            allocation_revision=allocation_revision,
        )
        state = self._replace(
            lots=lots,
            external_positions=self._snapshot.external_positions
            | {
                request.symbol: ExternalPosition(
                    symbol=request.symbol,
                    qty=request.external_qty,
                    allocation_revision=allocation_revision,
                )
            },
            ownership_incidents=self._snapshot.ownership_incidents
            | {
                request.incident_id: incident.model_copy(
                    update={"resolved_by": request.resolution_id}
                )
            },
            ownership_resolutions=self._snapshot.ownership_resolutions
            | {request.resolution_id: resolution},
        )
        self._commit(
            state, JournalEvent(at=checked_at, payload=OwnershipResolved(resolution=resolution))
        )
        return resolution

    def receive(self, delivery: DestinationSignal, now: dt.datetime, max_age: int) -> None:
        signal, destination = delivery.signal, delivery.terms
        source_key = f"{signal.source}:{signal.channel_id}"
        key = f"{source_key}:{signal.id}"
        if key in self._snapshot.messages:
            prior = self._snapshot.messages[key]
            original = {name: getattr(prior, name) for name in StockSignal.model_fields}
            if StockSignal.model_validate(original) != signal:
                raise ValueError("Signal identity was reused with different content")
            if prior.destination != destination:
                raise ValueError("A received destination cannot change its accepted terms")
            return
        age = (now - signal.timestamp).total_seconds()
        if signal.decision == "trade":
            status: MessageStatus = "queued"
        elif signal.decision == "ignore":
            status = "ignored"
        else:
            status = "review_required"
        review_reason: Literal["missing_source_fraction"] | None = None
        if (
            status == "queued"
            and destination.connection.mode == "proportional"
            and destination.connection.default_fraction is None
            and any(item.action == "buy" and item.fraction is None for item in signal.instructions)
        ):
            status = "review_required"
            review_reason = "missing_source_fraction"
        if status == "queued" and (age < -5 or age > max_age):
            status = "stale"
        previous = tuple(m for m in self._snapshot.messages.values() if m.source_key == source_key)
        if status == "queued" and any(
            m.decision == "trade"
            and m.status not in {"stale", "out_of_order"}
            and signal.timestamp < m.timestamp
            for m in previous
        ):
            status = "out_of_order"
        parts = tuple(
            Skipped(reason="duplicate")
            if status == "queued"
            and any(
                0 <= (signal.timestamp - m.timestamp).total_seconds() <= 600
                and instruction in m.instructions
                for m in previous
            )
            else Pending()
            for instruction in signal.instructions
        )
        message = MessageRecord.model_validate(
            signal.model_dump()
            | {
                "source_key": source_key,
                "parts": parts,
                "status": status,
                "destination": destination,
                "review_reason": review_reason,
            }
        )
        self._commit(
            self._replace(messages=self._snapshot.messages | {key: message}),
            JournalEvent(
                at=now,
                payload=Message(
                    message_id=key,
                    status=status,
                    parser_decision=signal.decision,
                    parser_reason=signal.reason,
                    parser_profile=signal.parser_profile,
                    instructions=signal.instructions,
                    destination=destination,
                    review_reason=review_reason,
                ),
            ),
        )

    def _message_state(self, key: str, **changes: Unpack[_MessageChanges]) -> LedgerSnapshot:
        message = MessageRecord.model_validate(self.message(key).model_dump() | changes)
        return self._replace(messages=self._snapshot.messages | {key: message})

    def anchor_cash(
        self, key: str, account_id: str, cash: Decimal, buying_power: Decimal, now: dt.datetime
    ) -> CashAnchor:
        """Commit the first broker observation before preparing any buy in this message."""
        message = self.message(key)
        if message.cash_anchor is not None:
            return message.cash_anchor
        if message.status != "queued" or account_id != self.account_id:
            raise RuntimeError("Cannot anchor funds for this message or account")
        anchor = CashAnchor(
            account_id=account_id,
            message_id=key,
            observed_at=now,
            cash=cash,
            buying_power=buying_power,
        )
        self._commit(
            self._message_state(key, cash_anchor=anchor),
            JournalEvent(at=now, payload=CashAnchorRecorded(anchor=anchor)),
        )
        return anchor

    def skip(
        self,
        key: str,
        part: int,
        reason: str,
        now: dt.datetime,
        *,
        exposure: tuple[Exposure, ...] | None = None,
    ) -> None:
        message = self.message(key)
        if message.status != "queued" or not isinstance(message.parts[part], Pending):
            raise RuntimeError("Instruction was already processed")
        parts = list(message.parts)
        parts[part] = Skipped(reason=reason)
        self._commit(
            self._message_state(key, parts=tuple(parts)),
            JournalEvent(
                at=now,
                payload=SkippedEvent(
                    message_id=key,
                    part=part,
                    reason=reason,
                    exposure=exposure,
                ),
            ),
        )

    def complete(self, key: str, now: dt.datetime) -> None:
        self._commit(
            self._message_state(key, status="done"),
            JournalEvent(at=now, payload=MessageDone(message_id=key)),
        )

    def prepare(self, plan: OrderPlan, key: str, part: int, now: dt.datetime) -> OrderRecord:
        message = self.message(key)
        if message.status != "queued" or not isinstance(message.parts[part], Pending):
            raise RuntimeError("Instruction was already processed")
        instruction = message.instructions[part]
        side = "buy" if instruction.action == "buy" else "sell"
        entry_price = instruction.price if side == "buy" else instruction.entry_price
        if (plan.symbol, plan.side, plan.source_price, plan.entry_price) != (
            instruction.symbol,
            side,
            instruction.price,
            entry_price,
        ):
            raise RuntimeError("Order plan differs from its source instruction")
        if plan.side == "buy" and self._snapshot.entry_halted:
            raise RuntimeError("Unresolved late-order incidents halt new buy orders")
        if self.pending(plan.symbol):
            raise RuntimeError("A pending order already owns this symbol")
        client_id = "copy-" + hashlib.sha256(f"{key}:{part}".encode()).hexdigest()[:40]
        if client_id in self._snapshot.orders:
            raise RuntimeError("Order intent already exists")
        order = OrderRecord(
            **plan.model_dump(),
            client_id=client_id,
            message_id=key,
            instruction_index=part,
            source_key=message.source_key,
            status=OrderStatus.PREPARED,
            filled_qty=ZERO,
            broker_id=None,
            created_at=now,
            day=trade_date(now),
        )
        parts = list(message.parts)
        parts[part] = OrderLinked(client_id=client_id)
        updated = MessageRecord.model_validate(message.model_dump() | {"parts": parts})
        state = self._replace(
            messages=self._snapshot.messages | {key: updated},
            orders=self._snapshot.orders | {client_id: order},
        )
        self._commit(
            state,
            JournalEvent(
                at=now,
                payload=OrderPrepared(
                    client_id=client_id,
                    message_id=key,
                    symbol=plan.symbol,
                    side=plan.side,
                    position_intent=plan.position_intent,
                    source_price=plan.source_price,
                    entry_price=plan.entry_price,
                    qty=plan.qty,
                    type=plan.type,
                    limit_price=plan.limit_price,
                    entry_tolerance_pct=plan.entry_tolerance_pct,
                    session=plan.session,
                ),
            ),
        )
        return order

    def _order_state(self, key: str, **changes: Unpack[_OrderChanges]) -> LedgerSnapshot:
        order = OrderRecord.model_validate(self.order(key).model_dump() | changes)
        return self._replace(orders=self._snapshot.orders | {key: order})

    def submitting(self, key: str, now: dt.datetime) -> None:
        order = self.order(key)
        if order.status != OrderStatus.PREPARED or order.submit_started_at is not None:
            raise RuntimeError("Only a never-submitted prepared intent can be submitted")
        self._commit(
            self._order_state(key, submit_started_at=now),
            JournalEvent(
                at=now,
                payload=SubmitStarted(
                    client_id=key,
                    message_id=order.message_id,
                    submit_started_at=now,
                ),
            ),
        )

    def abort_before_submit(self, key: str, reason: str, now: dt.datetime) -> None:
        order = self.order(key)
        if order.status != "prepared" or order.broker_id is not None or order.filled_qty:
            raise RuntimeError("Only an unsubmitted prepared order can be aborted")
        validate_transition(order.status, OrderStatus.ABORTED_BEFORE_SUBMIT)
        self._commit(
            self._order_state(key, status=OrderStatus.ABORTED_BEFORE_SUBMIT),
            JournalEvent(
                at=now,
                payload=SubmissionAborted(
                    client_id=key, message_id=order.message_id, reason=reason
                ),
            ),
        )

    def uncertain(self, key: str, now: dt.datetime) -> None:
        order = self.order(key)
        if order.status != OrderStatus.UNCERTAIN:
            validate_transition(order.status, OrderStatus.UNCERTAIN)
            self._commit(
                self._order_state(key, status=OrderStatus.UNCERTAIN),
                JournalEvent(
                    at=now,
                    payload=SubmissionUncertain(client_id=key, message_id=order.message_id),
                ),
            )

    def submission_failed(self, key: str, http_status: int | None, now: dt.datetime) -> None:
        status = (
            OrderStatus.REJECTED if http_status in {400, 401, 403, 422} else OrderStatus.UNCERTAIN
        )
        validate_transition(self.order(key).status, status)
        self._commit(
            self._order_state(key, status=status),
            JournalEvent(
                at=now,
                payload=SubmitError(
                    client_id=key,
                    message_id=self.order(key).message_id,
                    status=status,
                    http_status=http_status,
                ),
            ),
        )

    def release_uncertain_intent(self, client_id: str, evidence: ReleaseEvidence) -> None:
        """Record an audited release without resubmitting the original instruction."""
        order = self.order(client_id)
        if order.status != OrderStatus.UNCERTAIN:
            raise ValueError("Only an uncertain order intent can be released")
        if order.filled_qty != ZERO or order.broker_id is not None:
            raise ValueError("An uncertain intent with saved broker activity cannot be released")
        if evidence.submission_state == "started":
            if order.submit_started_at is None:
                raise ValueError("Release evidence claims a submission marker that is absent")
            if evidence.checked_at < order.submit_started_at:
                raise ValueError("Release evidence must follow the attempted submission")
        elif order.submit_started_at is not None:
            raise ValueError("Release evidence says submission never started, but a marker exists")
        elif evidence.checked_at < order.created_at:
            raise ValueError("Release evidence must follow the prepared intent")
        if client_id in self._snapshot.release_evidence:
            raise ValueError("Order intent already has release evidence")
        if self.account_id is None or evidence.account_id != self.account_id:
            raise ValueError("Release evidence belongs to a different account")
        validate_transition(order.status, OrderStatus.RELEASED_UNSUBMITTED)
        released = OrderRecord.model_validate(
            order.model_dump() | {"status": OrderStatus.RELEASED_UNSUBMITTED}
        )
        state = self._replace(
            orders=self._snapshot.orders | {client_id: released},
            release_evidence=self._snapshot.release_evidence | {client_id: evidence},
        )
        self._commit(
            state,
            JournalEvent(
                at=evidence.checked_at,
                payload=OrderIntentReleased(
                    client_id=client_id,
                    message_id=order.message_id,
                    previous_status="uncertain",
                    status="released_unsubmitted",
                    evidence=evidence,
                    entry_halted=state.entry_halted,
                ),
            ),
        )

    def clear_late_order_incident(
        self, client_id: str, evidence: IncidentClearanceEvidence
    ) -> None:
        """Persist operator clearance after a matched position audit."""
        incident = self._snapshot.late_order_incidents.get(client_id)
        if incident is None:
            raise ValueError("No late-order incident exists for this client ID")
        if incident.cleared:
            raise ValueError("Late-order incident is already cleared")
        order = self.order(client_id)
        if is_pending(order.status):
            raise ValueError("Cannot clear a late-order incident while its order is pending")
        if any(is_pending(self.order(key).status) for key in incident.conflicting_order_ids):
            raise ValueError(
                "Cannot clear a late-order incident while a conflicting order is pending"
            )
        if self.account_id is None or evidence.account_id != self.account_id:
            raise ValueError("Clearance evidence belongs to a different account")
        if evidence.checked_at < incident.last_observed_at:
            raise ValueError("Clearance requires an audit after the latest broker observation")
        if evidence.symbol is not None and evidence.symbol != incident.symbol:
            raise ValueError("Clearance position evidence does not match the late order symbol")
        if evidence.expected_qty is not None and evidence.expected_qty != self.expected_position(
            incident.symbol
        ):
            raise ValueError("Clearance expected quantity does not match ledger quantity")
        cleared = incident.model_copy(
            update={
                "clearance_history": (*incident.clearance_history, evidence),
                "cleared": True,
            }
        )
        state = self._replace(
            late_order_incidents=self._snapshot.late_order_incidents | {client_id: cleared}
        )
        self._commit(
            state,
            JournalEvent(
                at=evidence.checked_at,
                payload=LateOrderIncidentCleared(
                    client_id=client_id,
                    message_id=order.message_id,
                    broker_id=incident.broker_id,
                    order_symbol=incident.symbol,
                    evidence=evidence,
                    entry_halted=state.entry_halted,
                ),
            ),
        )

    def apply_order(self, key: str, update: BrokerOrder, now: dt.datetime) -> None:
        order = self.order(key)
        if update.client_order_id != order.client_id:
            raise RuntimeError("Broker returned an order with a different client ID")
        if (update.symbol, update.side) != (order.symbol, order.side):
            raise RuntimeError("Broker order identity mismatch")
        if update.position_intent is not None and update.position_intent != order.position_intent:
            raise RuntimeError("Broker order position intent mismatch")
        if order.broker_id and update.id != order.broker_id:
            raise RuntimeError("Broker order identity changed")
        if update.qty != order.qty:
            raise RuntimeError("Broker order quantity mismatch")
        status = map_broker_status(update.status)
        validate_transition(order.status, status)
        delta = update.filled_qty - order.filled_qty
        if delta < 0:
            raise RuntimeError("Broker fill quantity is inconsistent with the saved order")
        lots = self._snapshot.lots
        quarantined_fills = self._snapshot.quarantined_fills
        previous_quarantine = quarantined_fills.get(key)
        related_incident_ids = tuple(
            sorted(
                incident_id
                for incident_id, incident in self._snapshot.late_order_incidents.items()
                if not incident.cleared
                and key in incident.conflicting_order_ids
                and order.lot_id is not None
                and self.order(incident_id).lot_id == order.lot_id
            )
        )
        if key in self._snapshot.release_evidence:
            related_incident_ids = tuple(sorted((*related_incident_ids, key)))
        if delta:
            average = update.filled_avg_price
            if average is None:
                raise RuntimeError("A fill requires its average price")
            if order.side == "buy":
                if order.limit_price is None:
                    raise RuntimeError("Buy order has no saved limit")
                if average > order.limit_price:
                    raise RuntimeError("Broker buy fill exceeds the saved limit")
                lot = lots.get(key)
                updated_lot = OwnedLot(
                    symbol=order.symbol,
                    entry_price=order.entry_price,
                    source_key=order.source_key,
                    original_qty=update.filled_qty,
                    remaining_qty=(lot.remaining_qty if lot else ZERO) + delta,
                    average_price=average,
                )
                lots = lots | {key: updated_lot}
            else:
                if order.lot_id is None:
                    raise RuntimeError("Sell order has no owned lot")
                lot = lots[order.lot_id]
                applied_delta = min(delta, lot.remaining_qty)
                unapplied_delta = delta - applied_delta
                if unapplied_delta and not related_incident_ids:
                    raise RuntimeError("Sell fill exceeds the copier's owned lot")
                if applied_delta:
                    lots = lots | {
                        order.lot_id: OwnedLot.model_validate(
                            lot.model_dump() | {"remaining_qty": lot.remaining_qty - applied_delta}
                        )
                    }
                if previous_quarantine is not None or unapplied_delta:
                    incident_client_ids = tuple(
                        sorted(
                            set(
                                previous_quarantine.incident_client_ids
                                if previous_quarantine is not None
                                else ()
                            )
                            | set(related_incident_ids)
                        )
                    )
                    quarantined_fills = quarantined_fills | {
                        key: QuarantinedFill(
                            client_id=key,
                            broker_id=update.id,
                            lot_id=order.lot_id,
                            symbol=order.symbol,
                            observed_filled_qty=update.filled_qty,
                            applied_filled_qty=(
                                previous_quarantine.applied_filled_qty
                                if previous_quarantine is not None
                                else order.filled_qty
                            )
                            + applied_delta,
                            unapplied_qty=(
                                previous_quarantine.unapplied_qty
                                if previous_quarantine is not None
                                else ZERO
                            )
                            + unapplied_delta,
                            average_price=average,
                            first_observed_at=(
                                previous_quarantine.first_observed_at
                                if previous_quarantine is not None
                                else now
                            ),
                            last_observed_at=now,
                            incident_client_ids=incident_client_ids,
                        )
                    }
        status_changed = order.status != status
        raw_status_changed = order.raw_broker_status != update.status
        order_changed = (
            delta or status_changed or raw_status_changed or order.broker_id != update.id
        )
        if order_changed:
            if previous_quarantine is not None and not delta:
                average = update.filled_avg_price
                if average is None:
                    raise RuntimeError("A quarantined fill requires its average price")
                quarantined_fills = quarantined_fills | {
                    key: previous_quarantine.model_copy(
                        update={"average_price": average, "last_observed_at": now}
                    )
                }
            updated_order = OrderRecord.model_validate(
                order.model_dump()
                | {
                    "status": status,
                    "filled_qty": update.filled_qty,
                    "broker_id": update.id,
                    "raw_broker_status": update.status,
                    "filled_avg_price": update.filled_avg_price or order.filled_avg_price,
                }
            )
            incidents = self._snapshot.late_order_incidents
            previous_incident = incidents.get(key)
            newly_observed_late = (
                order.status == OrderStatus.RELEASED_UNSUBMITTED
                and key in self._snapshot.release_evidence
            )
            reopened = bool(previous_incident and previous_incident.cleared)
            if newly_observed_late:
                conflicting_order_ids = tuple(
                    sorted(
                        candidate.client_id
                        for candidate in self._snapshot.orders.values()
                        if candidate.client_id != key
                        and candidate.side == "sell"
                        and candidate.lot_id == order.lot_id
                        and candidate.created_at <= now
                        and (candidate.pending or candidate.filled_qty > ZERO)
                    )
                )
                incidents = incidents | {
                    key: LateOrderIncident(
                        client_id=key,
                        broker_id=update.id,
                        symbol=update.symbol,
                        side=update.side,
                        first_observed_at=now,
                        last_observed_at=now,
                        latest_status=status,
                        raw_broker_status=update.status,
                        latest_filled_qty=update.filled_qty,
                        conflicting_order_ids=conflicting_order_ids,
                    )
                }
                for conflicting_id in conflicting_order_ids:
                    conflicting_fill = quarantined_fills.get(conflicting_id)
                    if conflicting_fill is not None:
                        quarantined_fills = quarantined_fills | {
                            conflicting_id: conflicting_fill.model_copy(
                                update={
                                    "incident_client_ids": tuple(
                                        sorted(set(conflicting_fill.incident_client_ids) | {key})
                                    )
                                }
                            )
                        }
            elif previous_incident is not None:
                incidents = incidents | {
                    key: previous_incident.model_copy(
                        update={
                            "last_observed_at": now,
                            "latest_status": status,
                            "raw_broker_status": update.status,
                            "latest_filled_qty": update.filled_qty,
                            "cleared": False if reopened else previous_incident.cleared,
                        }
                    )
                }
            state = self._replace(
                orders=self._snapshot.orders | {key: updated_order},
                lots=lots,
                late_order_incidents=incidents,
                quarantined_fills=quarantined_fills,
            )
            quarantine = quarantined_fills.get(key)
            event_incident = incidents.get(key)
            if quarantine is not None:
                applied_fill_qty = quarantine.applied_filled_qty
                unapplied_fill_qty = quarantine.unapplied_qty
                incident_ids = quarantine.incident_client_ids
            elif event_incident is not None:
                applied_fill_qty = update.filled_qty
                unapplied_fill_qty = ZERO
                incident_ids = None
            else:
                applied_fill_qty = None
                unapplied_fill_qty = None
                incident_ids = None
            if newly_observed_late:
                if event_incident is None:
                    raise RuntimeError("New late-order incident was not persisted in state")
                payload = LateOrderIncidentOpened(
                    client_id=key,
                    message_id=order.message_id,
                    status=status,
                    raw_broker_status=update.status,
                    filled_qty=update.filled_qty,
                    filled_avg_price=update.filled_avg_price,
                    applied_fill_qty=applied_fill_qty,
                    unapplied_fill_qty=unapplied_fill_qty,
                    late_order_incident_ids=incident_ids,
                    entry_halted=state.entry_halted,
                    late_order_incident=event_incident,
                )
            elif reopened:
                if event_incident is None:
                    raise RuntimeError("Reopened late-order incident was not persisted in state")
                payload = LateOrderIncidentReopened(
                    client_id=key,
                    message_id=order.message_id,
                    status=status,
                    raw_broker_status=update.status,
                    filled_qty=update.filled_qty,
                    filled_avg_price=update.filled_avg_price,
                    applied_fill_qty=applied_fill_qty,
                    unapplied_fill_qty=unapplied_fill_qty,
                    late_order_incident_ids=incident_ids,
                    entry_halted=state.entry_halted,
                    late_order_incident=event_incident,
                )
            else:
                payload = OrderUpdate(
                    client_id=key,
                    message_id=order.message_id,
                    status=status,
                    raw_broker_status=update.status,
                    filled_qty=update.filled_qty,
                    filled_avg_price=update.filled_avg_price,
                    applied_fill_qty=applied_fill_qty,
                    unapplied_fill_qty=unapplied_fill_qty,
                    late_order_incident_ids=incident_ids,
                    entry_halted=state.entry_halted,
                    late_order_incident=event_incident,
                )
            self._commit(
                state,
                JournalEvent(at=now, payload=payload),
            )
