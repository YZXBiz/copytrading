"""Sanitized live runtime state exposed over the private control pipe."""

import datetime as dt
from dataclasses import dataclass
from typing import Literal

type TradingRunState = Literal["paused", "starting", "running", "degraded", "pausing", "failed"]
type AccountRunState = Literal["ready", "running", "failed", "paused"]


@dataclass(frozen=True)
class AccountStatus:
    id: str
    state: AccountRunState
    error_code: str | None = None
    entry_permission: str = "disabled"
    recovery_preference: str = "manual"
    readiness: str = "unavailable"
    account_risk_status: str = "unavailable"
    account_risk_reason: str | None = None
    account_activity_status: str = "unavailable"
    account_activity_reason: str | None = None


@dataclass(frozen=True)
class TradingStatus:
    state: TradingRunState = "paused"
    configured_accounts: int = 0
    active_accounts: int = 0
    source_connected: bool = False
    model_ready: bool = False
    pending_source: int = 0
    oldest_pending_source_at: dt.datetime | None = None
    pending_signals: int = 0
    oldest_pending_signal_at: dt.datetime | None = None
    processed_signals: int = 0
    error_code: str | None = None
    accounts: tuple[AccountStatus, ...] = ()
