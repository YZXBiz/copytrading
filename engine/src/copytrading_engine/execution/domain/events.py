"""Typed immutable journal events committed by the execution ledger."""

from typing import Annotated, Literal

from pydantic import AwareDatetime, ConfigDict, Field

from copytrading_engine.execution.domain.ledger_state import CashAnchor, MessageStatus
from copytrading_engine.execution.domain.lifecycle import AccountControlResult
from copytrading_engine.execution.domain.lot_sales import LotSalePreview, LotSaleRecord
from copytrading_engine.execution.domain.manual_commands import (
    ManualCommandRecord,
    ManualCorrectionRecord,
    ManualOrderPreview,
)
from copytrading_engine.execution.domain.market import Quote
from copytrading_engine.execution.domain.order_lifecycle import OrderStatus
from copytrading_engine.execution.domain.orders import CancelReason, OrderPlan
from copytrading_engine.execution.domain.ownership import (
    ExternalPosition,
    OwnershipIncident,
    OwnershipResolution,
)
from copytrading_engine.execution.domain.progress import Exposure, SellWait
from copytrading_engine.execution.domain.recovery import (
    IncidentClearanceEvidence,
    LateOrderIncident,
    ManualSale,
    ReleaseEvidence,
)
from copytrading_engine.execution.domain.sessions import Session
from copytrading_engine.execution.domain.sizing import DestinationTerms
from copytrading_engine.execution.domain.values import Identifier, Positive, Quantity, Side, Value
from copytrading_engine.shared.signals import Instruction


class EventPayloadValue(Value):
    """Keep constructor defaults while requiring them in serialized JSON Schema."""

    model_config = ConfigDict(json_schema_serialization_defaults_required=True)


class AccountBound(EventPayloadValue):
    kind: Literal["account_bound"] = "account_bound"
    endpoint: Identifier


class AccountInventoried(EventPayloadValue):
    kind: Literal["account_inventoried"] = "account_inventoried"
    account_id: Identifier
    environment: Literal["paper", "live"]
    external_positions: dict[str, ExternalPosition]


class AccountControlChanged(EventPayloadValue):
    kind: Literal["account_control_changed"] = "account_control_changed"
    result: AccountControlResult


class LimitChange(Value):
    """One account limit the owner changed while copying: its policy name, before and after."""

    setting: Identifier
    before: str
    after: str


class LimitsChanged(EventPayloadValue):
    kind: Literal["limits_changed"] = "limits_changed"
    changes: tuple[LimitChange, ...] = Field(min_length=1)


class OwnershipIncidentOpened(EventPayloadValue):
    kind: Literal["ownership_incident_opened"] = "ownership_incident_opened"
    incident: OwnershipIncident


class OwnershipResolved(EventPayloadValue):
    kind: Literal["ownership_resolved"] = "ownership_resolved"
    resolution: OwnershipResolution


class SignalRejected(EventPayloadValue):
    kind: Literal["signal_rejected"] = "signal_rejected"
    payload_hash: str = Field(pattern=r"^[0-9a-f]{64}$")
    reason: Identifier


class Message(EventPayloadValue):
    kind: Literal["message"] = "message"
    message_id: Identifier
    status: MessageStatus
    parser_decision: Literal["trade", "ignore", "review"]
    parser_reason: Identifier
    parser_profile: str
    instructions: tuple[Instruction, ...]
    destination: DestinationTerms


class CashAnchorRecorded(EventPayloadValue):
    kind: Literal["cash_anchor_recorded"] = "cash_anchor_recorded"
    anchor: CashAnchor


class Skipped(EventPayloadValue):
    kind: Literal["skipped"] = "skipped"
    message_id: Identifier
    part: int = Field(ge=0)
    reason: Identifier
    exposure: tuple[Exposure, ...] | None
    bought_at: AwareDatetime | None = None


class SellWaiting(EventPayloadValue):
    """A sell that has no price to sell at yet: it waits, and asks again later."""

    kind: Literal["sell_waiting"] = "sell_waiting"
    message_id: Identifier
    part: int = Field(ge=0)
    reason: SellWait


