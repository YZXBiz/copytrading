"""Start, pause, and check copying: validation grants an activation token."""

import hashlib
import hmac
import json
import os
import time
from dataclasses import dataclass
from uuid import uuid4

from copytrading_engine.host.pipe.requests import (
    CheckConnectionRequest,
    GetTradingActivationRequest,
    GetTradingStatusRequest,
    PauseTradingRequest,
    PipeRequest,
    RequestHandler,
    StartTradingRequest,
    ValidateTradingRequest,
)
from copytrading_engine.host.pipe.responses import reply, trading_reply
from copytrading_engine.host.pipe.services import TradingServices
from copytrading_engine.trading.domain.config import TradingSecrets


@dataclass(frozen=True)
class _ActivationGrant:
    token: str
    configuration_revision: str
    secret_fingerprint: str
    expires_at: float


class TradingLifecycleHandlers:
    """Validate, start, and pause copying; starting needs the latest validation's token."""

    def __init__(self, *, trading: TradingServices | None) -> None:
        self._trading = trading
        self._activation_key = os.urandom(32)
        self._activation_grant: _ActivationGrant | None = None

    def handlers(self) -> dict[type[PipeRequest], RequestHandler]:
        return {
            GetTradingStatusRequest: self._on_get_trading_status,
            GetTradingActivationRequest: self._on_get_trading_activation,
            ValidateTradingRequest: self._on_validate_trading,
            CheckConnectionRequest: self._on_check_connection,
            StartTradingRequest: self._on_start_trading,
            PauseTradingRequest: self._on_pause_trading,
        }

    async def _on_get_trading_status(self, request: GetTradingStatusRequest) -> bytes:
        if self._trading is None:
            return reply(request.version, request.request_id, error="unavailable")
        status = self._trading.lifecycle.status()
        return trading_reply(request.version, request.request_id, status)

    async def _on_get_trading_activation(self, request: GetTradingActivationRequest) -> bytes:
        if self._trading is None:
            return reply(request.version, request.request_id, error="unavailable")
        status = self._trading.lifecycle.activation_status(request.activation_id)
        return reply(
            request.version,
            request.request_id,
            ok={"type": "trading_activation", "activation": status.model_dump(mode="json")},
        )

    async def _on_validate_trading(self, request: ValidateTradingRequest) -> bytes:
        if self._trading is None:
            return reply(request.version, request.request_id, error="unavailable")
        report = await self._trading.lifecycle.validate(request.configuration, request.secrets)
        self._activation_grant = None
        token = None
        if report.activatable:
            token = uuid4().hex
            self._activation_grant = _ActivationGrant(
                token=token,
                configuration_revision=request.configuration.revision(),
                secret_fingerprint=self._secret_fingerprint(request.secrets),
                expires_at=time.monotonic() + 120,
            )
        return reply(
            request.version,
            request.request_id,
            ok={
                "type": "trading_validation",
                "report": report.model_dump(mode="json"),
                "activation_token": token,
            },
        )

    async def _on_check_connection(self, request: CheckConnectionRequest) -> bytes:
        """A single service's check never touches the start grant a full validation holds."""
        if self._trading is None:
            return reply(request.version, request.request_id, error="unavailable")
        check = await self._trading.lifecycle.check_connection(request.connection)
        return reply(
            request.version,
            request.request_id,
            ok={"type": "connection_check", "check": check.model_dump(mode="json")},
        )

    async def _on_start_trading(self, request: StartTradingRequest) -> bytes:
        if self._trading is None:
            return reply(request.version, request.request_id, error="unavailable")
        grant = self._activation_grant
        self._activation_grant = None
        if (
            grant is None
            or grant.token != request.validation_token
            or grant.configuration_revision != request.configuration.revision()
            or grant.secret_fingerprint != self._secret_fingerprint(request.secrets)
            or grant.expires_at < time.monotonic()
        ):
            return reply(request.version, request.request_id, error="invalid_request")
        status = await self._trading.lifecycle.start(
            request.configuration, request.secrets, request.activation_id
        )
        return trading_reply(request.version, request.request_id, status)

    async def _on_pause_trading(self, request: PauseTradingRequest) -> bytes:
        if self._trading is None:
            return reply(request.version, request.request_id, error="unavailable")
        status = await self._trading.lifecycle.pause()
        return trading_reply(request.version, request.request_id, status)

    def _secret_fingerprint(self, secrets: TradingSecrets) -> str:
        payload = {
            "discord_token": secrets.discord_token.get_secret_value(),
            "provider_api_key": secrets.provider_api_key.get_secret_value(),
            "brokers": [
                {
                    "account_id": item.account_id,
                    "key": item.key.get_secret_value(),
                    "secret": item.secret.get_secret_value(),
                }
                for item in sorted(secrets.brokers, key=lambda value: value.account_id)
            ],
            "notification_token": (
                secrets.notification_token.get_secret_value()
                if secrets.notification_token is not None
                else None
            ),
        }
        encoded = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode()
        return hmac.new(self._activation_key, encoded, hashlib.sha256).hexdigest()
