"""The trading services the pipe server calls, as the protocols it depends on."""

from dataclasses import dataclass
from typing import Protocol

from pydantic import SecretStr

from copytrading_engine.execution.domain.lifecycle import (
    AccountControlCommand,
    AccountControlResult,
)
from copytrading_engine.execution.domain.lot_sales import (
    LotSaleConfirmation,
    LotSalePreview,
    LotSalePreviewRequest,
    LotSaleResult,
)
from copytrading_engine.execution.domain.manual_commands import (
    ManualCommandPage,
    ManualCommandPageRequest,
    ManualCommandResult,
    ManualCommandsOutcome,
    ManualConfirmationRequest,
    ManualCorrectionOutcome,
    ManualCorrectionRequest,
    ManualOrderPreview,
    ManualPreviewRequest,
)
from copytrading_engine.execution.domain.market import EquityHistory, HistoryWindow
from copytrading_engine.execution.domain.ownership import (
    OwnershipResolution,
    OwnershipResolutionRequest,
)
from copytrading_engine.execution.domain.sizing import RouteConnection
from copytrading_engine.execution.presentation.operator_views import (
    AccountEventPage,
    AccountOverviewPage,
)
from copytrading_engine.trading.adapters.activation import TradingActivationStatus
from copytrading_engine.trading.adapters.capabilities import (
    CapabilityCheck,
    TradingCapabilityReport,
)
from copytrading_engine.trading.domain.config import (
    ConnectionCheck,
    ProviderConfiguration,
    TradingConfiguration,
    TradingSecrets,
)
from copytrading_engine.trading.domain.profiles import (
    LearnedPlaybook,
    ProfileEvaluation,
    ProfileExampleReview,
    ProfileRevision,
)
from copytrading_engine.trading.domain.status import TradingStatus
from copytrading_engine.trading.entrypoints.runtime import TradingRuntime
from copytrading_engine.trading.presentation.operator_models import SourceActivityPage


class TradingLifecycle(Protocol):
    def status(self) -> TradingStatus: ...

    async def validate(
        self, configuration: TradingConfiguration, secrets: TradingSecrets
    ) -> TradingCapabilityReport: ...

    async def check_connection(self, connection: ConnectionCheck) -> CapabilityCheck: ...

    async def start(
        self, configuration: TradingConfiguration, secrets: TradingSecrets, activation_id: str
    ) -> TradingStatus: ...

    def activation_status(self, activation_id: str) -> TradingActivationStatus: ...

    async def pause(self) -> TradingStatus: ...

    def register_restore_secrets(self, values: tuple[str, ...]) -> None: ...


class OperatorReads(Protocol):
    async def account_overviews(
        self, before_account_id: str | None, limit: int
    ) -> AccountOverviewPage: ...

    async def source_activity(self, before_seq: int | None, limit: int) -> SourceActivityPage: ...

    async def account_events(
        self, account_id: str, before_seq: int | None, limit: int
    ) -> AccountEventPage: ...

    async def equity_history(
        self, account_id: str, window: HistoryWindow
    ) -> EquityHistory | None: ...

    async def list_manual_commands(
        self, request: ManualCommandPageRequest
    ) -> ManualCommandPage: ...


class ManualIntervention(Protocol):
    async def control_account(self, command: AccountControlCommand) -> AccountControlResult: ...

    async def resolve_ownership(
        self, local_account_id: str, request: OwnershipResolutionRequest
    ) -> OwnershipResolution: ...

    async def save_manual_correction(
        self, request: ManualCorrectionRequest
    ) -> ManualCorrectionOutcome: ...

    async def preview_manual_order(self, request: ManualPreviewRequest) -> ManualOrderPreview: ...

    async def preview_lot_sale(self, request: LotSalePreviewRequest) -> LotSalePreview: ...

    async def confirm_lot_sale(self, request: LotSaleConfirmation) -> LotSaleResult: ...

    async def confirm_manual_orders(
        self, requests: tuple[ManualConfirmationRequest, ...]
    ) -> ManualCommandsOutcome: ...

    async def manual_command_result(
        self, account_id: str, command_id: str
    ) -> ManualCommandResult: ...


class ProfileReview(Protocol):
    async def evaluate_historical_profile(
        self,
        source_id: str,
        profile: ProfileRevision,
        provider: ProviderConfiguration,
        provider_api_key: SecretStr,
        destinations: list[RouteConnection],
    ) -> ProfileEvaluation: ...

    async def review_profile_examples(
        self,
        profile: ProfileRevision,
        provider: ProviderConfiguration,
        provider_api_key: SecretStr,
        destinations: list[RouteConnection],
    ) -> ProfileExampleReview: ...

    async def learn_playbook(
        self,
        channel_id: str,
        author_id: str | None,
        discord_token: SecretStr,
        provider: ProviderConfiguration,
        provider_api_key: SecretStr,
    ) -> LearnedPlaybook: ...


@dataclass(frozen=True, slots=True)
class TradingServices:
    """The trading capabilities the pipe serves, one per kind of caller task."""

    lifecycle: TradingLifecycle
    operator: OperatorReads
    manual: ManualIntervention
    profiles: ProfileReview

    @classmethod
    def of(cls, runtime: TradingRuntime) -> TradingServices:
        return cls(runtime, runtime.operator, runtime.manual, runtime.profiles)
