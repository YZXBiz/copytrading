"""The engine pipe's request contract: one model per operation the app may send."""

from collections.abc import Awaitable, Callable
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, SecretStr, StrictInt, TypeAdapter

from copytrading_engine.assistant.service import AskContext
from copytrading_engine.control.service import ControlContext
from copytrading_engine.control.wire import MAX_LINE_BYTES as MAX_CONTROL_LINE_BYTES
from copytrading_engine.execution.domain.lifecycle import AccountControlCommand
from copytrading_engine.execution.domain.lot_sales import LotSaleConfirmation, LotSalePreviewRequest
from copytrading_engine.execution.domain.manual_commands import (
    ManualConfirmationRequest,
    ManualCorrectionRequest,
    ManualPreviewRequest,
)
from copytrading_engine.execution.domain.market import HistoryWindow
from copytrading_engine.execution.domain.ownership import OwnershipResolutionRequest
from copytrading_engine.execution.domain.sizing import RouteConnection
from copytrading_engine.trading.domain.config import (
    BrokerCheck,
    ModelCheck,
    NotificationCheck,
    ProviderConfiguration,
    SourceCheck,
    TradingConfiguration,
    TradingSecrets,
)
from copytrading_engine.trading.domain.profiles import ProfileRevision


class PipeRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    version: Literal[1]
    request_id: str = Field(min_length=1, max_length=128)


