"""The app's manual-command fixtures decode into the engine's contracts."""

import json

from pydantic import BaseModel

from copytrading_engine.execution.domain.manual_commands import (
    ManualCommandPage,
    ManualCommandPageRequest,
    ManualCommandResult,
    ManualCommandsOutcome,
    ManualConfirmationRequest,
    ManualCorrectionOutcome,
    ManualCorrectionRequest,
    ManualOrderPreview,
    ManualPreviewRequest,
)
from copytrading_engine.trading.presentation.operator_models import SourceActivityPage

from ...contracts import CONTRACTS


def _fixture(name: str) -> dict:
    return json.loads((CONTRACTS / name).read_text())


def _validate[M: BaseModel](model: type[M], value: object) -> M:
    """Validate a fixture fragment as the JSON the native app sends or receives."""
    return model.model_validate_json(json.dumps(value))


def test_native_manual_request_fixtures_match_engine_contracts():
    correction = _fixture("manual-correction-request.json")
    parsed_correction = _validate(ManualCorrectionRequest, correction["correction"])
    assert parsed_correction.selected_account_ids == ("archive", "paper")

    preview = _fixture("manual-preview-request.json")
    assert _validate(ManualPreviewRequest, preview["preview"]).account_id == "paper"
    archive_preview = _fixture("manual-preview-archive-request.json")
    assert _validate(ManualPreviewRequest, archive_preview["preview"]).account_id == "archive"

    confirmation = _fixture("manual-confirmation-request.json")
    parsed_commands = tuple(
        _validate(ManualConfirmationRequest, item) for item in confirmation["commands"]
    )
    assert [item.account_id for item in parsed_commands] == ["paper", "archive"]
    command_lookup = _fixture("manual-command-request.json")
    assert command_lookup["operation"] == "get_manual_command"
    command_page = _fixture("manual-command-page-request.json")
    assert command_page["operation"] == "list_manual_commands"
    assert (
        _validate(
            ManualCommandPageRequest,
            {
                key: value
                for key, value in command_page.items()
                if key in {"account_id", "source_id", "before_command_id", "limit"}
            },
        ).limit
        == 50
    )


def test_native_manual_response_fixtures_match_engine_contracts():
    source = _fixture("manual-source-activity-response.json")
    source_item = _validate(SourceActivityPage, source["ok"]["activity"]).items[0]
    assert source_item.decision == "review"
    assert source_item.destinations[0].instruction_outcomes == ("ambiguous_trade_details",)
    assert source_item.destinations[1].orders[0].broker_id == "broker-prior-order"
    assert source_item.source_event.embeds[0].title == "Alert"
    assert source_item.source_event.attachments[0].status == "origin_rejected"

    correction = _fixture("manual-correction-response.json")
    assert (
        _validate(
            ManualCorrectionOutcome, correction["ok"]["correction"]
        ).correction.accepted_interpretation.decision
        == "review"
    )
    preview = _fixture("manual-preview-response.json")
    assert _validate(ManualOrderPreview, preview["ok"]["preview"]).plan is not None
    archive_preview = _fixture("manual-preview-archive-response.json")
    parsed_archive = _validate(ManualOrderPreview, archive_preview["ok"]["preview"])
    assert parsed_archive.request.account_id == "archive"

    commands = _fixture("manual-confirmation-response.json")
    outcomes = _validate(ManualCommandsOutcome, commands["ok"]["commands"]).outcomes
    assert outcomes[0].result is not None
    assert outcomes[1].error == "account_unavailable"
    command = _fixture("manual-command-response.json")
    assert _validate(ManualCommandResult, command["ok"]["command"]).status == "accepted"
    page = _validate(
        ManualCommandPage, _fixture("manual-command-page-response.json")["ok"]["commands"]
    )
    assert page.account_id == "paper"
    assert page.source_id == "discord:demo:review-8"
    assert page.items[0].status == "uncertain"
