"""Each rule an order or a lot sale must keep refuses the one change that breaks it.

Every case starts from a valid value and breaks exactly one rule, so deleting or loosening a
validator fails here even when no flow reaches the broken state today."""

import datetime as dt
from decimal import Decimal

import pytest
from pydantic import ValidationError

from copytrading_engine.execution.domain.lot_sales import (
    LotSaleConfirmation,
    LotSalePreview,
    LotSalePreviewRequest,
    LotSaleRecord,
)
from copytrading_engine.execution.domain.order_lifecycle import OrderStatus
from copytrading_engine.execution.domain.orders import (
    OrderPlan,
    OrderRecord,
    OrderRequest,
    OwnedLot,
)
from copytrading_engine.execution.domain.sessions import Session

NOW = dt.datetime(2026, 10, 20, 14, 0, tzinfo=dt.UTC)

REQUEST = {
    "side": "buy",
    "position_intent": "buy_to_open",
    "type": "limit",
    "limit_price": Decimal(10),
    "symbol": "F",
    "qty": Decimal(1),
    "client_order_id": "client-1",
    "extended_hours": False,
}
MARKET_EXIT = REQUEST | {
    "side": "sell",
    "position_intent": "sell_to_close",
    "type": "market",
    "limit_price": None,
}
BUY = {
    "side": "buy",
    "position_intent": "buy_to_open",
    "type": "limit",
    "limit_price": Decimal(10),
    "symbol": "F",
    "qty": Decimal(2),
    "source_price": Decimal(10),
    "entry_tolerance_pct": Decimal(1),
    "lot_id": None,
    "entry_price": Decimal(10),
    "session": Session.REGULAR,
}
SELL = BUY | {"side": "sell", "position_intent": "sell_to_close", "lot_id": "lot-1"}
RECORD = BUY | {
    "client_id": "client-1",
    "message_id": "message-1",
    "instruction_index": 0,
    "source_key": "source-1",
    "status": OrderStatus.ACCEPTED,
    "filled_qty": Decimal(0),
    "broker_id": "broker-1",
    "created_at": NOW,
    "day": NOW.date(),
}
LOT = {
    "symbol": "F",
    "entry_price": Decimal(10),
    "source_key": "source-1",
    "original_qty": Decimal(2),
    "remaining_qty": Decimal(2),
    "average_price": Decimal(10),
    "entry_remaining": {"source-1": Decimal(2)},
    "entry_prices": {"source-1": Decimal(10)},
}


@pytest.mark.parametrize(
    ("model", "valid", "change", "rule"),
    [
        pytest.param(
            OrderRequest,
            REQUEST,
            {"position_intent": "sell_to_close"},
            "position intent does not match",
            id="request intent against side",
        ),
        pytest.param(
            OrderRequest,
            REQUEST,
            {"limit_price": None},
            "Only limit orders require a limit price",
            id="limit order without price",
        ),
        pytest.param(
            OrderRequest,
            REQUEST,
            {"type": "market", "limit_price": None},
            "Only exits may use market orders",
            id="market buy",
        ),
        pytest.param(
            OrderRequest,
            MARKET_EXIT,
            {"extended_hours": True},
            "Market orders cannot execute in extended hours",
            id="market order after hours",
        ),
        pytest.param(
            OrderPlan,
            SELL,
            {"joins_lot": "lot-2"},
            "Only buys join a lot",
            id="sell joining a lot",
        ),
        pytest.param(
            OrderPlan,
            SELL,
            {"requested_usd": Decimal(100)},
            "Only buys join a lot or carry a requested amount",
            id="sell with a requested amount",
        ),
        pytest.param(
            OrderPlan,
            BUY,
            {"from_entries": ("source-1",)},
            "Only sells take from buys",
            id="buy taking from buys",
        ),
        pytest.param(
            OrderPlan,
            BUY,
            {"session": Session.CLOSED},
            "Cannot prepare an order in a closed session",
            id="order while closed",
        ),
        pytest.param(
            OrderPlan,
            SELL,
            {"type": "market", "limit_price": None, "session": Session.EXTENDED},
            "Market exits require a regular session",
            id="market exit after hours",
        ),
        pytest.param(
            OrderPlan,
            BUY,
            {"lot_id": "lot-1"},
            "Only sells must reference an owned lot",
            id="buy naming a lot",
        ),
        pytest.param(
            OrderPlan,
            SELL,
            {"lot_id": None},
            "Only sells must reference an owned lot",
            id="sell without its lot",
        ),
        pytest.param(
            OrderRecord,
            RECORD,
            {"filled_qty": Decimal(3)},
            "Inconsistent recorded fill quantity",
            id="fill above the order",
        ),
        pytest.param(
            OrderRecord,
            RECORD,
            {"status": OrderStatus.FILLED, "filled_qty": Decimal(1)},
            "Inconsistent recorded fill quantity",
            id="filled with shares missing",
        ),
        pytest.param(
            OrderRecord,
            RECORD,
            {"status": OrderStatus.ABORTED_BEFORE_SUBMIT},
            "aborted before submission cannot have broker activity",
            id="aborted with a broker id",
        ),
        pytest.param(
            OrderRecord,
            RECORD,
            {"status": OrderStatus.UNRECOGNIZED},
            "unrecognized order status must preserve",
            id="unrecognized without its value",
        ),
        pytest.param(
            OrderRecord,
            RECORD,
            {"raw_broker_status": "filled"},
            "Raw broker status does not match",
            id="raw status against status",
        ),
        pytest.param(
            OwnedLot,
            LOT,
            {"remaining_qty": Decimal(3), "entry_remaining": {"source-1": Decimal(3)}},
            "Remaining shares exceed the original lot",
            id="lot above its buys",
        ),
        pytest.param(
            OwnedLot,
            LOT,
            {"entry_remaining": {"source-1": Decimal(1)}},
            "must add up to its remaining shares",
            id="buys not adding up",
        ),
        pytest.param(
            OwnedLot,
            LOT,
            {"entry_prices": {"other": Decimal(10)}},
            "Every buy in a lot has its remaining shares and price",
            id="buy without its price",
        ),
    ],
)
def test_an_order_rule_refuses_the_change_that_breaks_it(model, valid, change, rule):
    model.model_validate(valid)

    with pytest.raises(ValidationError, match=rule):
        model.model_validate(valid | change)


