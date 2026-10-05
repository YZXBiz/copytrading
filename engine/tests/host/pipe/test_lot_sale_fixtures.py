"""The app's lot sale fixtures decode into the engine's contracts and serialize back the same."""

import json

from pydantic import BaseModel

from copytrading_engine.execution.domain.lot_sales import (
    LotSaleConfirmation,
    LotSalePreview,
    LotSalePreviewRequest,
    LotSaleResult,
)
from copytrading_engine.host.pipe.requests import ConfirmLotSaleRequest, PreviewLotSaleRequest

from ...contracts import CONTRACTS


def _fixture(name: str) -> dict:
    return json.loads((CONTRACTS / name).read_text())


def _round_trip[M: BaseModel](model: type[M], value: dict) -> M:
    parsed = model.model_validate_json(json.dumps(value))
    assert parsed.model_dump(mode="json") == value
    return parsed


def test_lot_sale_request_fixtures_match_engine_contracts():
    preview = _fixture("lot-sale-preview-request.json")
    assert PreviewLotSaleRequest.model_validate_json(json.dumps(preview)).preview.lot_id.startswith(
        "copy-"
    )
    assert _round_trip(LotSalePreviewRequest, preview["preview"]).account_id == "paper"

    confirmation = _fixture("lot-sale-confirm-request.json")
    assert (
        ConfirmLotSaleRequest.model_validate_json(json.dumps(confirmation)).sale.command_id
        == "lot-sale-1"
    )
    assert _round_trip(LotSaleConfirmation, confirmation["sale"]).actor == "owner"


def test_lot_sale_response_fixtures_match_engine_contracts():
    preview = _round_trip(
        LotSalePreview, _fixture("lot-sale-preview-response.json")["ok"]["preview"]
    )
    assert preview.plan is not None
    assert preview.plan.lot_id == preview.request.lot_id
    assert preview.plan.type == "limit"

    result = _round_trip(LotSaleResult, _fixture("lot-sale-response.json")["ok"]["sale"])
    assert result.status == "filled"
    assert result.sale.lot_id == preview.request.lot_id
