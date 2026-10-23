"""The versioned request and response contract shared by the CLI, the MCP server and the engine.

These models are the public face of agent control. They are deliberately separate from the
engine's internal views, never carry credentials, tokens or broker account identifiers, and
name Discord text `untrusted_source_text` so no consumer mistakes it for instructions.
"""

from decimal import Decimal
from typing import Annotated, Any, Final, Literal, Self

from pydantic import (
    AwareDatetime,
    BaseModel,
    ConfigDict,
    Field,
    PlainSerializer,
    SecretStr,
    TypeAdapter,
    model_validator,
)

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
CopyingWord = Literal["copying", "sells_only", "paused", "stopped", "not_started"]
# The five words the owner sees for copying, as the app says them (`control.copying` picks one).
COPYING_WORDS: Final[dict[CopyingWord, str]] = {
    "copying": "Copying",
    "sells_only": "Sells only",
    "paused": "Paused",
    "stopped": "Stopped",
    "not_started": "Not started",
}

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
    "propose_set_account_limits",
    "propose_start_processing",
    "get_setup",
    "edit_setup_discord",
    "edit_setup_model",
    "edit_setup_account",
    "edit_setup_guru",
    "edit_setup_alerts",
    "import_setup",
    "apply_setup",
    "discard_setup",
]

# The setup operations the app answers itself: their keys go to the Keychain, never the engine.
type SetupOperation = Literal[
    "get_setup",
    "edit_setup_discord",
    "edit_setup_model",
    "edit_setup_account",
    "edit_setup_guru",
    "edit_setup_alerts",
    "import_setup",
    "apply_setup",
    "discard_setup",
]
SETUP_OPERATIONS: Final[frozenset[str]] = frozenset(
    (
        "get_setup",
        "edit_setup_discord",
        "edit_setup_model",
        "edit_setup_account",
        "edit_setup_guru",
        "edit_setup_alerts",
        "import_setup",
        "apply_setup",
        "discard_setup",
    )
)

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


LIMIT_FIELDS: Final = (
    "max_order_usd",
    "max_symbol_usd",
    "max_total_usd",
    "daily_loss_cap_usd",
    "max_entries_per_day",
    "max_signal_age_seconds",
    "order_timeout_seconds",
    "poll_seconds",
    "extended_hours",
    "overnight",
    "copy_exits",
    "approve_orders",
    "max_above_signal_pct",
    "max_below_signal_pct",
)
type LimitField = Literal[
    "max_order_usd",
    "max_symbol_usd",
    "max_total_usd",
    "daily_loss_cap_usd",
    "max_entries_per_day",
    "max_signal_age_seconds",
    "order_timeout_seconds",
    "poll_seconds",
    "extended_hours",
    "overnight",
    "copy_exits",
    "approve_orders",
    "max_above_signal_pct",
    "max_below_signal_pct",
]


class LimitChange(Wire):
    """One account setting and the value it is to take, as the text a person would type."""

    field: LimitField
    value: Annotated[str, Field(min_length=1, max_length=32)]


class ProposeSetAccountLimits(RequestHeader):
    operation: Literal["propose_set_account_limits"] = "propose_set_account_limits"
    account_id: AccountId
    changes: Annotated[tuple[LimitChange, ...], Field(min_length=1, max_length=len(LIMIT_FIELDS))]


class ProposeStartProcessing(RequestHeader):
    """Start copying the saved setup, as the app's Start Copying does; the owner approves."""

    operation: Literal["propose_start_processing"] = "propose_start_processing"


class ProposeManualOrder(RequestHeader):
    operation: Literal["propose_manual_order"] = "propose_manual_order"
    account_id: AccountId
    preview_id: Identifier


# Setup: the CLI edits the app's own draft, the same one Connections edits, then applies it.


def _reveal(value: SecretStr) -> str:
    return value.get_secret_value()


