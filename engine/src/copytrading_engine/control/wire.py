"""The versioned request and response contract shared by the CLI, the MCP server and the engine.

These models are the public face of agent control. They are deliberately separate from the
engine's internal views, never carry credentials, tokens or broker account identifiers, and
name Discord text `untrusted_source_text` so no consumer mistakes it for instructions.
"""

from decimal import Decimal
from typing import Annotated, Any, Final, Literal, Self

from pydantic import AwareDatetime, BaseModel, ConfigDict, Field, TypeAdapter, model_validator

SCHEMA_VERSION: Final = 1
MAX_LINE_BYTES: Final = 64 * 1024


class Wire(BaseModel):
    model_config = ConfigDict(frozen=True, extra="forbid", strict=True, hide_input_in_errors=True)


AccountId = Annotated[str, Field(min_length=1, max_length=64)]
Identifier = Annotated[str, Field(min_length=1, max_length=256)]
RequestId = Annotated[str, Field(min_length=1, max_length=128)]
ProposalId = Annotated[str, Field(pattern=r"^p-[0-9a-f]{12}$")]
Digest = Annotated[str, Field(pattern=r"^[0-9a-f]{64}$")]
Limit = Annotated[int, Field(ge=1, le=100)]
Sequence = Annotated[int, Field(ge=1)]
RecoveryPreference = Literal["manual", "automatic"]

type Operation = Literal[
    "get_status",
    "list_accounts",
    "list_activity",
    "list_account_events",
    "list_manual_commands",
    "get_manual_command",
    "preview_manual_order",
    "list_proposals",
    "get_proposal",
    "pause_processing",
    "pause_account",
    "propose_resume_account",
    "propose_recovery_preference",
    "propose_manual_order",
]

type ErrorCode = Literal[
    "access_off",
    "locked",
    "forbidden",
    "invalid_request",
    "not_found",
    "unavailable",
    "busy",
    "cooling_down",
    "proposal_limit",
    "conflict",
    "expired",
    "rejected",
]


# Requests


class RequestHeader(Wire):
    schema_version: Literal[1] = 1
    request_id: RequestId


class GetStatus(RequestHeader):
    operation: Literal["get_status"] = "get_status"


class ListAccounts(RequestHeader):
    operation: Literal["list_accounts"] = "list_accounts"
    before_account_id: AccountId | None = None
    limit: Limit = 50


class ListActivity(RequestHeader):
    operation: Literal["list_activity"] = "list_activity"
    before_seq: Sequence | None = None
    limit: Limit = 50


class ListAccountEvents(RequestHeader):
    operation: Literal["list_account_events"] = "list_account_events"
    account_id: AccountId
    before_seq: Sequence | None = None
    limit: Limit = 50


class ListManualCommands(RequestHeader):
    operation: Literal["list_manual_commands"] = "list_manual_commands"
    account_id: AccountId
    source_id: Identifier
    before_command_id: Identifier | None = None
    limit: Limit = 50


class GetManualCommand(RequestHeader):
    operation: Literal["get_manual_command"] = "get_manual_command"
    account_id: AccountId
    command_id: Identifier


class PreviewManualOrder(RequestHeader):
    operation: Literal["preview_manual_order"] = "preview_manual_order"
    account_id: AccountId
    correction_id: Identifier
    instruction_index: Annotated[int, Field(ge=0)]


class ListProposals(RequestHeader):
    operation: Literal["list_proposals"] = "list_proposals"


class GetProposal(RequestHeader):
    operation: Literal["get_proposal"] = "get_proposal"
    proposal_id: ProposalId


class PauseProcessing(RequestHeader):
    operation: Literal["pause_processing"] = "pause_processing"


class PauseAccount(RequestHeader):
    operation: Literal["pause_account"] = "pause_account"
    account_id: AccountId


class ProposeResumeAccount(RequestHeader):
    operation: Literal["propose_resume_account"] = "propose_resume_account"
    account_id: AccountId


class ProposeRecoveryPreference(RequestHeader):
    operation: Literal["propose_recovery_preference"] = "propose_recovery_preference"
    account_id: AccountId
    preference: RecoveryPreference


class ProposeManualOrder(RequestHeader):
    operation: Literal["propose_manual_order"] = "propose_manual_order"
    account_id: AccountId
    preview_id: Identifier


