"""Each rule a by-hand order, a manual sale, or an order incident must keep refuses the one change
that breaks it, starting from a valid value."""

import datetime as dt
from decimal import Decimal

import pytest
from pydantic import ValidationError

from copytrading_engine.execution.domain.manual_commands import (
    ManualAccountCommandResult,
    ManualCommandRecord,
    ManualCommandResult,
    ManualConfirmationRequest,
    ManualCorrectionRequest,
    ManualOrderPreview,
    ManualPreviewRequest,
    ManualSourceEvidence,
)
from copytrading_engine.execution.domain.market import BrokerOrder
from copytrading_engine.execution.domain.order_lifecycle import OrderStatus
from copytrading_engine.execution.domain.orders import OrderPlan
from copytrading_engine.execution.domain.recovery import (
    IncidentClearanceEvidence,
    LateOrderIncident,
    ManualSale,
    QuarantinedFill,
)
from copytrading_engine.execution.domain.sessions import Session
from copytrading_engine.shared.signals import StockSignal

from .builders import NOW, event


def refuses(model, valid, change, rule):
    model.model_validate(valid)
    with pytest.raises(ValidationError, match=rule):
        model.model_validate(valid | change)


SIGNAL = StockSignal.model_validate(event("post-1"))
INSTRUCTION = SIGNAL.instructions[0]
PLAN = OrderPlan.model_validate(
    {
        "side": "buy",
        "position_intent": "buy_to_open",
        "type": "limit",
        "limit_price": Decimal(25),
        "symbol": "ABC",
        "qty": Decimal(4),
        "source_price": Decimal(25),
        "entry_tolerance_pct": Decimal(1),
        "lot_id": None,
        "entry_price": Decimal(25),
        "session": Session.REGULAR,
    }
)
PREVIEW = {
    "request": ManualPreviewRequest(
        preview_id="preview-1",
        account_id="paper",
        correction_id="correction-1",
        instruction_index=0,
    ),
    "broker_account_id": "PA123",
    "environment": "paper",
    "correction_revision": 1,
    "source_at": NOW,
    "source_age_seconds": 30,
    "instruction": INSTRUCTION,
    "created_at": NOW,
    "expires_at": NOW + dt.timedelta(minutes=2),
    "session": Session.REGULAR,
    "quote": None,
    "fresh_price": None,
    "plan": PLAN,
    "checks": (),
    "reasons": (),
    "facts_sha256": "0" * 64,
    "configuration_sha256": "1" * 64,
}


@pytest.mark.parametrize(
    ("change", "rule"),
    [
        pytest.param(
            {"plan": None}, "plan must agree with its blocking reasons", id="no plan, no reason"
        ),
        pytest.param(
            {"reasons": ("market_closed",)}, "plan must agree", id="plan despite a reason"
        ),
        pytest.param(
            {"expires_at": NOW}, "expiration must follow its creation", id="expired at birth"
        ),
        pytest.param(
            {"fresh_price": Decimal(25)}, "requires its quote evidence", id="price without quote"
        ),
        pytest.param({"session": None}, "requires a market session", id="ready without a session"),
    ],
)
def test_a_manual_preview_refuses_a_plan_its_facts_do_not_allow(change, rule):
    refuses(ManualOrderPreview, PREVIEW, change, rule)


CONFIRMATION = ManualConfirmationRequest(
    command_id="command-1", preview_id="preview-1", account_id="paper", actor="owner"
)
COMMAND = {
    "request": CONFIRMATION,
    "correction_id": "correction-1",
    "source_id": "discord:demo:post-1",
    "instruction_index": 0,
    "confirmed_at": NOW,
    "state": "prepared",
    "client_id": "client-1",
}