class SelfTestCommandBody(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    command_id: str = Field(min_length=1, max_length=128)
    text: str = Field(min_length=1)
    destination_ids: list[str] = Field(min_length=1, max_length=2)


class SubmitRequest(PipeRequest):
    operation: Literal["submit_self_test"]
    command: SelfTestCommandBody


class GetStatusRequest(PipeRequest):
    operation: Literal["get_status"]


class GetWorkflowRequest(PipeRequest):
    operation: Literal["get_workflow"]
    command_id: str = Field(min_length=1, max_length=128)


class StopRequest(PipeRequest):
    operation: Literal["stop"]


class GetTradingStatusRequest(PipeRequest):
    operation: Literal["get_trading_status"]


class GetTradingActivationRequest(PipeRequest):
    operation: Literal["get_trading_activation"]
    activation_id: str = Field(pattern=r"^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$")


class StartTradingRequest(PipeRequest):
    operation: Literal["start_trading"]
    configuration: TradingConfiguration
    secrets: TradingSecrets
    validation_token: str = Field(min_length=1, max_length=128)
    activation_id: str = Field(pattern=r"^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$")


class ValidateTradingRequest(PipeRequest):
    operation: Literal["validate_trading"]
    configuration: TradingConfiguration
    secrets: TradingSecrets


class CheckConnectionRequest(PipeRequest):
    """One service checked as the owner connects it; saves nothing and grants no start."""

    operation: Literal["check_connection"]
    connection: Annotated[
        SourceCheck | ModelCheck | BrokerCheck | NotificationCheck, Field(discriminator="kind")
    ]


class UpdateAccountLimitsRequest(PipeRequest):
    """The saved setup with changed account limits; copying takes them without a pause."""

    operation: Literal["update_account_limits"]
    configuration: TradingConfiguration


class PauseTradingRequest(PipeRequest):
    operation: Literal["pause_trading"]


class CreateBackupRequest(PipeRequest):
    operation: Literal["create_backup"]
    destination: str = Field(min_length=1, max_length=4096)


class PreviewRestoreRequest(PipeRequest):
    operation: Literal["preview_restore"]
    archive_path: str = Field(min_length=1, max_length=4096)


class PrepareRestoreCandidateRequest(PipeRequest):
    operation: Literal["prepare_restore_candidate"]
    staging_id: str = Field(pattern=r"^restore-[0-9a-f]{32}$")


class RestoreCandidateStatusRequest(PipeRequest):
    operation: Literal["restore_candidate_status"]


class AbortRestoreCandidateRequest(PipeRequest):
    operation: Literal["abort_restore_candidate"]
    candidate_id: str = Field(pattern=r"^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$")


class RestorePreflightAccount(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, hide_input_in_errors=True)

    account_id: str = Field(pattern=r"^[A-Za-z0-9_-]{1,64}$")
    environment: Literal["paper", "live"]
    key: SecretStr = Field(min_length=1, max_length=512)
    secret: SecretStr = Field(min_length=1, max_length=512)


class RestorePreflightRequest(PipeRequest):
    operation: Literal["restore_preflight"]
    candidate_id: str = Field(pattern=r"^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$")
    accounts: list[RestorePreflightAccount] = Field(min_length=0, max_length=64)


class CompleteRestoreCandidateRequest(PipeRequest):
    operation: Literal["complete_restore_candidate"]
    candidate_id: str = Field(pattern=r"^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$")
    completion_token: str = Field(pattern=r"^[0-9a-f]{32}$")


class ControlAccountRequest(PipeRequest):
    operation: Literal["control_account"]
    command: AccountControlCommand


class ResolveOwnershipRequest(PipeRequest):
    operation: Literal["resolve_ownership"]
    account_id: str = Field(min_length=1, max_length=64)
    resolution: OwnershipResolutionRequest


class GetAccountsRequest(PipeRequest):
    operation: Literal["get_accounts"]
    before_account_id: str | None = Field(default=None, min_length=1, max_length=64)
    limit: StrictInt = Field(default=50, ge=1, le=100)


class GetSourceActivityRequest(PipeRequest):
    operation: Literal["get_source_activity"]
    before_seq: StrictInt | None = Field(default=None, ge=1)
    limit: StrictInt = Field(default=50, ge=1, le=100)


class EvaluateHistoricalProfileRequest(PipeRequest):
    operation: Literal["evaluate_historical_profile"]
    source_id: str = Field(min_length=1, max_length=256)
    profile: ProfileRevision
    provider: ProviderConfiguration
    # Empty for a model on this Mac or a custom address; ProviderConfiguration.reader() decides.
    provider_api_key: SecretStr
    destinations: list[RouteConnection] = Field(min_length=1, max_length=20)


class ReviewProfileExamplesRequest(PipeRequest):
    operation: Literal["review_profile_examples"]
    profile: ProfileRevision
    provider: ProviderConfiguration
    # Empty for a model on this Mac or a custom address; ProviderConfiguration.reader() decides.
    provider_api_key: SecretStr
    destinations: list[RouteConnection] = Field(max_length=20)


class LearnGuruPlaybookRequest(PipeRequest):
    operation: Literal["learn_guru_playbook"]
    channel_id: str = Field(pattern=r"^[0-9]{1,32}$")
    author_id: str | None = Field(default=None, pattern=r"^[0-9]{1,32}$")
    discord_token: SecretStr = Field(min_length=1)
    provider: ProviderConfiguration
    # Empty for a model on this Mac or a custom address; ProviderConfiguration.reader() decides.
    provider_api_key: SecretStr


class ReplayGuruPostsRequest(PipeRequest):
    """Read a guru's recent posts with a draft profile, before switching them on (ADR-0007)."""

    operation: Literal["replay_guru_posts"]
    channel_id: str = Field(pattern=r"^[0-9]{1,32}$")
    author_id: str | None = Field(default=None, pattern=r"^[0-9]{1,32}$")
    discord_token: SecretStr = Field(min_length=1)
    provider: ProviderConfiguration
    provider_api_key: SecretStr
    profile: ProfileRevision
    # The guru's accounts, so each replayed buy says how much it would spend.
    destinations: list[RouteConnection] = Field(max_length=20)


class GetAccountEventsRequest(PipeRequest):
    operation: Literal["get_account_events"]
    account_id: str = Field(min_length=1, max_length=64)
    before_seq: StrictInt | None = Field(default=None, ge=1)
    limit: StrictInt = Field(default=50, ge=1, le=100)


class GetEquityHistoryRequest(PipeRequest):
    operation: Literal["get_equity_history"]
    account_id: str = Field(min_length=1, max_length=64)
    window: HistoryWindow


class SaveManualCorrectionRequest(PipeRequest):
    operation: Literal["save_manual_correction"]
    correction: ManualCorrectionRequest


class PreviewManualOrderRequest(PipeRequest):
    operation: Literal["preview_manual_order"]
    preview: ManualPreviewRequest


class PreviewLotSaleRequest(PipeRequest):
    operation: Literal["preview_lot_sale"]
    preview: LotSalePreviewRequest


class ConfirmLotSaleRequest(PipeRequest):
    operation: Literal["confirm_lot_sale"]
    sale: LotSaleConfirmation


class ConfirmManualOrdersRequest(PipeRequest):
    operation: Literal["confirm_manual_orders"]
    commands: list[ManualConfirmationRequest] = Field(min_length=1, max_length=20)


class GetManualCommandRequest(PipeRequest):
    operation: Literal["get_manual_command"]
    account_id: str = Field(min_length=1, max_length=64)
    command_id: str = Field(min_length=1, max_length=128)


class ListManualCommandsRequest(PipeRequest):
    operation: Literal["list_manual_commands"]
    account_id: str = Field(min_length=1, max_length=64)
    source_id: str = Field(min_length=1, max_length=256)
    before_command_id: str | None = Field(default=None, min_length=1, max_length=128)
    limit: StrictInt = Field(default=50, ge=1, le=100)


class ControlRequest(PipeRequest):
    """One agent request line relayed by the app, with what only the app knows."""

    operation: Literal["control"]
    line: str = Field(min_length=1, max_length=MAX_CONTROL_LINE_BYTES)
    context: ControlContext


class ListProposalsRequest(PipeRequest):
    operation: Literal["list_proposals"]


class ApproveProposalRequest(PipeRequest):
    operation: Literal["approve_proposal"]
    proposal_id: str = Field(pattern=r"^p-[0-9a-f]{12}$")
    digest: str = Field(pattern=r"^[0-9a-f]{64}$")


class RejectProposalRequest(PipeRequest):
    operation: Literal["reject_proposal"]
    proposal_id: str = Field(pattern=r"^p-[0-9a-f]{12}$")


class DiscardProposalsRequest(PipeRequest):
    operation: Literal["discard_proposals"]


class AgentAuditRequest(PipeRequest):
    operation: Literal["agent_audit"]
    limit: StrictInt = Field(default=50, ge=1, le=100)


class AssistantAskRequest(PipeRequest):
    operation: Literal["assistant_ask"]
    conversation_id: str = Field(pattern=r"^c-[0-9a-f]{12}$")
    text: str = Field(min_length=1, max_length=2000)
    context: AskContext
    provider: ProviderConfiguration
    # Empty for a model on this Mac or a custom address; ProviderConfiguration.reader() decides.
    provider_api_key: SecretStr


class AssistantTurnRequest(PipeRequest):
    operation: Literal["assistant_turn"]
    turn_id: str = Field(pattern=r"^t-[0-9a-f]{12}$")
    after: StrictInt = Field(ge=0)


class AssistantCancelRequest(PipeRequest):
    operation: Literal["assistant_cancel"]
    turn_id: str = Field(pattern=r"^t-[0-9a-f]{12}$")


class AssistantResetRequest(PipeRequest):
    operation: Literal["assistant_reset"]


RequestType = Annotated[
    SubmitRequest
    | GetStatusRequest
    | GetWorkflowRequest
    | GetTradingStatusRequest
    | GetTradingActivationRequest
    | StartTradingRequest
    | ValidateTradingRequest
    | CheckConnectionRequest
    | PauseTradingRequest
    | UpdateAccountLimitsRequest
    | CreateBackupRequest
    | PreviewRestoreRequest
    | PrepareRestoreCandidateRequest
    | RestoreCandidateStatusRequest
    | AbortRestoreCandidateRequest
    | RestorePreflightRequest
    | CompleteRestoreCandidateRequest
    | ControlAccountRequest
    | ResolveOwnershipRequest
    | GetAccountsRequest
    | GetSourceActivityRequest
    | EvaluateHistoricalProfileRequest
    | ReviewProfileExamplesRequest
    | LearnGuruPlaybookRequest
    | ReplayGuruPostsRequest
    | GetAccountEventsRequest
    | GetEquityHistoryRequest
    | SaveManualCorrectionRequest
    | PreviewManualOrderRequest
    | ConfirmManualOrdersRequest
    | PreviewLotSaleRequest
    | ConfirmLotSaleRequest
    | GetManualCommandRequest
    | ListManualCommandsRequest
    | ControlRequest
    | ListProposalsRequest
    | ApproveProposalRequest
    | RejectProposalRequest
    | DiscardProposalsRequest
    | AgentAuditRequest
    | AssistantAskRequest
    | AssistantTurnRequest
    | AssistantCancelRequest
    | AssistantResetRequest
    | StopRequest,
    Field(discriminator="operation"),
]
REQUEST_ADAPTER = TypeAdapter(RequestType)

# A handler answers one request with one contract response line.
type RequestHandler = Callable[..., Awaitable[bytes]]