type Request = Annotated[
    GetStatus
    | ListAccounts
    | ListActivity
    | ListAccountEvents
    | ListManualCommands
    | GetManualCommand
    | PreviewManualOrder
    | ListProposals
    | GetProposal
    | PauseProcessing
    | PauseAccount
    | ProposeResumeAccount
    | ProposeRecoveryPreference
    | ProposeManualOrder,
    Field(discriminator="operation"),
]
REQUEST: Final = TypeAdapter[Request](Request)


# Results


class ProcessingView(Wire):
    state: str
    source_connected: bool
    model_ready: bool
    pending_source: int
    pending_signals: int
    processed_signals: int
    error_code: str | None


class AccountStateView(Wire):
    account_id: str
    run_state: str
    entry_permission: str
    recovery_preference: str
    readiness: str
    risk_status: str
    activity_status: str
    error_code: str | None


class StatusView(Wire):
    type: Literal["status"] = "status"
    engine_state: str
    processing: ProcessingView
    accounts: tuple[AccountStateView, ...]


class LotView(Wire):
    """One block of shares the copier bought, and the post that bought it."""

    lot_id: str
    source_id: str | None
    guru_id: str | None
    posted_at: AwareDatetime | None
    untrusted_source_text: str | None
    bought_at: AwareDatetime | None
    original_qty: Decimal
    remaining_qty: Decimal
    average_price: Decimal


class PositionView(Wire):
    symbol: str
    owned_qty: Decimal
    external_qty: Decimal
    lots: tuple[LotView, ...]


class UnavailableAccountView(Wire):
    account_id: str
    reason: str


class BalanceView(Wire):
    equity: Decimal
    day_change_usd: Decimal
    cash: Decimal
    buying_power: Decimal
    observed_at: AwareDatetime


class AccountView(Wire):
    account_id: str
    environment: Literal["paper", "live"]
    entry_permission: str
    recovery_preference: str
    readiness: str
    risk_status: str
    risk_reason: str | None
    activity_status: str
    activity_reason: str | None
    total_exposure_usd: Decimal | None
    positions: tuple[PositionView, ...]
    ownership_incidents: int
    pending_orders: int | None
    balance: BalanceView | None


class AccountsPage(Wire):
    type: Literal["accounts"] = "accounts"
    items: tuple[AccountView, ...]
    next_before_account_id: str | None
    unavailable: tuple[UnavailableAccountView, ...]


class OrderView(Wire):
    client_id: str
    symbol: str
    side: str
    status: str
    quantity: Decimal
    filled_quantity: Decimal
    average_fill_price: Decimal | None


class DestinationView(Wire):
    account_id: str
    environment: str
    status: str
    instruction_outcomes: tuple[str, ...]
    orders: tuple[OrderView, ...]


class InstructionItem(Wire):
    action: Literal["buy", "reduce", "close"]
    symbol: str
    # None for a sell at the market (ADR-0007).
    price: Decimal | None
    fraction: Decimal | None


class ActivityItem(Wire):
    sequence: int
    source_id: str
    source_at: AwareDatetime
    captured_at: AwareDatetime
    parse_status: str
    delivery_status: str
    decision: str | None
    parser_reason: str | None
    guru_id: str | None
    untrusted_source_text: str
    understood_as: tuple[InstructionItem, ...]
    destinations: tuple[DestinationView, ...]


class RejectedActivityItem(Wire):
    source_id: str
    rejected_at: AwareDatetime
    reason: str


class ActivityPage(Wire):
    type: Literal["activity"] = "activity"
    items: tuple[ActivityItem, ...]
    rejected: tuple[RejectedActivityItem, ...]
    next_before_seq: int | None
    unavailable: tuple[UnavailableAccountView, ...]


class AccountEventView(Wire):
    sequence: int
    at: AwareDatetime
    kind: str
    message_id: str | None
    order_id: str | None
    reason: str | None
    status: str | None


class AccountEventsPage(Wire):
    type: Literal["account_events"] = "account_events"
    account_id: str
    items: tuple[AccountEventView, ...]
    next_before_seq: int | None


class ManualCommandView(Wire):
    command_id: str
    account_id: str
    source_id: str
    correction_id: str
    instruction_index: int
    actor: str
    confirmed_at: AwareDatetime
    status: str
    reason: str | None
    client_id: str | None


