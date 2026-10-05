"""Bounded HTTP adapter. This module has no live brokerage endpoint."""

import datetime as dt
import re
from collections.abc import Callable, Mapping
from dataclasses import dataclass
from typing import Literal

import httpx
from pydantic import SecretStr, TypeAdapter, ValidationError

from copytrading_engine.execution.adapters.alpaca.models import (
    decode_account,
    decode_asset,
    decode_broker_order,
    decode_calendar,
    decode_orders,
    decode_portfolio_history,
    decode_positions,
    decode_quote,
)
from copytrading_engine.execution.application.ports import (
    BrokerError,
    BrokerResponseError,
    BrokerRestoreEvidence,
    BrokerTimelineEvent,
)
from copytrading_engine.execution.domain.ledger_state import LedgerSnapshot
from copytrading_engine.execution.domain.market import (
    Account,
    Asset,
    BrokerOrder,
    CalendarDay,
    EquityHistory,
    HistoryRange,
    HistoryWindow,
    Position,
    Quote,
    QuoteFeed,
)
from copytrading_engine.execution.domain.orders import OrderRequest
from copytrading_engine.execution.domain.sessions import ET

_ORDERS_PAGE_SIZE = 500
# Alpaca serves intraday points for at most 30 days, so longer ranges use daily points.
_HISTORY_PARAMS: dict[HistoryRange, dict[str, str]] = {
    "day": {"period": "1D", "timeframe": "5Min", "intraday_reporting": "extended_hours"},
    "week": {"period": "1W", "timeframe": "1H", "intraday_reporting": "market_hours"},
    "month": {"period": "1M", "timeframe": "1D"},
    "three_months": {"period": "3M", "timeframe": "1D"},
    "year": {"period": "1A", "timeframe": "1D"},
}
_ACTIVITIES_PAGE_SIZE = 100
_MAX_RESTORE_ORDER_PAGES = 100
_MAX_RESTORE_ACTIVITY_PAGES = 100
_BROKER_TIMESTAMP = re.compile(
    r"^(?P<seconds>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})"
    r"(?P<fraction>\.\d{1,9})?(?P<zone>Z|[+-]\d{2}:\d{2})$"
)

PAPER_URL = "https://paper-api.alpaca.markets"
LIVE_URL = "https://api.alpaca.markets"
Environment = Literal["paper", "live"]


def _timeline_event(identifier: str, timestamp: object) -> BrokerTimelineEvent:
    if not identifier or not isinstance(timestamp, str):
        raise BrokerResponseError()
    match = _BROKER_TIMESTAMP.fullmatch(timestamp)
    if match is None:
        raise BrokerResponseError()
    fraction = match.group("fraction")
    fraction_digits = fraction[1:] if fraction else ""
    fraction_nanoseconds = int(fraction_digits.ljust(9, "0")) if fraction_digits else 0
    microseconds, submicrosecond_nanoseconds = divmod(fraction_nanoseconds, 1_000)
    zone = "+00:00" if match.group("zone") == "Z" else match.group("zone")
    normalized = f"{match.group('seconds')}.{microseconds:06d}{zone}"
    try:
        occurred_at = dt.datetime.fromisoformat(normalized)
    except ValueError:
        raise BrokerResponseError() from None
    if occurred_at.tzinfo is None or occurred_at.utcoffset() is None:
        raise BrokerResponseError()
    resolution_nanoseconds = 10 ** (9 - len(fraction_digits)) if fraction_digits else 1_000_000_000
    try:
        return BrokerTimelineEvent(
            identifier=identifier,
            occurred_at=occurred_at.astimezone(dt.UTC),
            resolution_nanoseconds=resolution_nanoseconds,
            submicrosecond_nanoseconds=submicrosecond_nanoseconds,
        )
    except ValueError:
        raise BrokerResponseError() from None


def _activity_timeline_events(
    identifier: str,
    item: dict[str, object],
) -> tuple[BrokerTimelineEvent, ...]:
    activity_type = item.get("activity_type")
    activity_kind = item.get("type")
    is_trade = activity_type in {"FILL", "PARTIAL_FILL"} or activity_kind in {
        "fill",
        "partial_fill",
    }

    if is_trade:
        precise: list[BrokerTimelineEvent] = []
        for field in ("transaction_time", "created_at"):
            timestamp = item.get(field)
            if timestamp is not None:
                precise.append(_timeline_event(identifier, timestamp))
        if not precise:
            raise BrokerResponseError()
        return tuple(precise)

    # The activity cursor filters on record creation time. For non-trading
    # activities, `date` is an occurrence/settlement date and cannot establish
    # whether the record was created before the snapshot cut.
    created_at = item.get("created_at")
    if created_at is None:
        raise BrokerResponseError()
    return (_timeline_event(identifier, created_at),)


