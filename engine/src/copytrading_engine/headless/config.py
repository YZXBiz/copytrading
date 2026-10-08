"""Read copytrading.toml and the environment into the engine's own setup and keys.

The file holds everything the app's setup screens hold, in plain names. Keys never live in
the file: they come from environment variables, so the file can be shared or committed.
"""

import os
import re
import tomllib
from collections.abc import Mapping
from decimal import Decimal
from pathlib import Path
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, SecretStr, ValidationError

from copytrading_engine.execution.domain.sizing import RouteConnection
from copytrading_engine.shared.model_providers import ModelProvider
from copytrading_engine.trading.domain.config import (
    AccountConfiguration,
    AccountPolicy,
    BrokerCredentials,
    NotificationConfiguration,
    ProviderConfiguration,
    RouteConfiguration,
    SourceConfiguration,
    TradingConfiguration,
    TradingSecrets,
)
from copytrading_engine.trading.domain.profiles import (
    ProfileBuilder,
    ProfileDraft,
    ProfileExample,
)

type AgentAccess = Literal["off", "read_pause", "propose"]

DISCORD_TOKEN = "COPYTRADING_DISCORD_TOKEN"
MODEL_API_KEY = "COPYTRADING_MODEL_API_KEY"
TELEGRAM_TOKEN = "COPYTRADING_TELEGRAM_TOKEN"
DISCORD_WEBHOOK_URL = "COPYTRADING_DISCORD_WEBHOOK_URL"


DEFAULT_LIMITS = AccountPolicy()


class ConfigError(Exception):
    """The file or the environment cannot become a setup; each problem is one plain line."""

    def __init__(self, problems: list[str]) -> None:
        super().__init__("\n".join(problems))
        self.problems = problems


class _Strict(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)


class _Discord(_Strict):
    channels: tuple[str, ...] = Field(min_length=1)
    authors: tuple[str, ...] = ()


class _Model(_Strict):
    provider: ModelProvider
    name: str
    address: str | None = None


class _Account(_Strict):
    id: str
    environment: Literal["paper", "live"]
    limits: AccountPolicy = Field(default_factory=AccountPolicy)


class _Example(_Strict):
    message: str
    action: Literal["buy", "reduce", "close"]
    symbol: str
    fraction: Decimal | None = None
    price: Decimal | None = None
    buy_price: Decimal | None = None


class _Guru(_Strict):
    id: str
    name: str
    channel: str
    author: str | None = None
    playbook: str = ""
    playbook_file: str | None = None
    examples: tuple[_Example, ...] = ()
    # One guru copies into one account; that account's max_symbol_usd is the guru's full position.
    account: str


class _Telegram(_Strict):
    chat_id: str


class _DiscordAlerts(_Strict):
    """Alerts in a Discord channel; its webhook URL comes from the environment."""


class _Agents(_Strict):
    access: AgentAccess = "read_pause"


class _File(_Strict):
    discord: _Discord
    model: _Model
    accounts: tuple[_Account, ...] = Field(min_length=1)
    gurus: tuple[_Guru, ...] = Field(min_length=1)
    telegram: _Telegram | None = None
    discord_alerts: _DiscordAlerts | None = None
    agents: _Agents = Field(default_factory=_Agents)


class ServerSetup(BaseModel):
    """The engine's setup plus what only the headless server decides."""

    model_config = ConfigDict(frozen=True)

    configuration: TradingConfiguration
    agent_access: AgentAccess


