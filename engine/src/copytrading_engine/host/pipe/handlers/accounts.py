"""Accounts, activity, history, and the owner's account controls."""

from copytrading_engine.host.pipe.requests import (
    AttachAccountReadersRequest,
    ControlAccountRequest,
    DetachAccountReadersRequest,
    GetAccountFeedRequest,
    GetAccountsRequest,
    GetEquityHistoryRequest,
    GetSourceActivityRequest,
    PipeRequest,
    RequestHandler,
    ResolveOwnershipRequest,
)
from copytrading_engine.host.pipe.responses import reply
from copytrading_engine.host.pipe.services import TradingServices
from copytrading_engine.trading.application.paused_reader import ReadKeys


class AccountHandlers:
    """Answer account, activity, and history reads, and apply the owner's account controls."""

    def __init__(self, *, trading: TradingServices | None) -> None:
        self._trading = trading

    def handlers(self) -> dict[type[PipeRequest], RequestHandler]:
        return {
            ControlAccountRequest: self._on_control_account,
            ResolveOwnershipRequest: self._on_resolve_ownership,
            GetAccountsRequest: self._on_get_accounts,
            GetSourceActivityRequest: self._on_get_source_activity,
            GetAccountFeedRequest: self._on_get_account_feed,
            GetEquityHistoryRequest: self._on_get_equity_history,
            AttachAccountReadersRequest: self._on_attach_account_readers,
            DetachAccountReadersRequest: self._on_detach_account_readers,
        }

    async def _on_attach_account_readers(self, request: AttachAccountReadersRequest) -> bytes:
        if self._trading is None:
            return reply(request.version, request.request_id, error="unavailable")
        self._trading.operator.attach_readers(
            tuple(
                ReadKeys(
                    account_id=item.account_id,
                    environment=item.environment,
                    key=item.key,
                    secret=item.secret,
                )
                for item in request.accounts
            )
        )
        return reply(request.version, request.request_id, ok={"type": "account_readers"})

    async def _on_detach_account_readers(self, request: DetachAccountReadersRequest) -> bytes:
        if self._trading is None:
            return reply(request.version, request.request_id, error="unavailable")
        self._trading.operator.detach_readers()
        return reply(request.version, request.request_id, ok={"type": "account_readers"})

    async def _on_control_account(self, request: ControlAccountRequest) -> bytes:
        if self._trading is None:
            return reply(request.version, request.request_id, error="unavailable")
        result = await self._trading.manual.control_account(request.command)
        return reply(
            request.version,
            request.request_id,
            ok={"type": "account_control", "control": result.model_dump(mode="json")},
        )

    async def _on_resolve_ownership(self, request: ResolveOwnershipRequest) -> bytes:
        if self._trading is None:
            return reply(request.version, request.request_id, error="unavailable")
        result = await self._trading.manual.resolve_ownership(
            request.account_id, request.resolution
        )
        return reply(
            request.version,
            request.request_id,
            ok={
                "type": "ownership_resolution",
                "resolution": result.model_dump(mode="json"),
            },
        )

    async def _on_get_accounts(self, request: GetAccountsRequest) -> bytes:
        if self._trading is None:
            return reply(request.version, request.request_id, error="unavailable")
        accounts = await self._trading.operator.account_overviews(
            request.before_account_id, request.limit
        )
        return reply(
            request.version,
            request.request_id,
            ok={
                "type": "accounts",
                "accounts": accounts.model_dump(mode="json"),
            },
        )

    async def _on_get_source_activity(self, request: GetSourceActivityRequest) -> bytes:
        if self._trading is None:
            return reply(request.version, request.request_id, error="unavailable")
        page = await self._trading.operator.source_activity(request.before_seq, request.limit)
        return reply(
            request.version,
            request.request_id,
            ok={"type": "source_activity", "activity": page.model_dump(mode="json")},
        )

    async def _on_get_account_feed(self, request: GetAccountFeedRequest) -> bytes:
        if self._trading is None:
            return reply(request.version, request.request_id, error="unavailable")
        page = await self._trading.operator.account_feed(
            request.account_id, request.before_seq, request.limit
        )
        return reply(
            request.version,
            request.request_id,
            ok={"type": "account_feed", "feed": page.model_dump(mode="json")},
        )

    async def _on_get_equity_history(self, request: GetEquityHistoryRequest) -> bytes:
        if self._trading is None:
            return reply(request.version, request.request_id, error="unavailable")
        history = await self._trading.operator.equity_history(request.account_id, request.window)
        return reply(
            request.version,
            request.request_id,
            ok={
                "type": "equity_history",
                "account_id": request.account_id,
                "history": None if history is None else history.model_dump(mode="json"),
            },
        )
