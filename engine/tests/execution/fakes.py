"""Test doubles for execution: an in-memory repository and a scripted broker."""

from decimal import ROUND_HALF_UP, Decimal

from copytrading_engine.execution.adapters.alpaca.models import (
    decode_account,
    decode_asset,
    decode_broker_order,
    decode_calendar,
    decode_positions,
)
from copytrading_engine.execution.application.ports import BrokerError
from copytrading_engine.execution.domain.events import JournalEvent
from copytrading_engine.execution.domain.ledger_state import LedgerSnapshot

COIN = Decimal("0.000000001")


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
        # What Alpaca says an order is when it is sent; it can hold one as pending_new first.
        self.submitted_status = "new"
        self.market_fill_price = "24.50"
        self.crypto_fee_rate = Decimal("0.0025")
        # Symbols Alpaca does not list: asking for one answers 404.
        self.unknown_symbols: set[str] = set()
        # Held positions Alpaca lists at $0: a holding worth under a cent.
        self.zero_valued: set[str] = set()
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
        if "/" in symbol:
            # As Alpaca lists BTC/USD (paper, 23 October 2026).
            return decode_asset(
                {
                    "symbol": symbol,
                    "class": "crypto",
                    "status": "active",
                    "tradable": True,
                    "fractionable": True,
                    "min_order_size": "0.000012307",
                    "min_trade_increment": "0.000000001",
                    "price_increment": "0.000000001",
                }
            )
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
        # Alpaca lists a coin held without its pair's slash (BTCUSD), as the adapter decodes it.
        return decode_positions(
            [
                {
                    "symbol": symbol.replace("/", ""),
                    "qty": str(qty),
                    "market_value": "0" if symbol in self.zero_valued else str(qty * Decimal("25")),
                    "currency": "USD",
                    "asset_class": "crypto" if "/" in symbol else "us_equity",
                }
                for symbol, qty in self.holdings.items()
            ]
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
        received = delta
        if "/" in o["symbol"] and o["side"] == "buy":
            # Alpaca keeps its fee out of the coin bought: 0.25% at tier 1, to the billionth.
            fee = (delta * self.crypto_fee_rate).quantize(COIN, rounding=ROUND_HALF_UP)
            received = delta - fee
        self.holdings[o["symbol"]] = self.holdings.get(o["symbol"], Decimal(0)) + side * received
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
            "status": self.submitted_status,
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
