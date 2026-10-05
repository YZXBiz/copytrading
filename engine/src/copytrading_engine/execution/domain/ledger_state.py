"""Canonical progress and aggregate state for the execution ledger."""

from decimal import Decimal
from typing import Literal, Self

from pydantic import AwareDatetime, ConfigDict, Field, model_validator

from copytrading_engine.execution.domain.lifecycle import AccountControl
from copytrading_engine.execution.domain.lot_sales import LotSalePreview, LotSaleRecord
from copytrading_engine.execution.domain.manual_commands import (
    ManualCommandRecord,
    ManualCorrectionRecord,
    ManualOrderPreview,
)
from copytrading_engine.execution.domain.order_lifecycle import (
    OrderStatus,
    is_pending,
    map_broker_status,
)
from copytrading_engine.execution.domain.orders import OrderPlan, OrderRecord, OwnedLot
from copytrading_engine.execution.domain.ownership import (
    ExternalPosition,
    OwnershipIncident,
    OwnershipResolution,
)
from copytrading_engine.execution.domain.progress import InstructionProgress, OrderLinked, Pending
from copytrading_engine.execution.domain.recovery import (
    LateOrderIncident,
    ManualSale,
    QuarantinedFill,
    ReleaseEvidence,
)
from copytrading_engine.execution.domain.sizing import DestinationTerms
from copytrading_engine.execution.domain.values import Identifier, Quantity, Value
from copytrading_engine.shared.signals import StockSignal

MessageStatus = Literal[
    "queued",
    "done",
    "stale",
    "out_of_order",
    "ignored",
    "review_required",
]


class CashAnchor(Value):
    """First observed funds for a message, committed before any buy intent.

    A later broker balance has no freshness marker. The lower of that balance and
    this anchor less known order commitments bounds every later entry in the message.
    """

    account_id: Identifier
    message_id: Identifier
    observed_at: AwareDatetime
    cash: Quantity
    buying_power: Quantity


class MessageRecord(StockSignal):
    model_config = ConfigDict(frozen=True, extra="forbid", hide_input_in_errors=True)
    source_key: Identifier
    destination: DestinationTerms
    parts: tuple[InstructionProgress, ...]
    status: MessageStatus
    review_reason: Literal["missing_source_fraction"] | None = None
    cash_anchor: CashAnchor | None = None

    @model_validator(mode="after")
    def valid_progress(self) -> Self:
        if len(self.parts) != len(self.instructions):
            raise ValueError("Every instruction requires a progress slot")
        if self.source_key != f"{self.source}:{self.channel_id}":
            raise ValueError("Message source identity mismatch")
        if self.status == "done" and any(isinstance(part, Pending) for part in self.parts):
            raise ValueError("Completed message still has Pending instructions")
        if self.review_reason is not None and self.status != "review_required":
            raise ValueError("Destination review reason requires review status")
        return self

    @property
    def key(self) -> str:
        return f"{self.source_key}:{self.id}"