class ManualCommand(Wire):
    type: Literal["manual_command"] = "manual_command"
    command: ManualCommandView


class ManualCommandsPage(Wire):
    type: Literal["manual_commands"] = "manual_commands"
    account_id: str
    source_id: str
    items: tuple[ManualCommandView, ...]
    next_before_command_id: str | None


class InstructionView(Wire):
    action: Literal["buy", "reduce", "close"]
    symbol: str
    # None for a sell at the market (ADR-0007).
    price: Decimal | None
    entry_price: Decimal | None
    fraction: Decimal | None


class OrderPlanView(Wire):
    side: Literal["buy", "sell"]
    type: Literal["limit", "market"]
    quantity: Decimal
    limit_price: Decimal | None
    session: str


class CheckView(Wire):
    name: str
    status: Literal["passed", "warning", "blocked"]
    reason: str | None


class ManualPreview(Wire):
    type: Literal["manual_preview"] = "manual_preview"
    preview_id: str
    account_id: str
    environment: Literal["paper", "live"]
    source_age_seconds: int
    created_at: AwareDatetime
    expires_at: AwareDatetime
    instruction: InstructionView
    fresh_price: Decimal | None
    plan: OrderPlanView | None
    checks: tuple[CheckView, ...]
    reasons: tuple[str, ...]


class ResumeAccountSubject(Wire):
    kind: Literal["resume_account"] = "resume_account"
    account_id: str


class RecoverySubject(Wire):
    kind: Literal["set_recovery"] = "set_recovery"
    account_id: str
    preference: RecoveryPreference


class ManualOrderSubject(Wire):
    kind: Literal["confirm_manual_order"] = "confirm_manual_order"
    account_id: str
    preview_id: str
    environment: Literal["paper", "live"]
    symbol: str
    side: Literal["buy", "sell"]
    order_type: Literal["limit", "market"]
    quantity: Decimal
    limit_price: Decimal | None


type ProposalSubject = Annotated[
    ResumeAccountSubject | RecoverySubject | ManualOrderSubject,
    Field(discriminator="kind"),
]


class CallerView(Wire):
    pid: int | None
    path: str | None


class ProposalOutcome(Wire):
    status: Literal["succeeded", "failed", "outcome_unknown"]
    code: str | None
    command_id: str


class ProposalView(Wire):
    type: Literal["proposal"] = "proposal"
    proposal_id: str
    state: Literal[
        "pending",
        "running",
        "succeeded",
        "failed",
        "outcome_unknown",
        "rejected",
        "expired",
        "discarded",
    ]
    subject: ProposalSubject
    digest: Digest
    command_id: str
    created_at: AwareDatetime
    expires_at: AwareDatetime
    requested_by: CallerView
    outcome: ProposalOutcome | None


class ProposalsPage(Wire):
    type: Literal["proposals"] = "proposals"
    items: tuple[ProposalView, ...]


class ProcessingPaused(Wire):
    type: Literal["processing"] = "processing"
    processing: ProcessingView


class AccountControlView(Wire):
    type: Literal["account_control"] = "account_control"
    account_id: str
    entry_permission: str
    recovery_preference: str
    applied_at: AwareDatetime


type Result = Annotated[
    StatusView
    | AccountsPage
    | ActivityPage
    | AccountEventsPage
    | ManualCommandsPage
    | ManualCommand
    | ManualPreview
    | ProposalView
    | ProposalsPage
    | ProcessingPaused
    | AccountControlView,
    Field(discriminator="type"),
]


class ErrorBody(Wire):
    code: ErrorCode
    message: str


class Response(Wire):
    schema_version: Literal[1] = 1
    request_id: str
    ok: Result | None = None
    error: ErrorBody | None = None

    @model_validator(mode="after")
    def one_outcome(self) -> Self:
        if (self.ok is None) == (self.error is None):
            raise ValueError("A response carries exactly one of ok or error")
        return self


def json_schema() -> dict[str, Any]:
    """The published contract: every request a client may send and every response it may get."""
    return {
        "schema_version": SCHEMA_VERSION,
        "request": REQUEST.json_schema(),
        "response": Response.model_json_schema(),
    }
