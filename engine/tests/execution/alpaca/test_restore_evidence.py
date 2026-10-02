"""Restore evidence reads only, pages within budget, and fails closed at the cut."""

import datetime as dt
from decimal import Decimal

import httpx
import pytest

from copytrading_engine.execution.application.ports import BrokerError

from .builders import make_broker


def test_restore_evidence_uses_only_get_requests(tmp_path):

    from copytrading_engine.execution.domain.ledger_state import LedgerSnapshot

    account = {
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
    requests = []

    def handler(request):
        requests.append(request)
        if request.url.path == "/v2/account":
            return httpx.Response(200, json=account)
        if request.url.path == "/v2/positions":
            return httpx.Response(200, json=[])
        if request.url.path == "/v2/orders":
            return httpx.Response(200, json=[])
        assert request.url.path == "/v2/account/activities"
        return httpx.Response(200, json=[])

    broker = make_broker("key", "secret", transport=httpx.MockTransport(handler))
    try:
        snapshot = LedgerSnapshot(account_id="paper-demo", environment="paper")
        evidence = broker.restore_evidence(snapshot, dt.datetime.now(dt.UTC))
        assert evidence.complete
        assert evidence.positions == {}
        assert all(request.method == "GET" for request in requests)
        assert any(request.url.path == "/v2/account/activities" for request in requests)
    finally:
        broker.close()


def test_restore_evidence_requests_a_conservative_overlap_before_the_snapshot_cut():

    cutoff = dt.datetime(2026, 9, 27, 16, 30, 0, 500_000, tzinfo=dt.UTC)
    requests = []
    broker = make_broker(
        "key",
        "secret",
        transport=httpx.MockTransport(
            lambda request: requests.append(request) or httpx.Response(200, json=[])
        ),
    )
    try:
        broker._orders_after(cutoff)
        broker._activity_events_after(cutoff)
        expected = (cutoff - dt.timedelta(seconds=1)).isoformat()
        assert [request.url.params["after"] for request in requests] == [expected, expected]
        assert all(request.method == "GET" for request in requests)
    finally:
        broker.close()


def test_restore_evidence_includes_order_and_activity_at_exact_snapshot_timestamp():

    from copytrading_engine.execution.domain.ledger_state import LedgerSnapshot

    cutoff = dt.datetime(2026, 9, 27, 16, 30, 0, tzinfo=dt.UTC)
    account = {
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
    exact_cut_order = {
        "id": "order-at-cut",
        "client_order_id": "client-at-cut",
        "symbol": "AAPL",
        "side": "buy",
        "qty": "1",
        "filled_qty": "1",
        "filled_avg_price": "200",
        "status": "filled",
        "position_intent": "buy_to_open",
        "created_at": cutoff.isoformat(),
        "submitted_at": cutoff.isoformat(),
        "updated_at": cutoff.isoformat(),
        "filled_at": cutoff.isoformat(),
    }
    requests = []

    def handler(request):
        requests.append(request)
        if request.url.path == "/v2/account":
            return httpx.Response(200, json=account)
        if request.url.path == "/v2/positions":
            return httpx.Response(200, json=[])
        if request.url.path == "/v2/orders":
            if request.url.params.get("status") == "all":
                if request.url.params["after"] >= cutoff.isoformat():
                    return httpx.Response(200, json=[])
                return httpx.Response(200, json=[exact_cut_order])
            return httpx.Response(200, json=[])
        assert request.url.path == "/v2/account/activities"
        if request.url.params["after"] >= cutoff.isoformat():
            return httpx.Response(200, json=[])
        return httpx.Response(
            200,
            json=[
                {
                    "id": "activity-at-cut",
                    "activity_type": "FILL",
                    "created_at": cutoff.isoformat(),
                    "transaction_time": cutoff.isoformat(),
                }
            ],
        )

    broker = make_broker("key", "secret", transport=httpx.MockTransport(handler))
    try:
        evidence = broker.restore_evidence(
            LedgerSnapshot(account_id="paper-demo", environment="paper"), cutoff
        )
        assert evidence.orders_after_snapshot == ("order-at-cut",)
        assert evidence.activity_ids_after_snapshot == ("activity-at-cut",)
        assert evidence.order_events_near_snapshot[0].occurred_at == cutoff
        assert evidence.activity_events_near_snapshot[0].occurred_at == cutoff
        expected_after = (cutoff - dt.timedelta(seconds=1)).isoformat()
        after_params = [
            request.url.params["after"]
            for request in requests
            if (
                request.url.path in {"/v2/orders", "/v2/account/activities"}
                and request.url.params.get("status") == "all"
            )
            or request.url.path == "/v2/account/activities"
        ]
        assert all(value == expected_after for value in after_params)
    finally:
        broker.close()


def test_restore_evidence_filters_overlap_events_by_the_exact_snapshot_cut():

    from copytrading_engine.execution.domain.ledger_state import LedgerSnapshot

    cutoff = dt.datetime(2026, 9, 27, 16, 30, 0, 500_000, tzinfo=dt.UTC)
    account = {
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
    before_cut = cutoff - dt.timedelta(milliseconds=500)

    def handler(request):
        if request.url.path == "/v2/account":
            return httpx.Response(200, json=account)
        if request.url.path in {"/v2/positions", "/v2/orders"}:
            if request.url.path == "/v2/orders" and request.url.params.get("status") == "all":
                return httpx.Response(
                    200,
                    json=[
                        {
                            "id": "order-before-cut",
                            "client_order_id": "client-before-cut",
                            "symbol": "AAPL",
                            "side": "buy",
                            "qty": "1",
                            "filled_qty": "1",
                            "filled_avg_price": "200",
                            "status": "filled",
                            "created_at": before_cut.isoformat(timespec="microseconds"),
                            "submitted_at": before_cut.isoformat(timespec="microseconds"),
                            "updated_at": before_cut.isoformat(timespec="microseconds"),
                            "filled_at": before_cut.isoformat(timespec="microseconds"),
                        }
                    ],
                )
            return httpx.Response(200, json=[])
        assert request.url.path == "/v2/account/activities"
        return httpx.Response(
            200,
            json=[
                {
                    "id": "activity-before-cut",
                    "activity_type": "FILL",
                    "created_at": before_cut.isoformat(timespec="microseconds"),
                    "transaction_time": before_cut.isoformat(timespec="microseconds"),
                }
            ],
        )

    broker = make_broker("key", "secret", transport=httpx.MockTransport(handler))
    try:
        evidence = broker.restore_evidence(
            LedgerSnapshot(account_id="paper-demo", environment="paper"), cutoff
        )
        assert evidence.orders_after_snapshot == ()
        assert evidence.activity_ids_after_snapshot == ()
        assert evidence.order_events_near_snapshot[0].occurred_at == before_cut
        assert evidence.order_events_near_snapshot[0].resolution_nanoseconds == 1_000
        assert evidence.activity_events_near_snapshot[0].occurred_at == before_cut
        assert evidence.activity_events_near_snapshot[0].resolution_nanoseconds == 1_000
    finally:
        broker.close()


@pytest.mark.parametrize(
    ("path", "payload"),
    [
        (
            "/v2/orders",
            [
                {
                    "id": "order-missing-time",
                    "client_order_id": "client-missing-time",
                    "symbol": "AAPL",
                    "side": "buy",
                    "qty": "1",
                    "filled_qty": "0",
                    "filled_avg_price": None,
                    "status": "new",
                }
            ],
        ),
        ("/v2/account/activities", [{"id": "activity-missing-time"}]),
    ],
)
def test_restore_evidence_fails_closed_when_broker_event_timestamp_is_missing(path, payload):

    from copytrading_engine.execution.application.ports import BrokerResponseError

    broker = make_broker(
        "key",
        "secret",
        transport=httpx.MockTransport(lambda request: httpx.Response(200, json=payload)),
    )
    try:
        read = broker._orders_after if path == "/v2/orders" else broker._activity_events_after
        with pytest.raises(BrokerResponseError):
            read(dt.datetime(2026, 9, 27, tzinfo=dt.UTC))
    finally:
        broker.close()


def test_restore_evidence_preserves_second_precision_as_an_ambiguous_interval():

    cutoff = dt.datetime(2026, 9, 27, 16, 30, 0, 500_000, tzinfo=dt.UTC)
    broker = make_broker(
        "key",
        "secret",
        transport=httpx.MockTransport(
            lambda _: httpx.Response(
                200,
                json=[
                    {
                        "id": "order-coarse-time",
                        "client_order_id": "client-coarse-time",
                        "symbol": "AAPL",
                        "side": "buy",
                        "qty": "1",
                        "filled_qty": "0",
                        "filled_avg_price": None,
                        "status": "new",
                        "created_at": "2026-09-27T16:30:00Z",
                        "submitted_at": "2026-09-27T16:30:00Z",
                        "updated_at": "2026-09-27T16:30:00Z",
                    }
                ],
            )
        ),
    )
    try:
        event = broker._orders_after(cutoff)[0]
        assert event.resolution_nanoseconds == 1_000_000_000
        assert event.overlaps_or_follows(cutoff)
    finally:
        broker.close()


@pytest.mark.parametrize(
    ("timestamp", "expected_after_cut", "submicrosecond_nanoseconds"),
    [
        ("2026-09-27T16:30:00.499999999Z", False, 999),
        ("2026-09-27T16:30:00.500000000Z", True, 0),
    ],
)
def test_restore_timestamp_preserves_nine_digit_fraction_at_snapshot_boundary(
    timestamp, expected_after_cut, submicrosecond_nanoseconds
):

    cutoff = dt.datetime(2026, 9, 27, 16, 30, 0, 500_000, tzinfo=dt.UTC)
    order = {
        "id": "order-nanosecond-time",
        "client_order_id": "client-nanosecond-time",
        "symbol": "AAPL",
        "side": "buy",
        "qty": "1",
        "filled_qty": "0",
        "filled_avg_price": None,
        "status": "new",
        "created_at": timestamp,
        "submitted_at": timestamp,
        "updated_at": timestamp,
    }
    broker = make_broker(
        "key",
        "secret",
        transport=httpx.MockTransport(lambda _: httpx.Response(200, json=[order])),
    )
    try:
        event = broker._orders_after(cutoff)[0]
        assert event.submicrosecond_nanoseconds == submicrosecond_nanoseconds
        assert event.resolution_nanoseconds == 1
        assert event.overlaps_or_follows(cutoff) is expected_after_cut
    finally:
        broker.close()


@pytest.mark.parametrize(
    ("created_at", "expected_after_cut"),
    [
        ("2026-09-27T16:30:00.000000Z", False),
        ("2026-09-27T16:30:00.500000Z", True),
    ],
)
def test_nontrade_restore_activity_uses_precise_creation_time_not_null_transaction_time(
    created_at, expected_after_cut
):

    cutoff = dt.datetime(2026, 9, 27, 16, 30, 0, 500_000, tzinfo=dt.UTC)
    broker = make_broker(
        "key",
        "secret",
        transport=httpx.MockTransport(
            lambda _: httpx.Response(
                200,
                json=[
                    {
                        "id": "nontrade-activity",
                        "activity_type": "DIV",
                        "transaction_time": None,
                        "created_at": created_at,
                        "date": "2026-09-27",
                    }
                ],
            )
        ),
    )
    try:
        event = broker._activity_events_after(cutoff)[0]
        assert event.overlaps_or_follows(cutoff) is expected_after_cut
    finally:
        broker.close()


def test_restore_evidence_catches_pre_cut_order_submitted_and_canceled_after_cut():

    cutoff = dt.datetime(2026, 9, 27, 16, 30, 0, 500_000, tzinfo=dt.UTC)
    before_cut = cutoff - dt.timedelta(milliseconds=500)
    after_cut = cutoff + dt.timedelta(milliseconds=500)
    order = {
        "id": "order-canceled-after-cut",
        "client_order_id": "client-canceled-after-cut",
        "symbol": "AAPL",
        "side": "buy",
        "qty": "1",
        "filled_qty": "0",
        "filled_avg_price": None,
        "status": "canceled",
        "created_at": before_cut.isoformat(timespec="microseconds"),
        "submitted_at": after_cut.isoformat(timespec="microseconds"),
        "updated_at": after_cut.isoformat(timespec="microseconds"),
        "canceled_at": after_cut.isoformat(timespec="microseconds"),
    }
    broker = make_broker(
        "key",
        "secret",
        transport=httpx.MockTransport(lambda _: httpx.Response(200, json=[order])),
    )
    try:
        events = broker._orders_after(cutoff)
        assert any(event.overlaps_or_follows(cutoff) for event in events)
    finally:
        broker.close()


@pytest.mark.parametrize(
    ("date", "transaction_time"),
    [
        ("2026-09-26", None),
        ("2026-09-26", "2026-09-26T12:00:00Z"),
        ("2026-09-27", None),
    ],
)
def test_nontrade_activity_without_creation_time_fails_closed(date, transaction_time):

    from copytrading_engine.execution.application.ports import BrokerResponseError

    cutoff = dt.datetime(2026, 9, 27, 16, 30, 0, 500_000, tzinfo=dt.UTC)
    broker = make_broker(
        "key",
        "secret",
        transport=httpx.MockTransport(
            lambda _: httpx.Response(
                200,
                json=[
                    {
                        "id": "nontrade-date-only",
                        "activity_type": "DIV",
                        "transaction_time": transaction_time,
                        "date": date,
                    }
                ],
            )
        ),
    )
    try:
        with pytest.raises(BrokerResponseError):
            broker._activity_events_after(cutoff)
    finally:
        broker.close()


def test_external_unfilled_cancel_between_sentinel_and_cut_is_harmless():

    from copytrading_engine.execution.application.restore_reconciliation import (
        reconcile_restore_snapshot,
    )
    from copytrading_engine.execution.domain.ledger_state import LedgerSnapshot

    # The external order is submitted and canceled after an earlier open-order
    # sentinel, but before the snapshot cut. It has no fill and is already
    # absent from current holdings/open orders. The post-cut cursor cannot
    # prove this complete audit history; the activation safety invariant treats
    # an unfilled external cancel as harmless.
    sentinel_at = dt.datetime(2026, 9, 27, 16, 30, 0, tzinfo=dt.UTC)
    cutoff = dt.datetime(2026, 9, 27, 16, 30, 3, tzinfo=dt.UTC)
    invisible_submit = dt.datetime(2026, 9, 27, 16, 30, 2, tzinfo=dt.UTC)
    requests = []
    account = {
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

    def handler(request):
        requests.append(request)
        if request.url.path == "/v2/account":
            return httpx.Response(200, json=account)
        if request.url.path == "/v2/orders":
            if request.url.params.get("status") == "all":
                # `after` is exclusive; the order's submission timestamp is
                # exactly the cursor and it has already been canceled unfilled.
                assert request.url.params["after"] == invisible_submit.isoformat()
            return httpx.Response(200, json=[])
        if request.url.path == "/v2/positions":
            return httpx.Response(200, json=[])
        assert request.url.path == "/v2/account/activities"
        return httpx.Response(200, json=[])

    broker = make_broker("key", "secret", transport=httpx.MockTransport(handler))
    try:
        snapshot = LedgerSnapshot(account_id="paper-demo", environment="paper")
        evidence = broker.restore_evidence(snapshot, cutoff)

        assert sentinel_at < invisible_submit < cutoff
        assert evidence.complete
        assert evidence.open_order_client_ids == ()
        assert evidence.orders_after_snapshot == ()
        assert evidence.activity_ids_after_snapshot == ()
        assert all(request.method == "GET" for request in requests)
        assert reconcile_restore_snapshot(snapshot, evidence) is None
    finally:
        broker.close()


def test_restore_evidence_preserves_blocked_account_readiness_and_reconciliation_refuses_it():

    from copytrading_engine.execution.application.restore_reconciliation import (
        RestoreReconciliationError,
        reconcile_restore_snapshot,
    )
    from copytrading_engine.execution.domain.ledger_state import LedgerSnapshot

    account = {
        "id": "paper-demo",
        "status": "ACTIVE",
        "cash": "5000",
        "equity": "5000",
        "last_equity": "5000",
        "buying_power": "5000",
        "currency": "USD",
        "trading_blocked": True,
        "account_blocked": False,
        "trade_suspended_by_user": False,
    }

    def handler(request):
        if request.url.path == "/v2/account":
            return httpx.Response(200, json=account)
        if request.url.path in {"/v2/positions", "/v2/orders"}:
            return httpx.Response(200, json=[])
        assert request.url.path == "/v2/account/activities"
        return httpx.Response(200, json=[])

    broker = make_broker("key", "secret", transport=httpx.MockTransport(handler))
    try:
        snapshot = LedgerSnapshot(account_id="paper-demo", environment="paper")
        evidence = broker.restore_evidence(snapshot, dt.datetime.now(dt.UTC))
        assert evidence.account.active is False
        with pytest.raises(RestoreReconciliationError, match="active"):
            reconcile_restore_snapshot(snapshot, evidence)
    finally:
        broker.close()


def test_restore_evidence_does_not_query_every_closed_order_in_a_large_ledger():

    from copytrading_engine.execution.domain.ledger_state import LedgerSnapshot
    from copytrading_engine.execution.domain.order_lifecycle import OrderStatus
    from copytrading_engine.execution.domain.orders import OrderRecord
    from copytrading_engine.execution.domain.sessions import Session

    created_at = dt.datetime(2020, 1, 1, tzinfo=dt.UTC)
    orders = {}
    for index in range(501):
        client_id = f"closed-{index}"
        orders[client_id] = OrderRecord(
            side="buy",
            position_intent="buy_to_open",
            type="limit",
            limit_price=Decimal("200"),
            symbol="AAPL",
            qty=Decimal("1"),
            source_price=Decimal("200"),
            entry_tolerance_pct=Decimal("0"),
            lot_id=None,
            entry_price=Decimal("200"),
            session=Session.REGULAR,
            client_id=client_id,
            message_id="source:1",
            instruction_index=0,
            source_key="source:1",
            status=OrderStatus.CANCELED,
            filled_qty=Decimal("0"),
            broker_id=f"broker-{index}",
            raw_broker_status="canceled",
            created_at=created_at,
            day=created_at.date(),
        )
    snapshot = LedgerSnapshot(account_id="paper-demo", environment="paper").model_copy(
        update={"orders": orders}
    )
    account = {
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
    requests = []

    def handler(request):
        requests.append(request)
        if request.url.path == "/v2/account":
            return httpx.Response(200, json=account)
        if request.url.path in {"/v2/positions", "/v2/orders"}:
            return httpx.Response(200, json=[])
        assert request.url.path == "/v2/account/activities"
        return httpx.Response(200, json=[])

    broker = make_broker("key", "secret", transport=httpx.MockTransport(handler))
    try:
        evidence = broker.restore_evidence(snapshot, dt.datetime(2026, 9, 27, tzinfo=dt.UTC))
        assert evidence.complete
        assert evidence.known_orders == {}
        assert not any(request.url.path.endswith(":by_client_order_id") for request in requests)
    finally:
        broker.close()


def test_restore_evidence_finds_closed_fill_round_trip_with_flat_positions():

    from copytrading_engine.execution.application.restore_reconciliation import (
        RestoreReconciliationError,
        reconcile_restore_snapshot,
    )
    from copytrading_engine.execution.domain.ledger_state import LedgerSnapshot

    account = {
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
    requests = []
    cutoff = dt.datetime.now(dt.UTC)
    later = cutoff + dt.timedelta(seconds=1)
    later_orders = [
        {
            "id": "broker-buy",
            "client_order_id": "client-buy",
            "symbol": "AAPL",
            "side": "buy",
            "qty": "1",
            "filled_qty": "1",
            "filled_avg_price": "200",
            "status": "filled",
            "position_intent": "buy_to_open",
            "created_at": later.isoformat(),
            "submitted_at": later.isoformat(),
            "updated_at": later.isoformat(),
            "filled_at": later.isoformat(),
        },
        {
            "id": "broker-sell",
            "client_order_id": "client-sell",
            "symbol": "AAPL",
            "side": "sell",
            "qty": "1",
            "filled_qty": "1",
            "filled_avg_price": "201",
            "status": "filled",
            "position_intent": "sell_to_close",
            "created_at": later.isoformat(),
            "submitted_at": later.isoformat(),
            "updated_at": later.isoformat(),
            "filled_at": later.isoformat(),
        },
    ]

    def handler(request):
        requests.append(request)
        if request.url.path == "/v2/account":
            return httpx.Response(200, json=account)
        if request.url.path == "/v2/positions":
            return httpx.Response(200, json=[])
        if request.url.path == "/v2/orders":
            if request.url.params.get("status") == "all":
                return httpx.Response(200, json=later_orders)
            return httpx.Response(200, json=[])
        assert request.url.path == "/v2/account/activities"
        return httpx.Response(
            200,
            json=[
                {
                    "id": "fill-buy",
                    "activity_type": "FILL",
                    "created_at": later.isoformat(),
                    "transaction_time": later.isoformat(),
                },
                {
                    "id": "fill-sell",
                    "activity_type": "FILL",
                    "created_at": later.isoformat(),
                    "transaction_time": later.isoformat(),
                },
            ],
        )

    broker = make_broker("key", "secret", transport=httpx.MockTransport(handler))
    try:
        snapshot = LedgerSnapshot(account_id="paper-demo", environment="paper")
        evidence = broker.restore_evidence(snapshot, cutoff)
        assert evidence.positions == {}
        assert len(evidence.orders_after_snapshot) == 2
        assert evidence.activity_ids_after_snapshot == ("fill-buy", "fill-sell")
        assert all(request.method == "GET" for request in requests)
        with pytest.raises(RestoreReconciliationError, match="activity after the snapshot"):
            reconcile_restore_snapshot(snapshot, evidence)
    finally:
        broker.close()


@pytest.mark.parametrize(
    ("page_size_name", "max_pages_name", "path", "page"),
    [
        (
            "_ORDERS_PAGE_SIZE",
            "_MAX_RESTORE_ORDER_PAGES",
            "/v2/orders",
            [
                {
                    "id": "order-1",
                    "client_order_id": "client-1",
                    "symbol": "AAPL",
                    "side": "buy",
                    "qty": "1",
                    "filled_qty": "0",
                    "filled_avg_price": None,
                    "status": "new",
                    "created_at": "2026-09-27T16:30:00.000000Z",
                    "submitted_at": "2026-09-27T16:30:00.000000Z",
                    "updated_at": "2026-09-27T16:30:00.000000Z",
                }
            ],
        ),
        (
            "_ACTIVITIES_PAGE_SIZE",
            "_MAX_RESTORE_ACTIVITY_PAGES",
            "/v2/account/activities",
            [
                {
                    "id": "activity-1",
                    "activity_type": "FILL",
                    "created_at": "2026-09-27T16:30:00.000000Z",
                    "transaction_time": "2026-09-27T16:30:00.000000Z",
                }
            ],
        ),
    ],
)
def test_restore_evidence_fails_closed_when_pagination_budget_ends_on_full_page(
    monkeypatch, page_size_name, max_pages_name, path, page
):

    import copytrading_engine.execution.adapters.alpaca.broker as alpaca_module
    from copytrading_engine.execution.application.ports import BrokerResponseError

    monkeypatch.setattr(alpaca_module, page_size_name, 1)
    monkeypatch.setattr(alpaca_module, max_pages_name, 1)
    requests = []

    def handler(request):
        requests.append(request)
        assert request.url.path == path
        return httpx.Response(200, json=page)

    broker = make_broker("key", "secret", transport=httpx.MockTransport(handler))
    try:
        read = broker._orders_after if path == "/v2/orders" else broker._activity_events_after
        with pytest.raises(BrokerResponseError):
            read(dt.datetime.now(dt.UTC))
        assert len(requests) == 1
        assert all(request.method == "GET" for request in requests)
    finally:
        broker.close()


@pytest.mark.parametrize(
    ("page_size_name", "max_pages_name", "path", "page"),
    [
        (
            "_ORDERS_PAGE_SIZE",
            "_MAX_RESTORE_ORDER_PAGES",
            "/v2/orders",
            [
                {
                    "id": "order-1",
                    "client_order_id": "client-1",
                    "symbol": "AAPL",
                    "side": "buy",
                    "qty": "1",
                    "filled_qty": "0",
                    "filled_avg_price": None,
                    "status": "new",
                    "created_at": "2026-09-27T16:30:00.000000Z",
                    "submitted_at": "2026-09-27T16:30:00.000000Z",
                    "updated_at": "2026-09-27T16:30:00.000000Z",
                }
            ],
        ),
        (
            "_ACTIVITIES_PAGE_SIZE",
            "_MAX_RESTORE_ACTIVITY_PAGES",
            "/v2/account/activities",
            [
                {
                    "id": "activity-1",
                    "activity_type": "FILL",
                    "created_at": "2026-09-27T16:30:00.000000Z",
                    "transaction_time": "2026-09-27T16:30:00.000000Z",
                }
            ],
        ),
    ],
)
def test_restore_evidence_rejects_rate_limited_continuation_page(
    monkeypatch, page_size_name, max_pages_name, path, page
):

    import copytrading_engine.execution.adapters.alpaca.broker as alpaca_module

    monkeypatch.setattr(alpaca_module, page_size_name, 1)
    monkeypatch.setattr(alpaca_module, max_pages_name, 2)
    requests = []

    def handler(request):
        requests.append(request)
        assert request.url.path == path
        if len(requests) == 1:
            return httpx.Response(200, json=page)
        return httpx.Response(429)

    broker = make_broker("key", "secret", transport=httpx.MockTransport(handler))
    try:
        read = broker._orders_after if path == "/v2/orders" else broker._activity_events_after
        with pytest.raises(BrokerError) as error:
            read(dt.datetime.now(dt.UTC))
        assert error.value.status == 429
        assert len(requests) == 2
        assert all(request.method == "GET" for request in requests)
    finally:
        broker.close()
