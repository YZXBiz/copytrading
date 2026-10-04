"""Read-only connection checks required before a saved trading revision is activated."""

import asyncio
import difflib
import logging
from collections.abc import Awaitable, Callable
from typing import Literal, Protocol

import discord
import httpx
from pydantic import BaseModel, ConfigDict

from copytrading_engine.execution.adapters.alpaca.broker import AlpacaBroker, AlpacaCredentials
from copytrading_engine.parsing.providers.registry import ManagedDecoder, builtin_registry
from copytrading_engine.parsing.readiness import ModelReadiness, probe_model
from copytrading_engine.shared.cleanup import close_logged
from copytrading_engine.sources.source import require_history_channel
from copytrading_engine.trading.adapters.notifications import discord_webhook
from copytrading_engine.trading.domain.config import (
    AccountConfiguration,
    BrokerCheck,
    BrokerCredentials,
    ConnectionCheck,
    ModelCheck,
    NotificationCheck,
    NotificationConfiguration,
    ProviderConfiguration,
    SourceCheck,
    SourceConfiguration,
    TradingConfiguration,
    TradingSecrets,
)

log = logging.getLogger(__name__)

type CapabilityState = Literal["ready", "failed", "not_configured", "unsupported"]
type CapabilityName = Literal[
    "source", "model", "broker", "notification", "configuration", "public_source_authorization"
]