# A key, token or secret. It travels only in a request line to the app, which saves it in the
# Keychain; its repr, errors and Python dumps are masked, and no response ever carries one.
Secret = Annotated[
    SecretStr,
    Field(min_length=1, max_length=4096),
    PlainSerializer(_reveal, return_type=str, when_used="json"),
]
# Discord channel, user and webhook-free identifiers are decimal strings (snowflakes).
DiscordId = Annotated[str, Field(pattern=r"^[0-9]{1,32}$")]
AccountName = Annotated[str, Field(pattern=r"^[A-Za-z0-9_-]{1,64}$")]
GuruRef = Annotated[str, Field(min_length=1, max_length=100)]
Environment = Literal["paper", "live"]
type ModelService = Literal[
    "anthropic",
    "openai",
    "google",
    "deepseek",
    "openrouter",
    "groq",
    "xai",
    "mistral",
    "together",
    "fireworks",
    "cerebras",
    "moonshotai",
    "ollama",
    "openai_compatible",
]
AlertService = Literal["telegram", "discord"]
PLAYBOOK_MAX_LENGTH: Final = 8_000
IMPORT_MAX_LENGTH: Final = 60_000
REPEAT_WINDOW_MAX_MINUTES: Final = 1440


def _require_a_change(model: BaseModel, fields: tuple[str, ...]) -> None:
    if all(getattr(model, name) is None for name in fields):
        raise ValueError("Name at least one thing to change")


class GetSetup(RequestHeader):
    """The setup as Connections shows it: saved values plus unsaved edits, keys as saved or not."""

    operation: Literal["get_setup"] = "get_setup"


class EditSetupDiscord(RequestHeader):
    operation: Literal["edit_setup_discord"] = "edit_setup_discord"
    channel_ids: Annotated[tuple[DiscordId, ...], Field(min_length=1, max_length=50)] | None = None
    # An empty list copies every author in the channels.
    author_ids: Annotated[tuple[DiscordId, ...], Field(max_length=50)] | None = None
    token: Secret | None = None

    @model_validator(mode="after")
    def changes_something(self) -> Self:
        _require_a_change(self, ("channel_ids", "author_ids", "token"))
        return self


class EditSetupModel(RequestHeader):
    operation: Literal["edit_setup_model"] = "edit_setup_model"
    service: ModelService | None = None
    model: Annotated[str, Field(min_length=1, max_length=200)] | None = None
    # Only for ollama and openai_compatible; an empty string clears it.
    base_url: Annotated[str, Field(max_length=2048)] | None = None
    key: Secret | None = None

    @model_validator(mode="after")
    def changes_something(self) -> Self:
        _require_a_change(self, ("service", "model", "base_url", "key"))
        return self


class EditSetupAccount(RequestHeader):
    operation: Literal["edit_setup_account"] = "edit_setup_account"
    action: Literal["add", "edit", "remove"]
    account_id: AccountName
    rename: AccountName | None = None
    environment: Environment | None = None
    # The Alpaca API key ID and its secret, always together.
    key: Secret | None = None
    secret: Secret | None = None
    limits: Annotated[tuple[LimitChange, ...], Field(max_length=len(LIMIT_FIELDS))] = ()
    # What the account does after a restart: wait for the owner (manual), or carry on by itself.
    recovery_preference: RecoveryPreference | None = None

    @model_validator(mode="after")
    def consistent(self) -> Self:
        if (self.key is None) != (self.secret is None):
            raise ValueError("Give the Alpaca key and its secret together")
        if len({change.field for change in self.limits}) != len(self.limits):
            raise ValueError("A setting is named twice")
        changes = (
            self.rename,
            self.environment,
            self.key,
            self.recovery_preference,
        ) != (None, None, None, None) or self.limits
        if self.action == "remove" and changes:
            raise ValueError("Removing an account takes only its name")
        if self.action == "add" and self.rename is not None:
            raise ValueError("A new account is named once")
        if self.action == "edit" and not changes:
            raise ValueError("Name at least one thing to change")
        return self


