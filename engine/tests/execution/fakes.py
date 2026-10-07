"""Test doubles for execution: an in-memory repository and a scripted broker."""

from decimal import Decimal

from copytrading_engine.execution.adapters.alpaca.models import (
    decode_account,
    decode_asset,
    decode_broker_order,
    decode_calendar,
)
from copytrading_engine.execution.application.ports import BrokerError
from copytrading_engine.execution.domain.events import JournalEvent
from copytrading_engine.execution.domain.ledger_state import LedgerSnapshot
from copytrading_engine.execution.domain.market import Position


class MemoryRepository:
    def __init__(self, snapshot_json: str | None = None):
        self.snapshot_json = snapshot_json
        self.events: list[JournalEvent] = []
        self.fail_commit = False
        self.fail_event: str | None = None

    def load(self) -> LedgerSnapshot:
        return (
            LedgerSnapshot.model_validate_json(self.snapshot_json)
            if self.snapshot_json
            else LedgerSnapshot()
        )

    def save(self, snapshot: LedgerSnapshot, event: JournalEvent) -> None:
        if self.fail_commit or event.payload.kind == self.fail_event:
            raise RuntimeError("simulated persistence failure")
        self.snapshot_json = snapshot.model_dump_json()
        self.events.append(event)


class FakeBroker:
    def __init__(self):
        self.orders = {}
        self.holdings = {}
        self.calls = 0
        self.timeout_after_accept = False
        self.auto_fill = True
        self.market_fill_price = "24.50"
        # Symbols Alpaca does not list: asking for one answers 404.
        self.unknown_symbols: set[str] = set()
        self.account_data = {
            "id": "paper-demo",
            "status": "ACTIVE",
            "cash": "5000",
            "equity": "5000",
            "last_equity": "5000",
            "buying_power": "5000",
            "currency": "USD",
            "trading_blocked": False,
            "account_blocked": False,
            "trade_suspended_by_user": False,
        }

    def account(self):
        return decode_account(self.account_data)

    def asset(self, symbol):
        if symbol in self.unknown_symbols:
            raise BrokerError(404)
        return decode_asset(
            {
                "symbol": symbol,
                "class": "us_equity",
                "status": "active",
                "tradable": True,
                "fractionable": True,
            }
        )

    def calendar(self, date):
        return decode_calendar([{"date": date, "open": "09:30", "close": "16:00"}])

    def positions(self):
        return tuple(
            Position(
                symbol=symbol,
                qty=qty,
                market_value=qty * Decimal("25"),
                currency="USD",
                asset_class="us_equity",
            )
            for symbol, qty in self.holdings.items()
        )

    def open_orders(self):
        return tuple(
            decode_broker_order(o)
            for o in self.orders.values()
            if o["status"] not in {"filled", "canceled", "rejected", "expired"}
        )

    def lookup(self, client_id):
        o = self.orders.get(client_id)
        return decode_broker_order(o) if o else None

    def fill(self, client_id, qty):
        o = self.orders[client_id]
        delta = Decimal(qty) - Decimal(o["filled_qty"])
        side = 1 if o["side"] == "buy" else -1
        self.holdings[o["symbol"]] = self.holdings.get(o["symbol"], Decimal(0)) + side * delta
        o.update(
            filled_qty=str(qty),
            filled_avg_price=o.get("limit_price") or self.market_fill_price,
            status="filled" if Decimal(qty) == Decimal(o["qty"]) else "partially_filled",
        )

    def submit(self, order):
        request = order.model_dump(mode="json", exclude_none=True)
        self.calls += 1
        cid = request["client_order_id"]
        self.orders[cid] = {
            **request,
            "id": f"broker-{self.calls}",
            "filled_qty": "0",
            "status": "new",
            "filled_avg_price": None,
        }
        if self.auto_fill:
            self.fill(cid, request["qty"])
        if self.timeout_after_accept:
            raise BrokerError()
        return decode_broker_order(self.orders[cid])

    def cancel(self, order_id):
        for order in self.orders.values():
            if order["id"] == order_id:
                order["status"] = "canceled"