def test_a_whole_share_sale_splits_in_whole_shares_with_the_remainder_from_the_oldest_buy():
    lot = OwnedLot.model_validate(
        LOT
        | {
            "original_qty": Decimal(7),
            "remaining_qty": Decimal(7),
            "joined_entries": ("source-2",),
            "entry_remaining": {"source-1": Decimal(4), "source-2": Decimal(3)},
            "entry_prices": {"source-1": Decimal(10), "source-2": Decimal(11)},
        }
    )

    assert lot.reduced(Decimal(3)).entry_remaining == {"source-1": 2, "source-2": 2}


def test_a_sale_never_takes_more_than_the_lot_holds():
    lot = OwnedLot.model_validate(LOT)

    with pytest.raises(ValueError, match="cannot take more than the buys it sells from hold"):
        lot.reduced(Decimal(3))
    assert lot.reduced(Decimal(2)).remaining_qty == 0


SALE_REQUEST = LotSalePreviewRequest(
    preview_id="preview-1", account_id="paper", lot_id="lot-1", qty=Decimal(2)
)
PREVIEW = {
    "request": SALE_REQUEST,
    "broker_account_id": "PA123",
    "environment": "paper",
    "symbol": "F",
    "lot_remaining_qty": Decimal(2),
    "created_at": NOW,
    "expires_at": NOW + dt.timedelta(minutes=2),
    "session": Session.REGULAR,
    "quote": None,
    "fresh_price": None,
    "plan": OrderPlan.model_validate(SELL),
    "checks": (),
    "reasons": (),
    "facts_sha256": "0" * 64,
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
            {"fresh_price": Decimal(10)}, "requires its quote evidence", id="price without quote"
        ),
        pytest.param({"session": None}, "requires a market session", id="ready without a session"),
        pytest.param(
            {"plan": OrderPlan.model_validate(SELL | {"qty": Decimal(3)})},
            "sell no more than its lot holds",
            id="selling more than asked",
        ),
        pytest.param(
            {"lot_remaining_qty": Decimal(1)},
            "sell no more than its lot holds",
            id="selling more than the lot holds",
        ),
        pytest.param(
            {"plan": OrderPlan.model_validate(SELL | {"symbol": "GM"})},
            "sell no more than its lot holds",
            id="selling another stock",
        ),
        pytest.param(
            {"plan": OrderPlan.model_validate(SELL | {"lot_id": "lot-2"})},
            "sell no more than its lot holds",
            id="selling from another lot",
        ),
    ],
)
def test_a_lot_sale_preview_refuses_a_plan_its_facts_do_not_allow(change, rule):
    LotSalePreview.model_validate(PREVIEW)

    with pytest.raises(ValidationError, match=rule):
        LotSalePreview.model_validate(PREVIEW | change)


CONFIRMATION = LotSaleConfirmation(
    command_id="command-1", preview_id="preview-1", account_id="paper", actor="owner"
)
SALE = {
    "request": CONFIRMATION,
    "lot_id": "lot-1",
    "confirmed_at": NOW,
    "state": "prepared",
    "client_id": "c-1",
}


@pytest.mark.parametrize(
    ("change", "rule"),
    [
        pytest.param(
            {"state": "rejected"},
            "rejected lot sale requires a reason",
            id="rejected without reason",
        ),
        pytest.param(
            {"state": "rejected", "reason": "market_closed"},
            "rejected lot sale requires a reason and no order intent",
            id="rejected with an order",
        ),
        pytest.param(
            {"client_id": None},
            "prepared lot sale requires its order intent",
            id="prepared without order",
        ),
        pytest.param(
            {"reason": "market_closed"}, "prepared lot sale requires", id="prepared with a reason"
        ),
    ],
)
def test_a_lot_sale_record_keeps_its_outcome_and_order_together(change, rule):
    LotSaleRecord.model_validate(SALE)

    with pytest.raises(ValidationError, match=rule):
        LotSaleRecord.model_validate(SALE | change)


def test_a_lot_sale_needs_someone_to_confirm_it():
    with pytest.raises(ValidationError, match="requires an actor"):
        LotSaleConfirmation.model_validate(CONFIRMATION.model_dump() | {"actor": "  "})