@pytest.mark.parametrize(
    ("change", "rule"),
    [
        pytest.param(
            {"state": "rejected"},
            "Rejected manual command requires a reason",
            id="rejected without reason",
        ),
        pytest.param(
            {"state": "rejected", "reason": "market_closed"},
            "requires a reason and no order intent",
            id="rejected with an order",
        ),
        pytest.param(
            {"client_id": None},
            "Prepared manual command requires its order intent",
            id="prepared without order",
        ),
        pytest.param(
            {"reason": "market_closed"},
            "Prepared manual command requires",
            id="prepared with a reason",
        ),
    ],
)
def test_a_manual_command_keeps_its_outcome_and_order_together(change, rule):
    refuses(ManualCommandRecord, COMMAND, change, rule)


def test_a_manual_order_needs_someone_to_confirm_it():
    refuses(
        ManualConfirmationRequest, CONFIRMATION.model_dump(), {"actor": " "}, "requires an actor"
    )


RESULT = ManualCommandResult(command=ManualCommandRecord.model_validate(COMMAND), status="prepared")
ACCOUNT_RESULT = {"account_id": "paper", "command_id": "command-1", "result": RESULT}


@pytest.mark.parametrize(
    ("change", "rule"),
    [
        pytest.param({"error": "confirm_failed"}, "exactly one outcome", id="result and error"),
        pytest.param({"result": None}, "exactly one outcome", id="neither"),
        pytest.param(
            {"account_id": "live"}, "belongs to another account", id="another account's result"
        ),
    ],
)
def test_an_account_answers_a_manual_order_once_and_for_itself(change, rule):
    refuses(ManualAccountCommandResult, ACCOUNT_RESULT, change, rule)


CORRECTION = {
    "correction_id": "correction-1",
    "source_id": "discord:demo:post-1",
    "selected_account_ids": ("live", "paper"),
    "actor": "owner",
    "reason": "misread",
    "instructions": (INSTRUCTION,),
}


@pytest.mark.parametrize(
    ("change", "rule"),
    [
        pytest.param({"actor": " "}, "requires an actor and reason", id="no actor"),
        pytest.param({"reason": " "}, "requires an actor and reason", id="no reason"),
        pytest.param(
            {"selected_account_ids": ("paper", "live")}, "unique and sorted", id="unsorted accounts"
        ),
        pytest.param(
            {"selected_account_ids": ("paper", "paper")}, "unique and sorted", id="repeated account"
        ),
    ],
)
def test_a_correction_names_who_made_it_why_and_each_account_once(change, rule):
    refuses(ManualCorrectionRequest, CORRECTION, change, rule)


IGNORED = StockSignal.model_validate(
    event("post-1") | {"decision": "ignore", "reason": "chat", "instructions": [], "evidence": []}
)
SOURCE = {
    "source_id": "discord:demo:post-1",
    "source_revision": 1,
    "source_at": SIGNAL.timestamp,
    "text": SIGNAL.text,
    "accepted_interpretation": SIGNAL,
}


@pytest.mark.parametrize(
    ("change", "rule"),
    [
        pytest.param(
            {"source_id": "discord:demo:post-2"},
            "differs from its accepted interpretation",
            id="other post",
        ),
        pytest.param(
            {"text": "edited"}, "differs from its accepted interpretation", id="edited text"
        ),
        pytest.param(
            {"source_at": SIGNAL.timestamp + dt.timedelta(seconds=1)},
            "differs from its accepted interpretation",
            id="other time",
        ),
        pytest.param(
            {"accepted_interpretation": IGNORED},
            "An ignored post has nothing to copy",
            id="ignored post",
        ),
    ],
)
def test_a_correction_copies_only_the_post_it_was_made_for(change, rule):
    refuses(ManualSourceEvidence, SOURCE, change, rule)


SOLD = BrokerOrder(
    id="broker-1",
    client_order_id="client-1",
    symbol="ABC",
    side="sell",
    qty=Decimal(2),
    filled_qty=Decimal(2),
    filled_avg_price=Decimal(26),
    status="filled",
)
SALE = {"order": SOLD, "filled_at": NOW, "recorded_at": NOW, "reason": "sold_in_alpaca"}


