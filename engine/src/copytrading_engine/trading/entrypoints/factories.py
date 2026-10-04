"""What the runtime builds collaborators with: the Discord session, notifier, decoder, and owner."""

import asyncio
import datetime as dt
from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from pathlib import Path
from typing import Protocol

import discord

from copytrading_engine.execution.adapters.alpaca.broker import AlpacaCredentials
from copytrading_engine.execution.adapters.owner import ExecutionOwner
from copytrading_engine.execution.adapters.resources import default_account_lock_root
from copytrading_engine.execution.domain.signals import CopyConfig
from copytrading_engine.parsing.providers.registry import (
    ManagedDecoder,
    NamedDecoderFactory,
    builtin_registry,
)
from copytrading_engine.shared.model_providers import ProviderConfig
from copytrading_engine.shared.notification_models import NotificationPayload
from copytrading_engine.shared.payload_capture import PayloadCapture
from copytrading_engine.sources.application import ForwardBatch
from copytrading_engine.sources.session import DiscordSession
from copytrading_engine.sources.sqlite import SQLiteSourceStore
from copytrading_engine.trading.adapters.notifications import alert_sender
from copytrading_engine.trading.adapters.telemetry import TradingTelemetry
from copytrading_engine.trading.application.accounts import AccountOwner
from copytrading_engine.trading.domain.config import NotificationConfiguration


class SourceSession(Protocol):
    @property
    def ready(self) -> bool: ...

    def start(self, token: str) -> None: ...

    async def ensure_running(self) -> None: ...

    async def forward_if_ready(self, forwarder: ForwardBatch) -> None: ...

    async def close(self) -> None: ...


class NotificationSender(Protocol):
    async def send(self, payload: NotificationPayload) -> None: ...


type OwnerFactory = Callable[[Path, AlpacaCredentials, CopyConfig, str], Awaitable[AccountOwner]]


type SessionFactory = Callable[
    [
        SQLiteSourceStore,
        set[int],
        set[int] | None,
        asyncio.Event,
        Callable[[str, BaseException | None], None],
    ],
    SourceSession,
]


type NotifierFactory = Callable[[NotificationConfiguration, str], NotificationSender]


async def open_owner(
    path: Path,
    credentials: AlpacaCredentials,
    policy: CopyConfig,
    environment: str,
    *,
    telemetry: TradingTelemetry | None = None,
) -> AccountOwner:
    if environment not in {"paper", "live"}:
        raise ValueError("Unknown broker environment")
    owner = await ExecutionOwner.open(
        path,
        credentials,
        policy,
        environment=environment,
        account_lock_root=default_account_lock_root(),
        observer=telemetry,
    )
    try:
        await owner.recover_account(dt.datetime.now(dt.UTC))
        return owner
    except BaseException:
        await owner.close()
        raise


async def create_decoder(
    name: str,
    config: ProviderConfig,
    *,
    diagnostics: PayloadCapture | None = None,
) -> ManagedDecoder:
    return await builtin_registry().create(name, config, diagnostics=diagnostics)


def _create_session(
    source: SQLiteSourceStore,
    channels: set[int],
    authors: set[int] | None,
    stop: asyncio.Event,
    report_failure: Callable[[str, BaseException | None], None],
) -> SourceSession:
    client = discord.Client()
    return DiscordSession(
        client, channels, source, stop, authors=authors, report_failure=report_failure
    )


@dataclass(frozen=True)
class TradingFactories:
    owner: OwnerFactory = open_owner
    decoder: NamedDecoderFactory = create_decoder
    session: SessionFactory = _create_session
    notifier: NotifierFactory = alert_sender