def _order_timeline_events(
    identifier: str,
    status: str,
    raw_order: dict[str, object],
) -> tuple[BrokerTimelineEvent, ...]:
    events: list[BrokerTimelineEvent] = []
    for field in ("created_at", "submitted_at", "updated_at"):
        events.append(_timeline_event(identifier, raw_order.get(field)))

    terminal_time_by_status = {
        "filled": "filled_at",
        "canceled": "canceled_at",
        "cancelled": "canceled_at",
        "expired": "expired_at",
        "rejected": "failed_at",
        "failed": "failed_at",
        "replaced": "replaced_at",
    }
    required_terminal_time = terminal_time_by_status.get(status.lower())
    terminal_fields = (
        "filled_at",
        "expired_at",
        "canceled_at",
        "failed_at",
        "replaced_at",
    )
    if required_terminal_time is not None and raw_order.get(required_terminal_time) is None:
        raise BrokerResponseError()
    for field in terminal_fields:
        timestamp = raw_order.get(field)
        if timestamp is not None:
            events.append(_timeline_event(identifier, timestamp))
    return tuple(events)


def quote_feed(now: dt.datetime) -> QuoteFeed:
    """Alpaca's overnight venue quotes from 20:00 to 4:00 New York time; at those hours IEX still
    shows the last close, so a price read from it would be hours old."""
    hour = now.astimezone(ET).hour
    return "overnight" if hour >= 20 or hour < 4 else "iex"


@dataclass(frozen=True, slots=True)
class AlpacaCredentials:
    key: SecretStr
    secret: SecretStr

    def __post_init__(self) -> None:
        if not self.key.get_secret_value() or not self.secret.get_secret_value():
            raise ValueError("Alpaca credentials are required")