class CryptoFeeCounted(EventPayloadValue):
    """Alpaca's fee on a coin's buys, counted from the coin it holds: the coin the account never
    received comes out of the buys' lot (ADR-0014)."""

    kind: Literal["crypto_fee_counted"] = "crypto_fee_counted"
    symbol: Identifier
    # Each buy's fee, by its order, for the fill counted now.
    fees: dict[Identifier, Quantity]
    # The coin those buys filled since their fee was last counted.
    filled_qty: Positive


class ReadBackSummary(EventPayloadValue):
    """What came of the posts read back after CopyTrading was off, told to the owner once."""

    kind: Literal["read_back_summary"] = "read_back_summary"
    posts: int = Field(ge=1)
    sells_copied: int = Field(ge=0)
    buys_too_old: int = Field(ge=0)


class MessageDone(EventPayloadValue):
    kind: Literal["message_done"] = "message_done"
    message_id: Identifier


class OrderPrepared(EventPayloadValue):
    kind: Literal["order_prepared"] = "order_prepared"
    client_id: Identifier
    message_id: Identifier
    symbol: Identifier
    side: Side
    position_intent: Literal["buy_to_open", "sell_to_close"]
    source_price: Positive
    entry_price: Positive
    qty: Positive
    type: Literal["market", "limit"]
    limit_price: Positive | None
    entry_tolerance_pct: Quantity
    session: Session


class SubmitStarted(EventPayloadValue):
    kind: Literal["submit_started"] = "submit_started"
    client_id: Identifier
    message_id: Identifier
    submit_started_at: AwareDatetime


class SubmissionAborted(EventPayloadValue):
    kind: Literal["submission_aborted"] = "submission_aborted"
    client_id: Identifier
    message_id: Identifier
    reason: Identifier


class SendAborted(EventPayloadValue):
    """A copied sell stopped before it reached Alpaca (CopyTrading stopping, or the session
    changing): its call waits again, and its next attempt goes out under a new client ID."""

    kind: Literal["send_aborted"] = "send_aborted"
    client_id: Identifier
    message_id: Identifier
    part: int = Field(ge=0)
    reason: Identifier


class SubmissionUncertain(EventPayloadValue):
    kind: Literal["submission_uncertain"] = "submission_uncertain"
    client_id: Identifier
    message_id: Identifier


class BrokerAcknowledged(EventPayloadValue):
    kind: Literal["broker_acknowledged"] = "broker_acknowledged"
    client_id: Identifier
    message_id: Identifier


class CancelRequested(EventPayloadValue):
    kind: Literal["cancel_requested"] = "cancel_requested"
    client_id: Identifier
    message_id: Identifier
    # None for orders cancelled before the reason was recorded.
    reason: CancelReason | None = None


class QuoteUnavailable(EventPayloadValue):
    kind: Literal["quote_unavailable"] = "quote_unavailable"
    client_id: Identifier
    message_id: Identifier


class SubmitError(EventPayloadValue):
    kind: Literal["submit_error"] = "submit_error"
    client_id: Identifier
    message_id: Identifier
    status: OrderStatus
    http_status: int | None


class SubmissionQuote(EventPayloadValue):
    kind: Literal["submission_quote"] = "submission_quote"
    client_id: Identifier
    message_id: Identifier
    quote: Quote


class ManualSaleRecorded(EventPayloadValue):
    kind: Literal["manual_sale_recorded"] = "manual_sale_recorded"
    sale: ManualSale
    previous_remaining_qty: Quantity | None = None
    remaining_qty: Quantity | None = None
    ownership_incident: OwnershipIncident | None = None


class ManualCorrectionRecorded(EventPayloadValue):
    kind: Literal["manual_correction_recorded"] = "manual_correction_recorded"
    correction: ManualCorrectionRecord


class ManualOrderPreviewed(EventPayloadValue):
    kind: Literal["manual_order_previewed"] = "manual_order_previewed"
    preview: ManualOrderPreview


class ManualCommandRejected(EventPayloadValue):
    kind: Literal["manual_command_rejected"] = "manual_command_rejected"
    command: ManualCommandRecord


