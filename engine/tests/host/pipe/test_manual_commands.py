"""Private operator requests for reviewed manual trading commands."""

import datetime as dt
import json

from copytrading_engine.execution.domain.manual_commands import (
    ManualCommandPage,
    ManualCommandPageRequest,
    ManualCorrectionAccountResult,
    ManualCorrectionOutcome,
    ManualCorrectionRecord,
    ManualCorrectionRequest,
    ManualRefusal,
)
from copytrading_engine.host.pipe.server import PipeServer
from copytrading_engine.host.self_test.parser import SelfTestParser
from copytrading_engine.host.self_test.service import SelfTestService
from copytrading_engine.host.status import EngineQueries
from copytrading_engine.shared.signals import StockSignal

from ...contracts import contract
from .builders import decode, request_line, services


class _ManualControl:
    async def save_manual_correction(
        self, request: ManualCorrectionRequest
    ) -> ManualCorrectionOutcome:
        signal = StockSignal(
            source="discord",
            channel_id="demo",
            id="message-1",
            timestamp=dt.datetime(2026, 1, 5, 15, tzinfo=dt.UTC),
            text="ambiguous source",
            parser_profile="fixture",
            model="fixture",
            decision="review",
            reason="ambiguous_trade_details",
            evidence=(),
            instructions=(),
        )

        correction = ManualCorrectionRecord(
            correction_id=request.correction_id,
            source_id=request.source_id,
            selected_account_ids=request.selected_account_ids,
            revision=1,
            actor=request.actor,
            reason=request.reason,
            instructions=request.instructions,
            source_revision=1,
            source_at=signal.timestamp,
            source_text=signal.text,
            accepted_interpretation=signal,
            recorded_at=signal.timestamp,
        )
        return ManualCorrectionOutcome(
            correction=correction,
            accounts=tuple(
                ManualCorrectionAccountResult(account_id=item, status="recorded")
                for item in request.selected_account_ids
            ),
        )

    async def list_manual_commands(self, request: ManualCommandPageRequest) -> ManualCommandPage:
        if request.account_id == "unavailable":
            raise ValueError("Account is not available for manual trading")
        del request
        return ManualCommandPage.model_validate_json(
            json.dumps(contract("manual-command-page-response.json")["ok"]["commands"])
        )


async def test_private_pipe_routes_a_typed_manual_correction_to_trading(store):
    server = PipeServer(
        SelfTestService(store, SelfTestParser()),
        EngineQueries(store, store.installation.instance_id),
        services(_ManualControl()),
    )
    response = decode(
        await server.handle_line(
            request_line(
                "save_manual_correction",
                "request-1",
                correction={
                    "correction_id": "correction-1",
                    "selected_account_ids": ["paper-local"],
                    "source_id": "discord:demo:message-1",
                    "actor": "operator",
                    "reason": "The reviewed symbol is wrong",
                    "instructions": [
                        {
                            "action": "buy",
                            "symbol": "AAPL",
                            "price": "200.00",
                            "entry_price": None,
                            "fraction": "0.25",
                        }
                    ],
                },
            )
        )
    )

    assert response["ok"]["type"] == "manual_correction"
    assert response["ok"]["correction"]["correction"]["correction_id"] == "correction-1"
    assert response["ok"]["correction"]["accounts"] == [
        {"account_id": "paper-local", "status": "recorded", "reason": None}
    ]


async def test_private_pipe_lists_bounded_source_scoped_manual_command_history(store):
    server = PipeServer(
        SelfTestService(store, SelfTestParser()),
        EngineQueries(store, store.installation.instance_id),
        services(_ManualControl()),
    )
    response = decode(
        await server.handle_line(
            request_line(
                "list_manual_commands",
                "request-command-page",
                account_id="paper",
                source_id="discord:demo:review-8",
                limit=25,
            )
        )
    )
    assert response["ok"]["type"] == "manual_command_page"
    page = response["ok"]["commands"]
    assert page["account_id"] == "paper"
    assert page["source_id"] == "discord:demo:review-8"
    assert page["items"][0]["status"] == "uncertain"

    invalid = decode(
        await server.handle_line(
            request_line(
                "list_manual_commands",
                "request-command-page-unbounded",
                account_id="paper",
                source_id="discord:demo:review-8",
                limit=101,
            )
        )
    )
    assert invalid["error"]["code"] == "invalid_request"

    unavailable = decode(
        await server.handle_line(
            request_line(
                "list_manual_commands",
                "request-command-page-unavailable",
                account_id="unavailable",
                source_id="discord:demo:review-8",
            )
        )
    )
    assert unavailable["error"]["code"] == "unavailable"


