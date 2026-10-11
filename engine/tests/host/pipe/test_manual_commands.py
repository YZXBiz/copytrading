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
    assert response["error"]["code"] == "unavailable"
    after = decode(await server.handle_line(request_line("get_status", "request-after")))
    assert "ok" in after
