"""Validated nonsecret routing policy and transient runtime credentials."""

import hashlib
import json
from decimal import Decimal
from typing import Literal, Self

from pydantic import BaseModel, ConfigDict, Field, SecretStr, StrictBool, StrictInt, model_validator

from copytrading_engine.execution.domain.sizing import RouteConnection
from copytrading_engine.shared.configuration_version import CONFIGURATION_VERSION
from copytrading_engine.shared.model_providers import (
    LOCAL_PROVIDERS,
    ModelProvider,
    ProviderConfig,
    endpoint_problem,
)
from copytrading_engine.trading.domain.profiles import ProfileRevision


class SourceConfiguration(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True, hide_input_in_errors=True)

    channel_ids: tuple[str, ...] = Field(min_length=1)
    author_ids: tuple[str, ...] = ()

    @model_validator(mode="after")
    def validate_ids(self) -> Self:
        for value in (*self.channel_ids, *self.author_ids):
            if not value.isascii() or not value.isdigit() or len(value) > 32:
                raise ValueError("Discord identifiers must be decimal strings")
        if len(set(self.channel_ids)) != len(self.channel_ids):
            raise ValueError("source channel identifiers must be unique")
        return self


class ProviderConfiguration(BaseModel):
    """The model service that reads posts. Only a local or custom OpenAI-compatible service
    takes an address; every named service has its own."""

    model_config = ConfigDict(extra="forbid", frozen=True, hide_input_in_errors=True)

    name: ModelProvider
    model: str = Field(min_length=1, max_length=128)
    base_url: str | None = Field(default=None, max_length=512)

    @model_validator(mode="after")
    def validate_endpoint(self) -> Self:
        if self.name == "openrouter" and "/" not in self.model:
            raise ValueError(
                "OpenRouter model names start with their provider, like openai/gpt-5.5"
            )
        if self.name == "openai_compatible" and self.base_url is None:
            raise ValueError("A custom OpenAI-compatible model needs its address")
        if self.base_url is not None:
            if self.name not in LOCAL_PROVIDERS:
                raise ValueError("Only a local or custom model takes an address")
            if (problem := endpoint_problem(self.base_url)) is not None:
                raise ValueError(problem)
        return self

    def reader(self, api_key: SecretStr, *, timeout: float) -> ProviderConfig:
        """The reader's configuration; a named cloud service always needs its key."""
        if not api_key.get_secret_value() and self.name not in LOCAL_PROVIDERS:
            raise ValueError("The model API key is required")
        return ProviderConfig(
            api_key=api_key, model=self.model, timeout=timeout, base_url=self.base_url
        )


class AccountPolicy(BaseModel):
    """Existing execution policy values, kept explicit for a saved native profile."""

    model_config = ConfigDict(extra="forbid", frozen=True, hide_input_in_errors=True)

    max_order_usd: Decimal = Field(default=Decimal("100"), gt=0)
    max_symbol_usd: Decimal = Field(default=Decimal("600"), gt=0)
    max_total_usd: Decimal = Field(default=Decimal("2500"), gt=0)
    daily_loss_cap_usd: Decimal = Field(default=Decimal("250"), gt=0)
    max_entries_per_day: StrictInt = Field(default=30, gt=0)
    max_signal_age_seconds: StrictInt = Field(default=120, gt=0, le=600)
    order_timeout_seconds: StrictInt = Field(default=60, gt=0, le=600)
    poll_seconds: float = Field(default=2, ge=1, le=30)
    extended_hours: StrictBool = True
    overnight: StrictBool = False
    copy_exits: StrictBool = True
    max_above_signal_pct: Decimal = Field(default=Decimal("0"), ge=0, le=100)

    @model_validator(mode="after")
    def validate_sessions(self) -> Self:
        if self.overnight and not self.extended_hours:
            raise ValueError("overnight trading requires extended hours")
        return self