@pytest.mark.parametrize(
    ("change", "rule"),
    [
        pytest.param(
            {"order": SOLD.model_copy(update={"side": "buy"})},
            "requires a fully filled sell",
            id="a buy",
        ),
        pytest.param(
            {"order": SOLD.model_copy(update={"status": "new", "filled_qty": Decimal(0)})},
            "requires a fully filled sell",
            id="not filled",
        ),
        pytest.param(
            {"filled_at": NOW + dt.timedelta(seconds=1)},
            "filled before it is recorded",
            id="recorded first",
        ),
    ],
)
def test_a_manual_sale_records_only_a_filled_sell_after_it_filled(change, rule):
    refuses(ManualSale, SALE, change, rule)


CLEARANCE = IncidentClearanceEvidence(
    actor="owner", reason="checked", checked_at=NOW, account_id="paper", matched_audit_ref="audit-1"
)
INCIDENT = {
    "client_id": "client-1",
    "broker_id": "broker-1",
    "symbol": "ABC",
    "side": "buy",
    "first_observed_at": NOW,
    "last_observed_at": NOW,
    "latest_status": OrderStatus.NEW,
    "raw_broker_status": "new",
    "latest_filled_qty": Decimal(0),
}


@pytest.mark.parametrize(
    ("change", "rule"),
    [
        pytest.param(
            {"last_observed_at": NOW - dt.timedelta(seconds=1)},
            "cannot move backwards",
            id="time backwards",
        ),
        pytest.param(
            {"cleared": True}, "requires clearance evidence", id="cleared without evidence"
        ),
        pytest.param(
            {"conflicting_order_ids": ("client-2", "client-2")},
            "must be unique",
            id="repeated conflict",
        ),
        pytest.param(
            {"conflicting_order_ids": ("client-1",)},
            "cannot conflict with itself",
            id="conflicts itself",
        ),
        pytest.param(
            {
                "clearance_history": (
                    CLEARANCE,
                    CLEARANCE.model_copy(update={"checked_at": NOW - dt.timedelta(minutes=1)}),
                )
            },
            "must be chronological",
            id="clearances out of order",
        ),
    ],
)
def test_a_late_order_incident_stays_consistent(change, rule):
    refuses(LateOrderIncident, INCIDENT, change, rule)


@pytest.mark.parametrize(
    ("change", "rule"),
    [
        pytest.param(
            {"matched_audit_ref": None},
            "requires a matched audit reference or quantities",
            id="no evidence",
        ),
        pytest.param(
            {"symbol": "ABC", "expected_qty": Decimal(2), "broker_qty": Decimal(1)},
            "requires equal expected and broker quantities",
            id="quantities differ",
        ),
        pytest.param(
            {"symbol": "ABC"}, "requires equal expected and broker quantities", id="symbol alone"
        ),
    ],
)
def test_clearing_an_incident_needs_matching_evidence(change, rule):
    refuses(IncidentClearanceEvidence, CLEARANCE.model_dump(), change, rule)


QUARANTINE = {
    "client_id": "client-1",
    "broker_id": "broker-1",
    "lot_id": "lot-1",
    "symbol": "ABC",
    "observed_filled_qty": Decimal(3),
    "applied_filled_qty": Decimal(2),
    "unapplied_qty": Decimal(1),
    "average_price": Decimal(26),
    "first_observed_at": NOW,
    "last_observed_at": NOW,
    "incident_client_ids": ("client-1",),
}


@pytest.mark.parametrize(
    ("change", "rule"),
    [
        pytest.param(
            {"unapplied_qty": Decimal(2)}, "do not match the broker observation", id="shares lost"
        ),
        pytest.param(
            {"last_observed_at": NOW - dt.timedelta(seconds=1)},
            "cannot move backwards",
            id="time backwards",
        ),
        pytest.param(
            {"incident_client_ids": ()}, "requires associated incidents", id="no incident"
        ),
        pytest.param(
            {"incident_client_ids": ("client-1", "client-1")},
            "must be unique",
            id="repeated incident",
        ),
    ],
)
def test_a_quarantined_fill_accounts_for_every_share(change, rule):
    refuses(QuarantinedFill, QUARANTINE, change, rule)