class EditSetupGuru(RequestHeader):
    operation: Literal["edit_setup_guru"] = "edit_setup_guru"
    action: Literal["add", "edit", "remove"]
    # The guru's name, or its ID; for add, the new guru's name.
    guru: GuruRef
    rename: GuruRef | None = None
    # An empty string follows the first source channel.
    channel_id: DiscordId | Literal[""] | None = None
    # An empty string copies every author in the channel.
    author_id: DiscordId | Literal[""] | None = None
    account_id: AccountName | None = None
    # The guru's own full position in their account: a 1/6 call buys a sixth of it (ADR-0010).
    full_position_usd: Annotated[str, Field(min_length=1, max_length=32)] | None = None
    playbook: Annotated[str, Field(max_length=PLAYBOOK_MAX_LENGTH)] | None = None
    # Minutes within which the same call again is a re-post; 0 copies every post.
    repeat_window_minutes: Annotated[int, Field(ge=0, le=REPEAT_WINDOW_MAX_MINUTES)] | None = None

    @model_validator(mode="after")
    def consistent(self) -> Self:
        fields = (
            "rename",
            "channel_id",
            "author_id",
            "account_id",
            "full_position_usd",
            "playbook",
            "repeat_window_minutes",
        )
        changes = any(getattr(self, name) is not None for name in fields)
        if self.action == "remove" and changes:
            raise ValueError("Removing a guru takes only their name")
        if self.action == "add" and self.rename is not None:
            raise ValueError("A new guru is named once")
        if self.action == "edit" and not changes:
            raise ValueError("Name at least one thing to change")
        return self


class EditSetupAlerts(RequestHeader):
    operation: Literal["edit_setup_alerts"] = "edit_setup_alerts"
    enabled: bool | None = None
    service: AlertService | None = None
    # Telegram's chat; a Discord webhook names its own channel.
    chat_id: Annotated[str, Field(max_length=64)] | None = None
    # Telegram's bot token, or the Discord webhook URL.
    token: Secret | None = None

    @model_validator(mode="after")
    def changes_something(self) -> Self:
        _require_a_change(self, ("enabled", "service", "chat_id", "token"))
        return self


class ImportSetup(RequestHeader):
    """A setup file's text, read the way the app's Import Setup reads it."""

    operation: Literal["import_setup"] = "import_setup"
    text: Annotated[
        SecretStr,
        Field(min_length=1, max_length=IMPORT_MAX_LENGTH),
        PlainSerializer(_reveal, return_type=str, when_used="json"),
    ]


class ApplySetup(RequestHeader):
    """Check every connection, then save. Copying that runs starts again with the new setup;
    copying that is paused stays paused unless `start` asks to start it, as Start Copying does."""

    operation: Literal["apply_setup"] = "apply_setup"
    start: bool = False


class DiscardSetup(RequestHeader):
    """Drop the unsaved edits, as Connections' Discard does."""

    operation: Literal["discard_setup"] = "discard_setup"


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
    | ProposeManualOrder
    | ProposeSetAccountLimits
    | ProposeStartProcessing
    | GetSetup
    | EditSetupDiscord
    | EditSetupModel
    | EditSetupAccount
    | EditSetupGuru
    | EditSetupAlerts
    | ImportSetup
    | ApplySetup
    | DiscardSetup,
    Field(discriminator="operation"),
]
REQUEST: Final = TypeAdapter[Request](Request)


# Results


class ProcessingView(Wire):
    state: str
    # One of the five words the owner sees, and the code for the line under it.
    copying: CopyingWord
    copying_detail: str | None
    source_connected: bool
    model_ready: bool
    pending_source: int
    pending_signals: int
    processed_signals: int
    error_code: str | None


class AccountStateView(Wire):
    account_id: str
    copying: CopyingWord
    copying_detail: str | None
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
    copying: CopyingWord
    copying_detail: str | None
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
    # A buy the post sizes in dollars ("$200 of NFLX").
    usd_amount: Decimal | None


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