class ManualCommandPrepared(EventPayloadValue):
    kind: Literal["manual_command_prepared"] = "manual_command_prepared"
    command: ManualCommandRecord
    plan: OrderPlan


class LotSalePreviewed(EventPayloadValue):
    kind: Literal["lot_sale_previewed"] = "lot_sale_previewed"
    preview: LotSalePreview


class LotSaleRejected(EventPayloadValue):
    kind: Literal["lot_sale_rejected"] = "lot_sale_rejected"
    sale: LotSaleRecord


class LotSalePrepared(EventPayloadValue):
    kind: Literal["lot_sale_prepared"] = "lot_sale_prepared"
    sale: LotSaleRecord
    plan: OrderPlan


class OrderIntentReleased(EventPayloadValue):
    kind: Literal["order_intent_released"] = "order_intent_released"
    client_id: Identifier
    message_id: Identifier
    previous_status: Literal["uncertain"]
    status: Literal["released_unsubmitted"]
    evidence: ReleaseEvidence
    entry_halted: bool


class LateOrderIncidentCleared(EventPayloadValue):
    kind: Literal["late_order_incident_cleared"] = "late_order_incident_cleared"
    client_id: Identifier
    message_id: Identifier
    broker_id: Identifier
    order_symbol: Identifier
    evidence: IncidentClearanceEvidence
    entry_halted: bool


class OrderUpdate(EventPayloadValue):
    kind: Literal["order_update"] = "order_update"
    client_id: Identifier
    message_id: Identifier
    status: OrderStatus
    raw_broker_status: Identifier
    filled_qty: Quantity
    filled_avg_price: Positive | None
    applied_fill_qty: Quantity | None
    unapplied_fill_qty: Quantity | None
    late_order_incident_ids: tuple[Identifier, ...] | None
    entry_halted: bool
    late_order_incident: LateOrderIncident | None


class LateOrderIncidentOpened(EventPayloadValue):
    kind: Literal["late_order_incident_opened"] = "late_order_incident_opened"
    client_id: Identifier
    message_id: Identifier
    status: OrderStatus
    raw_broker_status: Identifier
    filled_qty: Quantity
    filled_avg_price: Positive | None
    applied_fill_qty: Quantity | None
    unapplied_fill_qty: Quantity | None
    late_order_incident_ids: tuple[Identifier, ...] | None
    entry_halted: bool
    late_order_incident: LateOrderIncident


class LateOrderIncidentReopened(EventPayloadValue):
    kind: Literal["late_order_incident_reopened"] = "late_order_incident_reopened"
    client_id: Identifier
    message_id: Identifier
    status: OrderStatus
    raw_broker_status: Identifier
    filled_qty: Quantity
    filled_avg_price: Positive | None
    applied_fill_qty: Quantity | None
    unapplied_fill_qty: Quantity | None
    late_order_incident_ids: tuple[Identifier, ...] | None
    entry_halted: bool
    late_order_incident: LateOrderIncident


type EventPayload = Annotated[
    AccountBound
    | AccountInventoried
    | AccountControlChanged
    | LimitsChanged
    | OwnershipIncidentOpened
    | OwnershipResolved
    | SignalRejected
    | Message
    | CashAnchorRecorded
    | Skipped
    | SellWaiting
    | CryptoFeeCounted
    | ReadBackSummary
    | MessageDone
    | OrderPrepared
    | SubmitStarted
    | SubmissionAborted
    | SendAborted
    | SubmissionUncertain
    | BrokerAcknowledged
    | CancelRequested
    | QuoteUnavailable
    | SubmitError
    | SubmissionQuote
    | ManualSaleRecorded
    | ManualCorrectionRecorded
    | ManualOrderPreviewed
    | ManualCommandRejected
    | ManualCommandPrepared
    | LotSalePreviewed
    | LotSaleRejected
    | LotSalePrepared
    | OrderIntentReleased
    | LateOrderIncidentCleared
    | OrderUpdate
    | LateOrderIncidentOpened
    | LateOrderIncidentReopened,
    Field(discriminator="kind"),
]


class JournalEvent(Value):
    at: AwareDatetime
    payload: EventPayload