class LedgerSnapshot(Value):
    schema_version: Literal[9] = 9
    account_id: Identifier | None = None
    control: AccountControl = Field(default_factory=AccountControl)
    environment: Literal["paper", "live"] | None = None
    messages: dict[str, MessageRecord] = Field(default_factory=dict)
    orders: dict[str, OrderRecord] = Field(default_factory=dict)
    lots: dict[str, OwnedLot] = Field(default_factory=dict)
    manual_sales: dict[str, ManualSale] = Field(default_factory=dict)
    release_evidence: dict[str, ReleaseEvidence] = Field(default_factory=dict)
    late_order_incidents: dict[str, LateOrderIncident] = Field(default_factory=dict)
    quarantined_fills: dict[str, QuarantinedFill] = Field(default_factory=dict)
    external_positions: dict[str, ExternalPosition] = Field(default_factory=dict)
    ownership_incidents: dict[str, OwnershipIncident] = Field(default_factory=dict)
    ownership_resolutions: dict[str, OwnershipResolution] = Field(default_factory=dict)
    manual_corrections: dict[str, ManualCorrectionRecord] = Field(default_factory=dict)
    manual_previews: dict[str, ManualOrderPreview] = Field(default_factory=dict)
    manual_commands: dict[str, ManualCommandRecord] = Field(default_factory=dict)
    lot_sale_previews: dict[str, LotSalePreview] = Field(default_factory=dict)
    lot_sales: dict[str, LotSaleRecord] = Field(default_factory=dict)

    @property
    def entry_halted(self) -> bool:
        # Quarantined fills stay as audit evidence after a matched clearance;
        # their linked late-order incident determines whether activity is unresolved.
        return any(incident.unresolved for incident in self.late_order_incidents.values())

    @property
    def buy_halted(self) -> bool:
        return self.entry_halted

    @property
    def has_outstanding_work(self) -> bool:
        """A call still to act on, or an order still open: work a clock decides, such as an
        order timeout or a call waiting for the market to open, so its account checks often."""
        return any(message.status == "queued" for message in self.messages.values()) or any(
            order.pending for order in self.orders.values()
        )

    @model_validator(mode="after")
    def validate_references(self) -> Self:
        has_state = (
            self.orders
            or self.lots
            or self.release_evidence
            or self.late_order_incidents
            or self.quarantined_fills
            or self.external_positions
            or self.ownership_incidents
            or self.ownership_resolutions
            or self.manual_corrections
            or self.manual_previews
            or self.manual_commands
            or self.lot_sale_previews
            or self.lot_sales
        )
        if has_state and not self.account_id:
            raise ValueError("An active ledger requires an account identity")
        if self.environment is not None and self.account_id is None:
            raise ValueError("A ledger environment requires an account identity")
        for key, position in self.external_positions.items():
            if key != position.symbol:
                raise ValueError("External position symbol identity mismatch")
        for key, incident in self.ownership_incidents.items():
            if key != incident.incident_id:
                raise ValueError("Ownership incident identity mismatch")
            if incident.resolved_by is not None:
                resolution = self.ownership_resolutions.get(incident.resolved_by)
                if resolution is None or resolution.request.incident_id != key:
                    raise ValueError("Resolved ownership incident has no matching resolution")
        for key, resolution in self.ownership_resolutions.items():
            request = resolution.request
            incident = self.ownership_incidents.get(request.incident_id)
            if (
                key != request.resolution_id
                or request.account_id != self.account_id
                or incident is None
                or incident.symbol != request.symbol
                or incident.resolved_by != key
            ):
                raise ValueError("Ownership resolution identity or allocation mismatch")
            if any(
                lot_id not in self.lots or self.lots[lot_id].symbol != request.symbol
                for lot_id in request.lot_remaining
            ):
                raise ValueError("Ownership resolution refers to an unknown owned lot")
            if set(resolution.lot_reductions) != set(request.lot_remaining):
                raise ValueError("Ownership resolution lot allocation is incomplete")
            if resolution.checked_at <= incident.observed_at:
                raise ValueError("Ownership resolution evidence predates the incident")
        allocation_revisions: dict[str, dict[int, OwnershipResolution]] = {}
        for resolution in self.ownership_resolutions.values():
            symbol = resolution.request.symbol
            revisions = allocation_revisions.setdefault(symbol, {})
            if resolution.allocation_revision in revisions:
                raise ValueError("Duplicate ownership allocation revision")
            revisions[resolution.allocation_revision] = resolution
        for symbol, position in self.external_positions.items():
            revisions = allocation_revisions.get(symbol, {})
            if set(revisions) != set(range(1, len(revisions) + 1)):
                raise ValueError("Ownership allocation revisions are incomplete")
            latest = revisions.get(len(revisions))
            if position.allocation_revision != len(revisions) or (
                latest is not None and position.qty != latest.request.external_qty
            ):
                raise ValueError("External position does not match latest ownership allocation")
        if any(symbol not in self.external_positions for symbol in allocation_revisions):
            raise ValueError("Ownership allocation has no current external position")
        if any(key != message.key for key, message in self.messages.items()):
            raise ValueError("Snapshot message identity mismatch")
        for message_key, message in self.messages.items():
            anchor = message.cash_anchor
            if anchor is not None and (
                anchor.account_id != self.account_id or anchor.message_id != message_key
            ):
                raise ValueError("Cash anchor does not match its message and account")
            for instruction_index, progress in enumerate(message.parts):
                if isinstance(progress, OrderLinked):
                    order = self.orders.get(progress.client_id)
                    if order is None or (order.message_id, order.instruction_index) != (
                        message_key,
                        instruction_index,
                    ):
                        raise ValueError("Order link does not match its message instruction")
        correction_revisions: set[tuple[str, int]] = set()
        for key, correction in self.manual_corrections.items():
            message = self.messages.get(correction.source_id)
            accepted = (
                StockSignal.model_validate(
                    {name: getattr(message, name) for name in StockSignal.model_fields}
                )
                if message is not None
                else None
            )
            revision_key = (correction.source_id, correction.revision)
            if (
                key != correction.correction_id
                or revision_key in correction_revisions
                or message is None
                or message.status != "review_required"
                or message.decision != "review"
                or accepted != correction.accepted_interpretation
                or correction.source_text != message.text
                or correction.source_at != message.timestamp
                or message.destination.connection.account_id not in correction.selected_account_ids
            ):
                raise ValueError("Manual correction does not match reviewed source evidence")
            correction_revisions.add(revision_key)
        for key, preview in self.manual_previews.items():
            correction = self.manual_corrections.get(preview.request.correction_id)
            instruction_index = preview.request.instruction_index
            if (
                key != preview.request.preview_id
                or correction is None
                or preview.request.account_id not in correction.selected_account_ids
                or preview.broker_account_id != self.account_id
                or preview.environment != self.environment
                or preview.correction_revision != correction.revision
                or instruction_index >= len(correction.instructions)
                or preview.source_at != correction.source_at
                or preview.instruction != correction.instructions[instruction_index]
            ):
                raise ValueError("Manual preview does not match its correction and owner")
            if preview.plan is not None:
                instruction = correction.instructions[instruction_index]
                expected_side = "buy" if instruction.action == "buy" else "sell"
                expected_entry = (
                    instruction.price
                    if expected_side == "buy"
                    else instruction.entry_price
                    if instruction.entry_price is not None
                    else preview.plan.entry_price
                )
                if (
                    preview.plan.side,
                    preview.plan.symbol,
                    preview.plan.source_price,
                    preview.plan.entry_price,
                ) != (
                    expected_side,
                    instruction.symbol,
                    instruction.price,
                    expected_entry,
                ):
                    raise ValueError("Manual preview plan differs from corrected instruction")
        manual_order_ids: set[str] = set()
        for key, command in self.manual_commands.items():
            preview = self.manual_previews.get(command.request.preview_id)
            correction = self.manual_corrections.get(command.correction_id)
            if (
                key != command.request.command_id
                or correction is None
                or command.request.account_id not in correction.selected_account_ids
                or preview is None
                or preview.request.account_id != command.request.account_id
                or preview.request.correction_id != command.correction_id
                or preview.request.instruction_index != command.instruction_index
                or command.source_id != correction.source_id
                or (command.state == "prepared" and preview.plan is None)
            ):
                raise ValueError("Manual command does not match its saved correction preview")
            if command.state == "prepared":
                assert preview.plan is not None
                if (
                    command.client_id is None
                    or command.client_id not in self.orders
                    or self.orders[command.client_id].message_id != correction.source_id
                    or self.orders[command.client_id].instruction_index != command.instruction_index
                    or self.orders[command.client_id].source_key
                    != self.messages[correction.source_id].source_key
                    or self.orders[command.client_id].model_dump(
                        include=set(OrderPlan.model_fields)
                    )
                    != preview.plan.model_dump()
                ):
                    raise ValueError("Manual command intent differs from its saved preview")
            if command.client_id is not None:
                if command.client_id in manual_order_ids:
                    raise ValueError("Manual commands share an order intent")
                manual_order_ids.add(command.client_id)
        for key, preview in self.lot_sale_previews.items():
            if (
                key != preview.request.preview_id
                or preview.broker_account_id != self.account_id
                or preview.environment != self.environment
            ):
                raise ValueError("Lot sale preview does not match its account")
        for key, sale in self.lot_sales.items():
            preview = self.lot_sale_previews.get(sale.request.preview_id)
            if (
                key != sale.request.command_id
                or preview is None
                or preview.request.account_id != sale.request.account_id
                or preview.request.lot_id != sale.lot_id
                or (sale.state == "prepared" and preview.plan is None)
            ):
                raise ValueError("Lot sale does not match its saved preview")
            if sale.state == "prepared":
                assert preview.plan is not None
                order = self.orders.get(sale.client_id or "")
                if (
                    order is None
                    or order.lot_id != sale.lot_id
                    or order.model_dump(include=set(OrderPlan.model_fields))
                    != preview.plan.model_dump()
                ):
                    raise ValueError("Lot sale intent differs from its saved preview")
            if sale.client_id is not None:
                if sale.client_id in manual_order_ids:
                    raise ValueError("Owner commands share an order intent")
                manual_order_ids.add(sale.client_id)
        broker_ids = {order.broker_id for order in self.orders.values() if order.broker_id}
        if len(broker_ids) != sum(order.broker_id is not None for order in self.orders.values()):
            raise ValueError("Snapshot contains duplicate broker order identities")
        client_ids = set(self.orders)
        for key, evidence in self.release_evidence.items():
            order = self.orders.get(key)
            if (
                key != (order.client_id if order else None)
                or evidence.account_id != self.account_id
            ):
                raise ValueError("Release evidence does not match its order and account")
            if order is None:
                raise ValueError("Release evidence does not match a submitted or released intent")
            if evidence.submission_state == "started":
                submission_matches = (
                    order.submit_started_at is not None
                    and evidence.checked_at >= order.submit_started_at
                )
            else:
                submission_matches = (
                    order.submit_started_at is None and evidence.checked_at >= order.created_at
                )
            if not submission_matches or (
                order.status != OrderStatus.RELEASED_UNSUBMITTED
                and (
                    order.raw_broker_status is None
                    or map_broker_status(order.raw_broker_status) != order.status
                )
            ):
                raise ValueError("Release evidence does not match a submitted or released intent")
            if (
                order.status != OrderStatus.RELEASED_UNSUBMITTED
                and key not in self.late_order_incidents
            ):
                raise ValueError("Observed released order is missing its late-order incident")
        for key, order in self.orders.items():
            if order.status == OrderStatus.RELEASED_UNSUBMITTED:
                if (
                    key not in self.release_evidence
                    or order.broker_id is not None
                    or order.filled_qty
                ):
                    raise ValueError(
                        "Released order intent must have evidence and no broker activity"
                    )
        for key, incident in self.late_order_incidents.items():
            order = self.orders.get(key)
            if (
                key != incident.client_id
                or key not in self.release_evidence
                or order is None
                or (order.broker_id, order.symbol, order.side, order.status, order.filled_qty)
                != (
                    incident.broker_id,
                    incident.symbol,
                    incident.side,
                    incident.latest_status,
                    incident.latest_filled_qty,
                )
                or order.raw_broker_status != incident.raw_broker_status
                or incident.first_observed_at < self.release_evidence[key].checked_at
                or any(item.account_id != self.account_id for item in incident.clearance_history)
                or any(
                    conflicting_id not in self.orders
                    or self.orders[conflicting_id].side != "sell"
                    or self.orders[conflicting_id].lot_id != order.lot_id
                    or self.orders[conflicting_id].symbol != order.symbol
                    or self.orders[conflicting_id].created_at > incident.first_observed_at
                    for conflicting_id in incident.conflicting_order_ids
                )
                or (
                    incident.cleared
                    and (
                        is_pending(order.status)
                        or any(
                            is_pending(self.orders[conflicting_id].status)
                            for conflicting_id in incident.conflicting_order_ids
                        )
                        or incident.clearance_history[-1].checked_at < incident.last_observed_at
                    )
                )
            ):
                raise ValueError("Late-order incident does not match its order or account")
        for key, fill in self.quarantined_fills.items():
            order = self.orders.get(key)
            if (
                key != fill.client_id
                or order is None
                or order.side != "sell"
                or (fill.broker_id, fill.lot_id, fill.symbol, fill.observed_filled_qty)
                != (order.broker_id, order.lot_id, order.symbol, order.filled_qty)
            ):
                raise ValueError("Quarantined fill does not match its broker order")
            for incident_id in fill.incident_client_ids:
                incident = self.late_order_incidents.get(incident_id)
                incident_order = self.orders.get(incident_id)
                if (
                    incident is None
                    or incident_order is None
                    or incident_id not in self.release_evidence
                    or incident.side != "sell"
                    or incident_order.lot_id != fill.lot_id
                    or incident.symbol != fill.symbol
                    or (
                        incident_id != key
                        and (
                            key not in incident.conflicting_order_ids
                            or order.created_at > incident.first_observed_at
                        )
                    )
                    or (
                        incident_id == key
                        and fill.observed_filled_qty != incident.latest_filled_qty
                    )
                ):
                    raise ValueError("Quarantined fill has an invalid incident association")
            for incident in self.late_order_incidents.values():
                if (
                    key in incident.conflicting_order_ids
                    and incident.client_id not in fill.incident_client_ids
                ):
                    raise ValueError("Quarantined fill is missing its associated incident")
        for incident_id, incident in self.late_order_incidents.items():
            for conflicting_id in incident.conflicting_order_ids:
                fill = self.quarantined_fills.get(conflicting_id)
                if fill is not None and incident_id not in fill.incident_client_ids:
                    raise ValueError("Incident is missing its conflicting quarantined fill link")
        for key, sale in self.manual_sales.items():
            lot = self.lots.get(sale.lot_id or "")
            if key != sale.order.id or (
                sale.lot_id is not None and (lot is None or lot.symbol != sale.order.symbol)
            ):
                raise ValueError("Manual sale identity or lot mismatch")
            if sale.lot_id is None and key not in self.ownership_incidents:
                raise ValueError("Unallocated manual sale requires an ownership incident")
            if sale.lot_id is None:
                incident = self.ownership_incidents[key]
                if (
                    incident.cause != "manual_sale"
                    or incident.symbol != sale.order.symbol
                    or incident.expected_qty - sale.order.filled_qty != incident.actual_qty
                ):
                    raise ValueError("Manual sale ownership incident does not match its fill")
            if sale.order.id in broker_ids or sale.order.client_order_id in client_ids:
                raise ValueError("Manual sale duplicates an already recorded order")
            broker_ids.add(sale.order.id)
            client_ids.add(sale.order.client_order_id)
        entry_lots: dict[str, str] = {}
        for lot_key, lot in self.lots.items():
            for entry in lot.entries(lot_key):
                if entry in entry_lots:
                    raise ValueError("A buy order belongs to more than one lot")
                entry_lots[entry] = lot_key
        for key, order in self.orders.items():
            message = self.messages.get(order.message_id)
            if key != order.client_id or message is None or order.source_key != message.source_key:
                raise ValueError("Snapshot order identity mismatch")
            manual = key in manual_order_ids
            if not manual and (
                order.instruction_index >= len(message.parts)
                or message.parts[order.instruction_index] != OrderLinked(client_id=key)
            ):
                raise ValueError("Recorded order has no matching instruction reservation")
            if (
                order.side == "buy"
                and not manual
                and (
                    message.cash_anchor is None
                    or order.created_at < message.cash_anchor.observed_at
                )
            ):
                raise ValueError("Buy order requires a preceding cash anchor")
            if order.side == "buy" and order.filled_qty > 0 and key not in entry_lots:
                raise ValueError("Entry fills require an owned lot")
            if order.side == "sell":
                lot = self.lots.get(order.lot_id or "")
                if lot is None or (lot.symbol, lot.source_key, lot.entry_price) != (
                    order.symbol,
                    order.source_key,
                    order.entry_price,
                ):
                    raise ValueError("Sell order references an unknown or different lot")
        for key, lot in self.lots.items():
            entries = [self.orders.get(entry) for entry in lot.entries(key)]
            # A buy that joined this lot for a whole-position guru may be at another price.
            if any(
                entry is None
                or entry.side != "buy"
                or (lot.symbol, lot.source_key) != (entry.symbol, entry.source_key)
                or (lot.entry_price != entry.entry_price and entry.joins_lot != key)
                for entry in entries
            ) or lot.original_qty != sum(
                (entry.filled_qty for entry in entries if entry is not None), Decimal(0)
            ):
                raise ValueError("Snapshot lot does not match its entry fills")
            sold = sum(
                (
                    order.filled_qty
                    - (
                        self.quarantined_fills[order.client_id].unapplied_qty
                        if order.client_id in self.quarantined_fills
                        else Decimal(0)
                    )
                    for order in self.orders.values()
                    if order.side == "sell" and order.lot_id == key
                ),
                Decimal(0),
            )
            manually_sold = sum(
                (
                    sale.order.filled_qty
                    for sale in self.manual_sales.values()
                    if sale.lot_id == key
                ),
                Decimal(0),
            )
            ownership_reductions = sum(
                (
                    resolution.lot_reductions.get(key, Decimal(0))
                    for resolution in self.ownership_resolutions.values()
                ),
                Decimal(0),
            )
            if lot.remaining_qty != lot.original_qty - sold - manually_sold - ownership_reductions:
                raise ValueError("Lot quantity does not match recorded sell fills")
        return self