class LimitsSubject(Wire):
    kind: Literal["set_account_limits"] = "set_account_limits"
    account_id: str
    changes: tuple[LimitChange, ...]


class StartProcessingSubject(Wire):
    kind: Literal["start_processing"] = "start_processing"


class ApplySetupSubject(Wire):
    """Applying the setup touches real money: what in it does, by account."""

    kind: Literal["apply_setup"] = "apply_setup"
    # Accounts the setup makes live, new or switched from paper.
    made_live: tuple[str, ...]
    # Live accounts with new Alpaca keys to save.
    new_live_keys: tuple[str, ...]
    # Live accounts whose limits or switches change.
    changed_live: tuple[str, ...]
    # Live accounts copying starts again with.
    starts_live: tuple[str, ...]


type ProposalSubject = Annotated[
    ResumeAccountSubject
    | RecoverySubject
    | ManualOrderSubject
    | LimitsSubject
    | StartProcessingSubject
    | ApplySetupSubject,
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


# Setup results. Keys are only ever "saved", "missing", "entered" (typed, not saved yet), or
# "not_needed" (a model on the owner's own machine).
type KeyState = Literal["saved", "missing", "entered", "not_needed"]


class SetupCheckView(Wire):
    """A connection's latest check, as its row in Connections reads."""

    connection: Literal["discord", "model", "account", "alerts", "setup"]
    subject: str | None = None
    state: Literal["passed", "failed", "not_configured"]
    reason: str | None = None
    # What happened and what to do, in the app's words; set when the check failed.
    message: str | None = None


class SetupDiscordView(Wire):
    channel_ids: tuple[str, ...]
    author_ids: tuple[str, ...]
    token: KeyState
    check: SetupCheckView | None = None


class SetupModelView(Wire):
    service: str
    model: str
    base_url: str | None = None
    key: KeyState
    check: SetupCheckView | None = None


class SetupAccountView(Wire):
    account_id: str
    environment: Environment
    keys: KeyState
    limits: tuple[LimitChange, ...]
    recovery_preference: RecoveryPreference
    check: SetupCheckView | None = None


class SetupGuruView(Wire):
    # The ID the guru's channel gives them (`route_keys.guru_for_channel`); None until they have
    # a channel.
    guru_id: str | None = None
    name: str
    # The channel the guru is read from; the first source channel when they name none.
    channel_id: str | None = None
    author_id: str | None = None
    account_id: str | None = None
    full_position_usd: str | None = None
    repeat_window_minutes: int | None = None
    playbook_characters: int


class SetupAlertsView(Wire):
    enabled: bool
    service: AlertService
    chat_id: str | None = None
    token: KeyState
    check: SetupCheckView | None = None


class SetupView(Wire):
    type: Literal["setup"] = "setup"
    # A setup has been checked, saved and started at least once.
    saved: bool
    # The draft differs from what is saved; `setup apply` checks and saves it.
    unsaved_changes: bool
    # One of the five words the owner sees for copying (`COPYING_WORDS`).
    copying: CopyingWord
    discord: SetupDiscordView
    model: SetupModelView
    accounts: tuple[SetupAccountView, ...]
    gurus: tuple[SetupGuruView, ...]
    alerts: SetupAlertsView


class SetupImported(Wire):
    type: Literal["setup_imported"] = "setup_imported"
    # What the file filled and what the setup still needs, by name; never a value.
    filled: tuple[str, ...]
    missing: tuple[str, ...]
    setup: SetupView


class SetupApplied(Wire):
    type: Literal["setup_applied"] = "setup_applied"
    # applied: checked, saved, and copying uses it; unchanged: nothing to apply; failed_checks:
    # a connection needs attention and nothing was saved; failed: it did not start (see message).
    status: Literal["applied", "unchanged", "failed_checks", "failed"]
    message: str | None = None
    checks: tuple[SetupCheckView, ...] = ()


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
    | AccountControlView
    | SetupView
    | SetupImported
    | SetupApplied,
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
