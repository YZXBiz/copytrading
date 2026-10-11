"""Durable operator permission, separate from broker and risk readiness."""

from typing import Literal, Self

from pydantic import AwareDatetime, Field, model_validator

from copytrading_engine.execution.domain.values import Identifier, Value

type EntryPermission = Literal["disabled", "enabled", "paused"]
type RecoveryPreference = Literal["manual", "automatic"]


class AccountOwnerClosed(RuntimeError):
    """The account's executor is stopping or stopped; its retained ledger answers instead."""


class AccountControlConflict(ValueError):
    """A stable command identity was reused with different content."""


class AccountControlCommand(Value):
    command_id: Identifier
    account_id: Identifier
    action: Literal["pause", "resume", "set_recovery", "restore_manual"]
    recovery_preference: RecoveryPreference | None = None

    @model_validator(mode="after")
    def valid_action(self) -> Self:
        if (self.action == "set_recovery") != (self.recovery_preference is not None):
            raise ValueError("Recovery preference belongs only to set_recovery")
        return self


class AccountControlResult(Value):
    command: AccountControlCommand
    applied_at: AwareDatetime
    entry_permission: EntryPermission
    recovery_preference: RecoveryPreference


class AccountControl(Value):
    entry_permission: EntryPermission = "disabled"
    recovery_preference: RecoveryPreference = "manual"
    commands: dict[str, AccountControlResult] = Field(default_factory=dict)