class AlpacaBroker:
    def __init__(
        self,
        credentials: AlpacaCredentials,
        environment: Environment,
        *,
        transport: httpx.BaseTransport | None = None,
        clock: Callable[[], dt.datetime] = lambda: dt.datetime.now(dt.UTC),
    ) -> None:
        if environment not in {"paper", "live"}:
            raise ValueError("Choose Alpaca paper or live explicitly")
        self.http = httpx.Client(
            base_url=PAPER_URL if environment == "paper" else LIVE_URL,
            headers={
                "APCA-API-KEY-ID": credentials.key.get_secret_value(),
                "APCA-API-SECRET-KEY": credentials.secret.get_secret_value(),
            },
            timeout=10,
            follow_redirects=False,
            transport=transport,
        )
        self.environment = environment
        self.now = clock

    def close(self) -> None:
        self.http.close()

    def request(
        self,
        method: str,
        path: str,
        *,
        params: Mapping[str, str | int] | None = None,
        json: object = None,
    ) -> object:
        try:
            response = self.http.request(method, path, params=params, json=json)
        except httpx.HTTPError:
            raise BrokerError() from None
        if response.is_error or response.is_redirect:
            raise BrokerError(response.status_code)
        if response.status_code == 204:
            return None
        try:
            return response.json()
        except ValueError:
            raise BrokerResponseError() from None

    @staticmethod
    def decode[T](model: type[T], value: object) -> T:
        try:
            return TypeAdapter(model).validate_python(value)
        except ValidationError, TypeError:
            raise BrokerResponseError() from None

    @staticmethod
    def decode_normalized[T](decoder: Callable[[object], T], value: object) -> T:
        try:
            return decoder(value)
        except ValidationError, TypeError:
            raise BrokerResponseError() from None

    def account(self) -> Account:
        return self.decode_normalized(decode_account, self.request("GET", "/v2/account"))

    def equity_history(self, window: HistoryWindow) -> EquityHistory:
        params: dict[str, str | int] = dict(_HISTORY_PARAMS[window.range])
        if window.day is not None:
            # With a period, Alpaca starts the chosen day's session at its first timestamp.
            params["start"] = dt.datetime.combine(window.day, dt.time(), ET).isoformat()
        return self.decode_normalized(
            lambda value: decode_portfolio_history(value, window),
            self.request("GET", "/v2/account/portfolio/history", params=params),
        )

    def asset(self, symbol: str) -> Asset:
        return self.decode_normalized(
            decode_asset,
            self.request("GET", f"/v2/assets/{symbol}"),
        )

    def calendar(self, date: str) -> tuple[CalendarDay, ...]:
        return self.decode_normalized(
            decode_calendar,
            self.request("GET", "/v2/calendar", params={"start": date, "end": date}),
        )

    def positions(self) -> tuple[Position, ...]:
        # Alpaca's position response may omit currency; the freshly decoded
        # account provides the valuation unit, while an explicit position unit wins.
        currency = self.account().currency
        result = self.decode_normalized(
            lambda value: decode_positions(value, account_currency=currency),
            self.request("GET", "/v2/positions"),
        )
        if len({position.symbol for position in result}) != len(result):
            raise BrokerResponseError()
        return result

    def open_orders(self) -> tuple[BrokerOrder, ...]:
        return self.decode_normalized(
            decode_orders,
            self.request("GET", "/v2/orders", params={"status": "open", "limit": 500}),
        )

    def restore_evidence(
        self,
        snapshot: LedgerSnapshot,
        created_at: dt.datetime,
    ) -> BrokerRestoreEvidence:
        """Collect read-only broker facts needed to reconcile a restored snapshot.

        Historical terminal orders remain validated archive evidence. Fresh order
        lookups are limited to buys backing currently open owned lots; querying all
        terminal history would make old archives depend on broker retention and
        produce work proportional to every order the account ever placed.
        """
        if created_at.tzinfo is None or created_at.utcoffset() is None:
            raise ValueError("Restore snapshot time must be timezone-aware")

        account = self.account()
        positions = self.decode_normalized(
            lambda value: decode_positions(value, account_currency=account.currency),
            self.request("GET", "/v2/positions"),
        )
        if len({position.symbol for position in positions}) != len(positions):
            raise BrokerResponseError()
        open_orders = self.open_orders()
        if len(open_orders) >= _ORDERS_PAGE_SIZE:
            raise BrokerResponseError()

        known_orders: dict[str, BrokerOrder] = {}
        for lot_id, lot in snapshot.lots.items():
            if lot.remaining_qty <= 0:
                continue
            for entry in lot.entries(lot_id):
                found = self.lookup(entry)
                if found is None:
                    raise BrokerResponseError()
                known_orders[entry] = found

        order_events = self._orders_after(created_at)
        activity_events = self._activity_events_after(created_at)
        return BrokerRestoreEvidence(
            account=account,
            environment=self.environment,
            positions={position.symbol: position.qty for position in positions},
            open_order_client_ids=tuple(order.client_order_id for order in open_orders),
            known_orders=known_orders,
            snapshot_started_at=created_at.astimezone(dt.UTC),
            order_events_near_snapshot=order_events,
            activity_events_near_snapshot=activity_events,
            complete=True,
        )

    def _orders_after(self, created_at: dt.datetime) -> tuple[BrokerTimelineEvent, ...]:
        params: dict[str, str | int] = {
            "status": "all",
            "limit": _ORDERS_PAGE_SIZE,
            "after": (created_at - dt.timedelta(seconds=1)).isoformat(),
            "direction": "asc",
        }
        observed: list[BrokerTimelineEvent] = []
        seen: set[str] = set()
        for _ in range(_MAX_RESTORE_ORDER_PAGES):
            raw_page = self.request("GET", "/v2/orders", params=params)
            page = self.decode_normalized(
                decode_orders,
                raw_page,
            )
            if not isinstance(raw_page, list) or len(raw_page) != len(page):
                raise BrokerResponseError()
            for raw_order, order in zip(raw_page, page, strict=True):
                if order.id in seen:
                    raise BrokerResponseError()
                seen.add(order.id)
                if not isinstance(raw_order, dict):
                    raise BrokerResponseError()
                observed.extend(_order_timeline_events(order.id, order.status, raw_order))
            if len(page) < _ORDERS_PAGE_SIZE:
                return tuple(observed)
            cursor = page[-1].id
            params = {
                "status": "all",
                "limit": _ORDERS_PAGE_SIZE,
                "direction": "asc",
                "after_order_id": cursor,
            }
        raise BrokerResponseError()

    def _activity_events_after(self, created_at: dt.datetime) -> tuple[BrokerTimelineEvent, ...]:
        params: dict[str, str | int] = {
            "after": (created_at - dt.timedelta(seconds=1)).isoformat(),
            "direction": "asc",
            "page_size": _ACTIVITIES_PAGE_SIZE,
        }
        observed: list[BrokerTimelineEvent] = []
        seen: set[str] = set()
        for _ in range(_MAX_RESTORE_ACTIVITY_PAGES):
            result = self.request("GET", "/v2/account/activities", params=params)
            if not isinstance(result, list):
                raise BrokerResponseError()
            page: list[BrokerTimelineEvent] = []
            for item in result:
                if not isinstance(item, dict) or not isinstance(item.get("id"), str):
                    raise BrokerResponseError()
                activity_id = item["id"]
                if not activity_id or activity_id in seen:
                    raise BrokerResponseError()
                seen.add(activity_id)
                page.extend(_activity_timeline_events(activity_id, item))
            observed.extend(page)
            if len(page) < _ACTIVITIES_PAGE_SIZE:
                return tuple(observed)
            params["page_token"] = page[-1].identifier
        raise BrokerResponseError()

    def lookup(self, client_id: str) -> BrokerOrder | None:
        try:
            result = self.request(
                "GET", "/v2/orders:by_client_order_id", params={"client_order_id": client_id}
            )
        except BrokerError as exc:
            if exc.status == 404:
                return None
            raise
        return self.decode_normalized(decode_broker_order, result)

    def quote(self, symbol: str) -> Quote:
        feed = quote_feed(self.now())
        result = self.request(
            "GET",
            f"https://data.alpaca.markets/v2/stocks/{symbol}/quotes/latest",
            params={"feed": feed},
        )
        return self.decode_normalized(lambda value: decode_quote(value, feed), result)

    def submit(self, order: OrderRequest) -> BrokerOrder:
        # Never retry a POST: a timeout or malformed response can follow acceptance.
        return self.decode_normalized(
            decode_broker_order,
            self.request(
                "POST", "/v2/orders", json=order.model_dump(mode="json", exclude_none=True)
            ),
        )

    def cancel(self, order_id: str) -> None:
        self.request("DELETE", f"/v2/orders/{order_id}")