class CapabilityCheck(BaseModel):
    """Safe identity and permission evidence; never carries submitted credentials."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    name: CapabilityName
    state: CapabilityState
    subject: str | None = None
    environment: Literal["paper", "live"] | None = None
    identity: str | None = None
    adapter: str
    reason_code: str | None = None
    # A close name the provider lists, when the model asked for does not exist.
    suggestion: str | None = None


class TradingCapabilityReport(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)

    configuration_revision: str
    activatable: bool
    checks: tuple[CapabilityCheck, ...]
    release_gates: tuple[str, ...]
    cost_notice: str


class CapabilityProbes(Protocol):
    async def source(self, configuration: SourceConfiguration, token: str) -> CapabilityCheck: ...

    async def model(self, configuration: ProviderConfiguration, token: str) -> CapabilityCheck: ...

    async def broker(
        self, account: AccountConfiguration, credentials: BrokerCredentials
    ) -> CapabilityCheck: ...

    async def notification(
        self, configuration: NotificationConfiguration | None, token: str | None
    ) -> CapabilityCheck: ...


def _failed(
    name: CapabilityName,
    code: str,
    *,
    subject: str | None = None,
    environment: Literal["paper", "live"] | None = None,
    adapter: str = "connection_probe",
    suggestion: str | None = None,
) -> CapabilityCheck:
    return CapabilityCheck(
        name=name,
        state="failed",
        subject=subject,
        environment=environment,
        identity=None,
        adapter=adapter,
        reason_code=code,
        suggestion=suggestion,
    )


async def _closest_model(decoder: ManagedDecoder, asked: str) -> str | None:
    """The listed model name nearest to a mistyped one, or nothing when the list is unavailable."""
    try:
        names = await asyncio.wait_for(decoder.model_names(), timeout=15)
    except asyncio.CancelledError:
        raise
    except Exception:  # noqa: BLE001 - a missing list only means no suggestion
        return None
    matches = difflib.get_close_matches(asked, names, n=1, cutoff=0.6)
    return matches[0] if matches else None


async def _safely(
    name: CapabilityName,
    operation: Awaitable[CapabilityCheck],
    *,
    subject: str | None = None,
    environment: Literal["paper", "live"] | None = None,
) -> CapabilityCheck:
    try:
        return await operation
    except asyncio.CancelledError:
        raise
    except Exception:  # noqa: BLE001 - any client failure becomes a failed capability check
        return _failed(
            name, f"{name}_capability_unavailable", subject=subject, environment=environment
        )


class TradingCapabilityService:
    """Run source, provider, broker, and notification checks without saving config."""

    def __init__(self, probes: CapabilityProbes | None = None) -> None:
        self._probes = probes or NativeCapabilityProbes()

    async def validate(
        self, configuration: TradingConfiguration, secrets: TradingSecrets
    ) -> TradingCapabilityReport:
        configuration = TradingConfiguration.model_validate(configuration.model_dump())
        secrets = TradingSecrets.model_validate(secrets.model_dump())
        by_account = {credential.account_id: credential for credential in secrets.brokers}
        account_ids = {account.id for account in configuration.accounts}
        checks: list[CapabilityCheck] = []
        if set(by_account) != account_ids:
            checks.append(_failed("configuration", "broker_credential_mapping_invalid"))

        operations = [
            _safely(
                "source",
                self._probes.source(configuration.source, secrets.discord_token.get_secret_value()),
            ),
            _safely(
                "model",
                self._probes.model(
                    configuration.provider, secrets.provider_api_key.get_secret_value()
                ),
            ),
            _safely(
                "notification",
                self._probes.notification(
                    configuration.notification,
                    secrets.notification_token.get_secret_value()
                    if secrets.notification_token is not None
                    else None,
                ),
            ),
        ]
        for account in configuration.accounts:
            credentials = by_account.get(account.id)
            if credentials is None:
                operations.append(
                    asyncio.sleep(
                        0,
                        result=_failed(
                            "broker",
                            "broker_credentials_missing",
                            subject=account.id,
                            environment=account.environment,
                        ),
                    )
                )
            else:
                operations.append(
                    _safely(
                        "broker",
                        self._probes.broker(account, credentials),
                        subject=account.id,
                        environment=account.environment,
                    )
                )
        checks.extend(await asyncio.gather(*operations))
        checks.append(
            CapabilityCheck(
                name="public_source_authorization",
                state="unsupported",
                identity=None,
                adapter="discord-py-self-user-token",
                reason_code="public_discord_authorization_not_qualified",
            )
        )
        required = [check for check in checks if check.name != "public_source_authorization"]
        activatable = all(check.state in {"ready", "not_configured"} for check in required)
        return TradingCapabilityReport(
            configuration_revision=configuration.revision(),
            activatable=activatable,
            checks=tuple(checks),
            release_gates=("public_discord_authorization_not_qualified",),
            cost_notice=(
                "Model validation sends one short no-trade prompt to the configured provider; "
                "provider charges may apply. Notification validation checks bot/chat access "
                "without sending a message."
            ),
        )

    async def check(self, connection: ConnectionCheck) -> CapabilityCheck:
        """One service, the moment the owner connects it: the same read-only check a full
        validation runs for it, without saving anything or granting a start."""
        match connection:
            case SourceCheck():
                return await _safely(
                    "source",
                    self._probes.source(connection.source, connection.token.get_secret_value()),
                )
            case ModelCheck():
                return await _safely(
                    "model",
                    self._probes.model(connection.provider, connection.api_key.get_secret_value()),
                )
            case BrokerCheck():
                account = connection.account
                return await _safely(
                    "broker",
                    self._probes.broker(account, connection.credentials),
                    subject=account.id,
                    environment=account.environment,
                )
            case NotificationCheck():
                return await _safely(
                    "notification",
                    self._probes.notification(
                        connection.notification, connection.token.get_secret_value()
                    ),
                )


class NativeCapabilityProbes:
    """Actual read-only adapters used by the desktop engine."""

    def __init__(
        self,
        *,
        discord_client_factory: Callable[..., discord.Client] = discord.Client,
        http_client_factory: Callable[..., httpx.AsyncClient] = httpx.AsyncClient,
        source_timeout_seconds: float = 20,
    ) -> None:
        if source_timeout_seconds <= 0:
            raise ValueError("Source probe timeout must be positive")
        self._discord_client_factory = discord_client_factory
        self._http_client_factory = http_client_factory
        self._source_timeout_seconds = source_timeout_seconds

    async def source(self, configuration: SourceConfiguration, token: str) -> CapabilityCheck:
        # discord.py-self does not expose discord.Intents. Its documented client
        # defaults are also what the existing DiscordSession adapter uses.
        client = self._discord_client_factory()
        stage = "login"
        try:
            async with asyncio.timeout(self._source_timeout_seconds):
                await client.login(token)
                user = client.user
                if user is None:
                    return _failed("source", "source_identity_unavailable")
                for channel_id in configuration.channel_ids:
                    stage = "channel"
                    channel = await client.fetch_channel(int(channel_id))
                    try:
                        readable = require_history_channel(channel)
                    except ValueError:
                        return _failed("source", "source_channel_not_readable")
                    stage = "history"
                    history = readable.history(limit=1)
                    try:
                        await anext(history, None)
                    finally:
                        close = getattr(history, "aclose", None)
                        if close is not None:
                            await close()
                return CapabilityCheck(
                    name="source",
                    state="ready",
                    identity=f"discord_user:{user.id}",
                    adapter="discord-py-self-user-token",
                    reason_code=None,
                )
        except asyncio.CancelledError:
            raise
        except TimeoutError:
            reason = (
                "source_history_probe_timed_out" if stage == "history" else "source_probe_timed_out"
            )
            return _failed("source", reason)
        except discord.Forbidden:
            reason = (
                "source_history_permission_denied"
                if stage == "history"
                else "source_channel_access_denied"
            )
            return _failed("source", reason)
        except discord.HTTPException:
            reason = (
                "source_history_read_failed"
                if stage == "history"
                else "source_auth_or_channel_access"
            )
            return _failed("source", reason)
        except Exception:  # noqa: BLE001 - any client failure becomes a failed capability check
            reason = (
                "source_history_read_failed"
                if stage == "history"
                else "source_auth_or_channel_access"
            )
            return _failed("source", reason)
        finally:
            await close_logged(client.close, resource="source_probe", log=log)

    async def model(self, configuration: ProviderConfiguration, token: str) -> CapabilityCheck:
        from pydantic import SecretStr

        decoder = None
        try:
            decoder = await builtin_registry().create(
                configuration.name,
                configuration.reader(SecretStr(token), timeout=20),
            )
            health = ModelReadiness()
            await asyncio.wait_for(probe_model(decoder, health), timeout=25)
            if health.error == "provider_key_rejected":
                return _failed("model", "model_key_rejected", adapter=configuration.name)
            if health.error == "provider_model_not_found":
                return _failed(
                    "model",
                    "model_not_found",
                    adapter=configuration.name,
                    suggestion=await _closest_model(decoder, configuration.model),
                )
            if health.error in {"provider_unavailable", "provider_timeout"}:
                return _failed("model", "model_unreachable", adapter=configuration.name)
            if not health.ready:
                return _failed("model", "model_probe_rejected", adapter=configuration.name)
            return CapabilityCheck(
                name="model",
                state="ready",
                identity=f"{configuration.name}:{configuration.model}",
                adapter=configuration.name,
                reason_code=None,
            )
        except asyncio.CancelledError:
            raise
        except Exception:  # noqa: BLE001 - any client failure becomes a failed capability check
            return _failed("model", "model_auth_or_probe_failed", adapter=configuration.name)
        finally:
            if decoder is not None:
                await close_logged(decoder.close, resource="model_probe", log=log)

    async def broker(
        self, account: AccountConfiguration, credentials: BrokerCredentials
    ) -> CapabilityCheck:
        return await asyncio.to_thread(self._broker_read, account, credentials)

    @staticmethod
    def _broker_read(
        account: AccountConfiguration, credentials: BrokerCredentials
    ) -> CapabilityCheck:
        broker = None
        try:
            broker = AlpacaBroker(
                AlpacaCredentials(credentials.key, credentials.secret), account.environment
            )
            identity = broker.account()
            if not identity.active:
                return _failed(
                    "broker",
                    "broker_account_not_tradeable",
                    subject=account.id,
                    environment=account.environment,
                    adapter="alpaca_read_only",
                )
            broker.positions()
            broker.open_orders()
            return CapabilityCheck(
                name="broker",
                state="ready",
                subject=account.id,
                environment=account.environment,
                identity=identity.id,
                adapter="alpaca_read_only",
                reason_code=None,
            )
        except Exception:  # noqa: BLE001 - any client failure becomes a failed capability check
            return _failed(
                "broker",
                "broker_auth_or_permissions_failed",
                subject=account.id,
                environment=account.environment,
                adapter="alpaca_read_only",
            )
        finally:
            if broker is not None:
                broker.close()

    async def notification(
        self, configuration: NotificationConfiguration | None, token: str | None
    ) -> CapabilityCheck:
        if configuration is None:
            return CapabilityCheck(
                name="notification",
                state="not_configured",
                adapter="not_configured",
                reason_code=None,
            )
        if token is None or not token:
            return _failed("notification", "notification_credentials_missing")
        if configuration.service == "discord":
            return await self._discord_webhook(token)
        try:
            async with self._http_client_factory(timeout=8, follow_redirects=False) as client:
                base = f"https://api.telegram.org/bot{token}"
                async with asyncio.timeout(10):
                    bot_response = await client.get(f"{base}/getMe")
                    bot_response.raise_for_status()
                    bot_body = bot_response.json()
                    if not isinstance(bot_body, dict) or bot_body.get("ok") is not True:
                        return _failed("notification", "notification_bot_identity_failed")
                    chat_response = await client.get(
                        f"{base}/getChat", params={"chat_id": configuration.chat_id}
                    )
                    chat_response.raise_for_status()
                    chat_body = chat_response.json()
                    if not isinstance(chat_body, dict) or chat_body.get("ok") is not True:
                        return _failed("notification", "notification_chat_access_failed")
                    bot = bot_body.get("result")
                    chat = chat_body.get("result")
                    if not isinstance(bot, dict) or not isinstance(chat, dict):
                        return _failed("notification", "notification_identity_invalid")
                    username = bot.get("username")
                    chat_id = chat.get("id")
                    if not isinstance(username, str) or type(chat_id) not in {int, str}:
                        return _failed("notification", "notification_identity_invalid")
                    return CapabilityCheck(
                        name="notification",
                        state="ready",
                        identity=f"telegram_bot:@{username};chat:{chat_id}",
                        adapter="telegram_read_only",
                        reason_code=None,
                    )
        except asyncio.CancelledError:
            raise
        except Exception:  # noqa: BLE001 - any client failure becomes a failed capability check
            return _failed("notification", "notification_auth_or_chat_access_failed")

    async def _discord_webhook(self, url: str) -> CapabilityCheck:
        """Reads the webhook's name and channel, which Discord answers without posting anything."""
        adapter = "discord_webhook_read_only"
        try:
            host, path = discord_webhook(url)
        except ValueError:
            return _failed("notification", "notification_webhook_invalid", adapter=adapter)
        try:
            async with self._http_client_factory(timeout=8, follow_redirects=False) as client:
                async with asyncio.timeout(10):
                    response = await client.get(f"https://{host}{path}")
                    response.raise_for_status()
                    body = response.json()
        except asyncio.CancelledError:
            raise
        except Exception:  # noqa: BLE001 - the URL is the secret, so no detail is kept
            return _failed("notification", "notification_webhook_unreachable", adapter=adapter)
        name = body.get("name") if isinstance(body, dict) else None
        channel = body.get("channel_id") if isinstance(body, dict) else None
        if not isinstance(name, str) or not isinstance(channel, str):
            return _failed("notification", "notification_identity_invalid", adapter=adapter)
        return CapabilityCheck(
            name="notification",
            state="ready",
            identity=f"discord_webhook:{name};channel:{channel}",
            adapter=adapter,
            reason_code=None,
        )