async def test_a_correction_that_fails_unexpectedly_is_answered_not_fatal(store):
    """A save that trips on bad local state used to re-raise out of the server and stop the
    engine. It is answered as unavailable, and the server keeps serving."""

    class _Broken(_ManualControl):
        async def save_manual_correction(self, request):
            raise RuntimeError("Manual correction revision evidence is unavailable")

    server = PipeServer(
        SelfTestService(store, SelfTestParser()),
        EngineQueries(store, store.installation.instance_id),
        services(_Broken()),
    )
    response = decode(
        await server.handle_line(
            request_line(
                "save_manual_correction",
                "request-broken",
                correction={
                    "correction_id": "correction-broken",
                    "selected_account_ids": ["paper-local"],
                    "source_id": "discord:demo:message-1",
                    "actor": "operator",
                    "reason": "The reviewed symbol is wrong",
                    "instructions": [
                        {
                            "action": "buy",
                            "symbol": "AAPL",
                            "price": "200.00",
                            "entry_price": None,
                            "fraction": "0.25",
                        }
                    ],
                },
            )
        )
    )
    assert response["error"] == {"code": "unavailable", "reason": "correction_failed"}
    after = decode(await server.handle_line(request_line("get_status", "request-after")))
    assert "ok" in after


_PREVIEW = {
    "preview_id": "preview-1",
    "account_id": "paper",
    "correction_id": "c-1",
    "instruction_index": 0,
}
_CONFIRM = {
    "command_id": "command-1",
    "preview_id": "preview-1",
    "account_id": "paper",
    "actor": "me",
}


class _Refusing:
    """A trading double whose by-hand steps fail the way the test says."""

    def __init__(self, failure: Exception) -> None:
        self.failure = failure

    async def save_manual_correction(self, request):
        raise self.failure

    async def preview_manual_order(self, request):
        raise self.failure

    async def confirm_manual_orders(self, requests):
        raise self.failure

    async def manual_command_result(self, account_id, command_id):
        raise self.failure

    async def list_manual_commands(self, request):
        raise self.failure


async def _ask(store, trading, operation, **values):
    server = PipeServer(
        SelfTestService(store, SelfTestParser()),
        EngineQueries(store, store.installation.instance_id),
        trading,
    )
    return decode(await server.handle_line(request_line(operation, "req-refused", **values)))


async def test_a_refusal_in_the_by_hand_flow_names_its_reason(store):
    refused = await _ask(
        store,
        services(_Refusing(ManualRefusal("preview_missing"))),
        "confirm_manual_orders",
        commands=[_CONFIRM],
    )
    assert refused["error"] == {"code": "unavailable", "reason": "preview_missing"}

    conflict = await _ask(
        store,
        services(_Refusing(ManualRefusal("identity_conflict"))),
        "preview_manual_order",
        preview=_PREVIEW,
    )
    assert conflict["error"] == {"code": "identity_conflict", "reason": "identity_conflict"}

    missing = await _ask(
        store,
        services(_Refusing(ManualRefusal("command_not_found"))),
        "get_manual_command",
        account_id="paper",
        command_id="command-1",
    )
    assert missing["error"] == {"code": "not_found", "reason": "command_not_found"}


async def test_an_unexpected_failure_in_each_step_still_says_which_step(store):
    steps = {
        "preview_manual_order": ({"preview": _PREVIEW}, "preview_failed"),
        "confirm_manual_orders": ({"commands": [_CONFIRM]}, "confirm_failed"),
        "get_manual_command": (
            {"account_id": "paper", "command_id": "command-1"},
            "status_failed",
        ),
        "list_manual_commands": (
            {"account_id": "paper", "source_id": "discord:demo:review-8"},
            "history_failed",
        ),
    }
    for operation, (values, reason) in steps.items():
        for failure in (ValueError("a ledger invariant"), RuntimeError("anything"), KeyError("x")):
            response = await _ask(store, services(_Refusing(failure)), operation, **values)
            assert response["error"]["reason"] == reason, (operation, failure)


async def test_a_by_hand_request_before_copying_starts_says_so(store):
    response = await _ask(store, None, "preview_manual_order", preview=_PREVIEW)
    assert response["error"] == {"code": "unavailable", "reason": "copying_not_started"}
