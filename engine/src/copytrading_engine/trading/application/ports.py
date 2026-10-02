"""Ports the trading use cases need from retained operational evidence."""

from pathlib import Path
from typing import Protocol

from copytrading_engine.execution.domain.ledger_state import LedgerSnapshot
from copytrading_engine.execution.domain.manual_commands import ManualSourceEvidence
from copytrading_engine.execution.presentation.operator_views import (
    AccountEventPage,
    AccountOverview,
    DestinationView,
)
from copytrading_engine.shared.raw_message import RawMessage
from copytrading_engine.trading.presentation.operator_models import SourceActivityPage


class ChannelHistory(Protocol):
    """Recent text posts of one source channel, for learning a guru's style."""

    async def recent_posts(
        self, token: str, channel_id: str, author_id: str | None, limit: int
    ) -> tuple[str, ...]: ...


class OperatorEvidence(Protocol):
    """Read committed source, parser, and account evidence without writing or binding."""

    def source_page(
        self,
        database: Path,
        *,
        before_seq: int | None,
        limit: int,
        destinations: dict[str, tuple[DestinationView, ...]],
    ) -> SourceActivityPage: ...

    def retained_account(
        self, path: Path, *, before_seq: int | None = None, limit: int = 50
    ) -> tuple[AccountOverview, LedgerSnapshot, AccountEventPage]: ...

    def manual_source_evidence(self, database: Path, source_id: str) -> ManualSourceEvidence: ...

    def historical_source_message(self, database: Path, source_id: str) -> RawMessage: ...
