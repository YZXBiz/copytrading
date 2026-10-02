"""Manual corrections, orders, and lot sales: save, preview, confirm, and read back."""

from copytrading_engine.execution.domain.manual_commands import ManualCommandPageRequest
from copytrading_engine.host.pipe.requests import (
    ConfirmLotSaleRequest,
    ConfirmManualOrdersRequest,
    GetManualCommandRequest,
    ListManualCommandsRequest,
    PipeRequest,
    PreviewLotSaleRequest,
    PreviewManualOrderRequest,
    RequestHandler,
    SaveManualCorrectionRequest,
)
from copytrading_engine.host.pipe.responses import reply
from copytrading_engine.host.pipe.services import TradingServices


class ManualOrderHandlers:
    """Save corrections and preview, confirm, and read back manual orders."""

    def __init__(self, *, trading: TradingServices | None) -> None:
        self._trading = trading

    def handlers(self) -> dict[type[PipeRequest], RequestHandler]:
        return {
            SaveManualCorrectionRequest: self._on_save_manual_correction,
            PreviewManualOrderRequest: self._on_preview_manual_order,
            ConfirmManualOrdersRequest: self._on_confirm_manual_orders,
            PreviewLotSaleRequest: self._on_preview_lot_sale,
            ConfirmLotSaleRequest: self._on_confirm_lot_sale,
            GetManualCommandRequest: self._on_get_manual_command,
            ListManualCommandsRequest: self._on_list_manual_commands,
        }

    async def _on_save_manual_correction(self, request: SaveManualCorrectionRequest) -> bytes:
        if self._trading is None:
            return reply(request.version, request.request_id, error="unavailable")
        outcome = await self._trading.manual.save_manual_correction(request.correction)
        return reply(
            request.version,
            request.request_id,
            ok={"type": "manual_correction", "correction": outcome.model_dump(mode="json")},
        )

    async def _on_preview_manual_order(self, request: PreviewManualOrderRequest) -> bytes:
        if self._trading is None:
            return reply(request.version, request.request_id, error="unavailable")
        preview = await self._trading.manual.preview_manual_order(request.preview)
        return reply(
            request.version,
            request.request_id,
            ok={"type": "manual_preview", "preview": preview.model_dump(mode="json")},
        )

    async def _on_confirm_manual_orders(self, request: ConfirmManualOrdersRequest) -> bytes:
        if self._trading is None:
            return reply(request.version, request.request_id, error="unavailable")
        outcome = await self._trading.manual.confirm_manual_orders(tuple(request.commands))
        return reply(
            request.version,
            request.request_id,
            ok={"type": "manual_commands", "commands": outcome.model_dump(mode="json")},
        )

    async def _on_preview_lot_sale(self, request: PreviewLotSaleRequest) -> bytes:
        if self._trading is None:
            return reply(request.version, request.request_id, error="unavailable")
        preview = await self._trading.manual.preview_lot_sale(request.preview)
        return reply(
            request.version,
            request.request_id,
            ok={"type": "lot_sale_preview", "preview": preview.model_dump(mode="json")},
        )

    async def _on_confirm_lot_sale(self, request: ConfirmLotSaleRequest) -> bytes:
        if self._trading is None:
            return reply(request.version, request.request_id, error="unavailable")
        result = await self._trading.manual.confirm_lot_sale(request.sale)
        return reply(
            request.version,
            request.request_id,
            ok={"type": "lot_sale", "sale": result.model_dump(mode="json")},
        )

    async def _on_get_manual_command(self, request: GetManualCommandRequest) -> bytes:
        if self._trading is None:
            return reply(request.version, request.request_id, error="unavailable")
        result = await self._trading.manual.manual_command_result(
            request.account_id, request.command_id
        )
        return reply(
            request.version,
            request.request_id,
            ok={"type": "manual_command", "command": result.model_dump(mode="json")},
        )

    async def _on_list_manual_commands(self, request: ListManualCommandsRequest) -> bytes:
        if self._trading is None:
            return reply(request.version, request.request_id, error="unavailable")
        page = await self._trading.operator.list_manual_commands(
            ManualCommandPageRequest(
                account_id=request.account_id,
                source_id=request.source_id,
                before_command_id=request.before_command_id,
                limit=request.limit,
            )
        )
        return reply(
            request.version,
            request.request_id,
            ok={"type": "manual_command_page", "commands": page.model_dump(mode="json")},
        )