def load_setup(path: Path) -> ServerSetup:
    """Parse and check copytrading.toml; every problem is reported at once."""
    try:
        raw = tomllib.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        raise ConfigError(
            [f"{path} does not exist. Run `copytrading-server init` first."]
        ) from None
    except tomllib.TOMLDecodeError as exc:
        raise ConfigError([f"{path} is not valid TOML: {exc}"]) from None
    try:
        parsed = _File.model_validate(_decimals(raw))
    except ValidationError as exc:
        raise ConfigError(_problems(exc)) from None
    profiles = []
    problems: list[str] = []
    for index, guru in enumerate(parsed.gurus):
        playbook = guru.playbook
        if guru.playbook_file is not None:
            playbook_path = (path.parent / guru.playbook_file).expanduser()
            try:
                playbook = playbook_path.read_text(encoding="utf-8")
            except OSError:
                problems.append(f"gurus[{index}] ({guru.id}): cannot read {playbook_path}")
                continue
        try:
            profiles.append(
                ProfileBuilder().build(
                    ProfileDraft(
                        guru_id=guru.id,
                        display_name=guru.name,
                        playbook=playbook,
                        examples=tuple(
                            ProfileExample(
                                message=example.message,
                                expected_action=example.action,
                                expected_symbol=example.symbol,
                                expected_fraction=example.fraction,
                                expected_price=example.price,
                                expected_buy_price=example.buy_price,
                            )
                            for example in guru.examples
                        ),
                    )
                )
            )
        except ValidationError as exc:
            problems.extend(f"gurus[{index}] ({guru.id}): {line}" for line in _problems(exc))
    if parsed.telegram is not None and parsed.discord_alerts is not None:
        problems.append("Choose one place for alerts: [telegram] or [discord_alerts], not both.")
    if problems:
        raise ConfigError(problems)
    limits = {account.id: account.limits for account in parsed.accounts}
    try:
        configuration = TradingConfiguration(
            source=SourceConfiguration(
                channel_ids=parsed.discord.channels, author_ids=parsed.discord.authors
            ),
            provider=ProviderConfiguration(
                name=parsed.model.provider, model=parsed.model.name, base_url=parsed.model.address
            ),
            accounts=tuple(
                AccountConfiguration(
                    id=account.id, environment=account.environment, policy=account.limits
                )
                for account in parsed.accounts
            ),
            profiles=tuple(profiles),
            routes=tuple(
                RouteConfiguration(
                    channel_id=guru.channel,
                    author_id=guru.author,
                    guru_id=guru.id,
                    profile_revision=profile.profile_revision,
                    connections=(
                        RouteConnection(
                            account_id=guru.account,
                            full_position_usd=limits.get(
                                guru.account, AccountPolicy()
                            ).max_symbol_usd,
                        ),
                    ),
                )
                for guru, profile in zip(parsed.gurus, profiles, strict=True)
            ),
            notification=(
                NotificationConfiguration(chat_id=parsed.telegram.chat_id)
                if parsed.telegram is not None
                else NotificationConfiguration(service="discord")
                if parsed.discord_alerts is not None
                else None
            ),
        )
    except ValidationError as exc:
        raise ConfigError(_problems(exc)) from None
    return ServerSetup(configuration=configuration, agent_access=parsed.agents.access)


def broker_key_names(account_id: str) -> tuple[str, str]:
    """The environment variables holding one account's Alpaca key and secret."""
    stem = re.sub(r"[^A-Z0-9]", "_", account_id.upper())
    return f"COPYTRADING_ALPACA_{stem}_KEY", f"COPYTRADING_ALPACA_{stem}_SECRET"


def load_secrets(
    configuration: TradingConfiguration, environ: Mapping[str, str] = os.environ
) -> TradingSecrets:
    """Every key the setup needs, from the environment; all missing names are listed."""
    missing: list[str] = []

    def required(name: str) -> SecretStr:
        value = environ.get(name, "").strip()
        if not value:
            missing.append(name)
        return SecretStr(value)

    discord = required(DISCORD_TOKEN)
    if configuration.provider.name in {"ollama", "openai_compatible"}:
        model_key = SecretStr(environ.get(MODEL_API_KEY, "").strip())
    else:
        model_key = required(MODEL_API_KEY)
    brokers = []
    for account in configuration.accounts:
        key_name, secret_name = broker_key_names(account.id)
        brokers.append(
            BrokerCredentials(
                account_id=account.id, key=required(key_name), secret=required(secret_name)
            )
        )
    alerts = configuration.notification
    alert_secret = (
        None
        if alerts is None
        else required(DISCORD_WEBHOOK_URL if alerts.service == "discord" else TELEGRAM_TOKEN)
    )
    if missing:
        raise ConfigError([f"Set {name} in the environment." for name in missing])
    return TradingSecrets(
        discord_token=discord,
        provider_api_key=model_key,
        brokers=tuple(brokers),
        notification_token=alert_secret,
    )


def _decimals(value: object) -> object:
    """TOML floats become exact decimals, so 0.1 stays 0.1 in money and fractions."""
    if isinstance(value, float):
        return Decimal(str(value))
    if isinstance(value, dict):
        return {key: _decimals(item) for key, item in value.items()}
    if isinstance(value, list):
        return [_decimals(item) for item in value]
    return value


def _problems(error: ValidationError) -> list[str]:
    lines = []
    for item in error.errors(include_input=False, include_url=False):
        where = "".join(
            f"[{part}]" if isinstance(part, int) else f".{part}" for part in item["loc"]
        ).lstrip(".")
        message = str(item["msg"]).removeprefix("Value error, ")
        if item["type"] == "string_type" and _names_a_discord_id(item["loc"]):
            message += " (put Discord IDs in quotes: they are longer than TOML numbers allow)"
        lines.append(f"{where}: {message}" if where else message)
    return lines


def _names_a_discord_id(location: tuple[int | str, ...]) -> bool:
    return any(part in {"channels", "authors", "channel", "author"} for part in location)
