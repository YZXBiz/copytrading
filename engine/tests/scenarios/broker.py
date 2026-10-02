"""A broker that keeps real books: cash moves with every fill, positions carry their shares, and
an order the account cannot pay for or does not hold is refused, as Alpaca refuses it."""

import datetime as dt
import threading
from decimal import Decimal

from copytrading_engine.execution.adapters.alpaca.models import (
    decode_account,
    decode_asset,
    decode_broker_order,
    decode_calendar,
)
from copytrading_engine.execution.application.ports import BrokerError
from copytrading_engine.execution.domain.market import Position, Quote

CENT = Decimal("0.01")


class SimulatedBroker:
    def __init__(self, name: str, *, cash: str, prices: dict[str, str]) -> None:
        self.name = name
        self.cash = Decimal(cash)
        self.previous_close = Decimal(cash)
        self.prices = {symbol: Decimal(price) for symbol, price in prices.items()}
        self.holdings: dict[str, Decimal] = {}
        self.orders: dict[str, dict] = {}
        self.refused: list[dict] = []
        self.calls = 0
        self._lock = threading.Lock()

    # What the test changes between posts.

    def move(self, symbol: str, price: str) -> None:
        with self._lock:
            self.prices[symbol] = Decimal(price)
            self._fill_resting()

    def hold_outside_the_app(self, symbol: str, qty: str) -> None:
        with self._lock:
            self.holdings[symbol] = self.holdings.get(symbol, Decimal(0)) + Decimal(qty)

    def equity(self) -> Decimal:
        with self._lock:
            return self._equity()

    def submitted(self, side: str | None = None) -> list[dict]:
        with self._lock:
            return [order for order in self.orders.values() if side in (None, order["side"])]

    # The broker port.

    def account(self):
        with self._lock:
            return decode_account(
                {
                    "id": self.name,
                    "status": "ACTIVE",
                    "cash": str(self.cash),
                    "buying_power": str(self.cash),
                    "equity": str(self._equity()),
                    "last_equity": str(self.previous_close),
                    "currency": "USD",
                    "trading_blocked": False,
                    "account_blocked": False,
                    "trade_suspended_by_user": False,
                }
            )

    def asset(self, symbol: str):
        return decode_asset(
            {
                "symbol": symbol,
                "class": "us_equity",
                "status": "active",
                "tradable": True,
                "fractionable": True,
            }
        )

    def calendar(self, date: str):
        return decode_calendar([{"date": date, "open": "09:30", "close": "16:00"}])

    def positions(self):
        with self._lock:
            return tuple(
                Position(
                    symbol=symbol,
                    qty=qty,
                    market_value=(qty * self.prices[symbol]).quantize(CENT),
                    currency="USD",
                    asset_class="us_equity",
                )
                for symbol, qty in self.holdings.items()
                if qty
            )

    def open_orders(self):
        with self._lock:
            return tuple(
                decode_broker_order(order)
                for order in self.orders.values()
                if order["status"] in {"new", "partially_filled"}
            )

    def lookup(self, client_id: str):
        with self._lock:
            order = self.orders.get(client_id)
            return decode_broker_order(order) if order else None

    def quote(self, symbol: str) -> Quote:
        with self._lock:
            price = self.prices[symbol]
            return Quote(feed="iex", bid=price, ask=price + CENT, timestamp=dt.datetime.now(dt.UTC))

    def submit(self, request):
        fields = request.model_dump(mode="json", exclude_none=True)
        with self._lock:
            self.calls += 1
            qty = Decimal(fields["qty"])
            price = self.prices[fields["symbol"]]
            if fields["side"] == "buy" and qty * price > self.cash:
                self.refused.append(fields)
                raise BrokerError(403)  # Alpaca: insufficient buying power
            held = self.holdings.get(fields["symbol"], Decimal(0))
            if fields["side"] == "sell" and qty > held:
                self.refused.append(fields)
                raise BrokerError(403)  # Alpaca: insufficient qty available
            order = {
                **fields,
                "id": f"{self.name}-{self.calls}",
                "filled_qty": "0",
                "filled_avg_price": None,
                "status": "new",
            }
            self.orders[fields["client_order_id"]] = order
            self._try_fill(order)
            return decode_broker_order(order)

    def cancel(self, order_id: str) -> None:
        with self._lock:
            for order in self.orders.values():
                if order["id"] == order_id and order["status"] in {"new", "partially_filled"}:
                    order["status"] = "canceled"

    # Fills.

    def _fill_resting(self) -> None:
        for order in self.orders.values():
            if order["status"] == "new":
                self._try_fill(order)

    def _try_fill(self, order: dict) -> None:
        price = self.prices[order["symbol"]]
        limit = order.get("limit_price")
        if limit is not None:
            if order["side"] == "buy" and price > Decimal(limit):
                return
            if order["side"] == "sell" and price < Decimal(limit):
                return
        qty = Decimal(order["qty"])
        signed = qty if order["side"] == "buy" else -qty
        self.holdings[order["symbol"]] = self.holdings.get(order["symbol"], Decimal(0)) + signed
        self.cash -= (signed * price).quantize(CENT)
        order.update(filled_qty=order["qty"], filled_avg_price=str(price), status="filled")

    def _equity(self) -> Decimal:
        held = sum((qty * self.prices[symbol] for symbol, qty in self.holdings.items()), Decimal(0))
        return (self.cash + held).quantize(CENT)