class AccountConfiguration(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True, hide_input_in_errors=True)

    id: str = Field(pattern=r"^[a-zA-Z0-9_-]{1,64}$")
    environment: Literal["paper", "live"]
    policy: AccountPolicy = Field(default_factory=AccountPolicy)


class RouteConfiguration(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True, hide_input_in_errors=True)

    source: Literal["discord"] = "discord"
    channel_id: str
    author_id: str | None = None
    guru_id: str = Field(pattern=r"^[a-zA-Z0-9_-]{1,64}$")
    profile_revision: str = Field(pattern=r"^[0-9a-f]{64}$")
    connections: tuple[RouteConnection, ...] = Field(min_length=1)

    @model_validator(mode="after")
    def validate_source_identity(self) -> Self:
        for value in (self.channel_id, self.author_id):
            if value is not None and (
                not value.isascii() or not value.isdigit() or len(value) > 32
            ):
                raise ValueError("Discord identifiers must be decimal strings")
        return self


class NotificationConfiguration(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True, hide_input_in_errors=True)

    chat_id: str = Field(min_length=1, max_length=128)


class TradingConfiguration(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True, hide_input_in_errors=True)

    version: Literal[4] = CONFIGURATION_VERSION
    source: SourceConfiguration
    provider: ProviderConfiguration
    accounts: tuple[AccountConfiguration, ...] = Field(min_length=1)
    profiles: tuple[ProfileRevision, ...] = Field(min_length=1)
    routes: tuple[RouteConfiguration, ...] = Field(min_length=1)
    notification: NotificationConfiguration | None = None

    def revision(self) -> str:
        canonical = json.dumps(self.model_dump(mode="json"), sort_keys=True, separators=(",", ":"))
        return hashlib.sha256(canonical.encode()).hexdigest()

    @model_validator(mode="after")
    def validate_references(self) -> Self:
        account_ids = [account.id for account in self.accounts]
        if len(set(account_ids)) != len(account_ids):
            raise ValueError("account identifiers must be unique")
        profile_revisions = {profile.profile_revision: profile for profile in self.profiles}
        if len(profile_revisions) != len(self.profiles):
            raise ValueError("profile revisions must be unique")
        source_rules = [(route.source, route.channel_id, route.author_id) for route in self.routes]
        if len(set(source_rules)) != len(source_rules):
            raise ValueError("source identity rules must be unique")
        by_channel: dict[tuple[str, str], list[RouteConfiguration]] = {}
        for route in self.routes:
            if route.source != "discord" or route.channel_id not in self.source.channel_ids:
                raise ValueError("route references an unknown source channel")
            by_channel.setdefault((route.source, route.channel_id), []).append(route)
            profile = profile_revisions.get(route.profile_revision)
            if profile is None or profile.guru_id != route.guru_id:
                raise ValueError("route references an unknown guru profile revision")
            destination_ids = [connection.account_id for connection in route.connections]
            if len(set(destination_ids)) != len(destination_ids):
                raise ValueError("route account identifiers must be unique")
            if not set(destination_ids).issubset(account_ids):
                raise ValueError("route references an unknown account")
        for rules in by_channel.values():
            if len(rules) > 1 and any(route.author_id is None for route in rules):
                raise ValueError("shared channels require disambiguating author identities")
        return self


class BrokerCredentials(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True, hide_input_in_errors=True)

    account_id: str
    key: SecretStr
    secret: SecretStr


class TradingSecrets(BaseModel):
    """IPC-only credentials. No instance is serialized to engine storage or logs."""

    model_config = ConfigDict(extra="forbid", frozen=True, hide_input_in_errors=True)

    discord_token: SecretStr
    provider_api_key: SecretStr
    brokers: tuple[BrokerCredentials, ...]
    notification_token: SecretStr | None = None

    @model_validator(mode="after")
    def validate_brokers(self) -> Self:
        identifiers = [broker.account_id for broker in self.brokers]
        if len(set(identifiers)) != len(identifiers):
            raise ValueError("broker credential identifiers must be unique")
        return self
