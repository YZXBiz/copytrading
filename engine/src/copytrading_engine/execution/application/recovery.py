"""Offline, broker-verified operator recovery for the execution ledger."""

import datetime as dt
from collections import defaultdict
from collections.abc import Callable
from decimal import Decimal

from copytrading_engine.execution.application.ledger import TradingLedger
from copytrading_engine.execution.application.ports import Broker
from copytrading_engine.execution.domain.ledger_state import LedgerSnapshot
from copytrading_engine.execution.domain.market import Account, Position
from copytrading_engine.execution.domain.order_lifecycle import OrderStatus, is_terminal
from copytrading_engine.execution.domain.ownership import (
    OwnershipInspection,
    OwnershipResolution,
    OwnershipResolutionRequest,
    account_activity_reason,
)
from copytrading_engine.execution.domain.recovery import (
    IncidentClearanceEvidence,
    ManualSale,
    ReleaseEvidence,
)
from copytrading_engine.execution.domain.risk import account_exposure
from copytrading_engine.execution.domain.values import BrokerAccountNumber


class RecoveryApplication:
    """Verify current broker observations before asking the ledger to record recovery."""

    def __init__(
        self,
        ledger: TradingLedger,
        broker: Broker,
        *,
        clock: Callable[[], dt.datetime] | None = None,
    ) -> None:
        self._ledger = ledger
        self._broker = broker
        self._clock = clock or (lambda: dt.datetime.now(dt.UTC))

    def inspect_ownership(self) -> OwnershipInspection:
        snapshot = self._ledger.snapshot()
        if snapshot.account_id is None or snapshot.environment is None:
            raise RuntimeError("Broker account inventory has not been initialized")
        account = self._verify_account(snapshot.account_id, snapshot.account_id)
        positions = self._broker.positions()
        self._position_map(positions)
        try:
            exposure = account_exposure(
                positions,
                tuple(snapshot.lots.values()),
                tuple(order for order in snapshot.orders.values() if order.pending),
                account_currency=account.currency,
            )
            risk_status = "ready"
            risk_reason = None
            total_exposure = exposure.total
        except ValueError as error:
            risk_status = "unavailable"
            risk_reason = str(error)
            total_exposure = None
        activity_reason = account_activity_reason(
            self._broker.open_orders(),
            tuple(order for order in snapshot.orders.values() if order.pending),
            unresolved_order_incidents=snapshot.entry_halted,
        )
        return OwnershipInspection(
            account_id=snapshot.account_id,
            environment=snapshot.environment,
            external_positions=tuple(snapshot.external_positions.values()),
            incidents=tuple(snapshot.ownership_incidents.values()),
            broker_positions=positions,
            expected_quantities=self._expected_positions(snapshot),
            account_risk_status=risk_status,
            account_risk_reason=risk_reason,
            total_exposure_usd=total_exposure,
            account_activity_status="ready" if activity_reason is None else "unavailable",
            account_activity_reason=activity_reason,
        )

    def release_uncertain_intent(
        self,
        client_id: str,
        *,
        actor: str,
        reason: str,
        order_history_ref: str,
        fill_history_ref: str,
        account_id: str,
    ) -> ReleaseEvidence:
        """Release a never-confirmed intent without replaying its source instruction."""
        self._require_attestation(actor, reason, order_history_ref, fill_history_ref)
        snapshot = self._ledger.snapshot()
        order = snapshot.orders.get(client_id)
        if order is None or order.status != OrderStatus.UNCERTAIN:
            raise ValueError("Only a saved uncertain order intent can be released")
        if order.filled_qty != 0 or order.broker_id is not None:
            raise ValueError("An uncertain intent with saved broker activity cannot be released")
        if client_id in snapshot.release_evidence:
            raise ValueError("Order intent already has release evidence")

        self._verify_account(snapshot.account_id, account_id)
        if self._broker.lookup(client_id) is not None:
            raise ValueError("Broker lookup found the uncertain order; reconcile it first")
        open_orders = self._broker.open_orders()
        if any(
            item.client_order_id == client_id
            or (order.broker_id is not None and item.id == order.broker_id)
            for item in open_orders
        ):
            raise ValueError("A matching broker order is still open")
        actual = self._position_map(self._broker.positions())
        expected_qty = self._expected_positions(snapshot).get(order.symbol, Decimal(0))
        if actual.get(order.symbol, Decimal(0)) != expected_qty:
            raise ValueError("Broker position does not exactly match the saved ledger position")

        evidence = ReleaseEvidence(
            actor=actor,
            reason=reason,
            order_history_ref=order_history_ref,
            fill_history_ref=fill_history_ref,
            checked_at=self._clock(),
            account_id=account_id,
            submission_state=("started" if order.submit_started_at is not None else "not_started"),
        )
        self._ledger.release_uncertain_intent(client_id, evidence)
        return evidence

    def record_manual_sale(self, sale: ManualSale, *, account_id: str) -> None:
        """Import an externally completed sale after verifying broker fill and holdings."""
        self._require_attestation(sale.reason)
        snapshot = self._ledger.snapshot()
        self._verify_account(snapshot.account_id, account_id)

        observed = self._broker.lookup(sale.order.client_order_id)
        if observed is None or observed != sale.order:
            raise ValueError("Provided manual sale does not match the broker order record")
        if self._ledger.pending():
            raise ValueError("Reconcile pending copier orders before recording a manual sale")
        if self._broker.open_orders():
            raise ValueError("Broker has open orders; verify the account before recording a sale")

        expected = self._expected_positions(snapshot)
        existing = snapshot.manual_sales.get(sale.order.id)
        if existing is None:
            expected[sale.order.symbol] = (
                expected.get(sale.order.symbol, Decimal(0)) - sale.order.filled_qty
            )
        elif existing.lot_id is None:
            incident = snapshot.ownership_incidents[sale.order.id]
            if not incident.resolved:
                expected[sale.order.symbol] = incident.actual_qty
        actual = self._position_map(self._broker.positions())
        if not self._positions_equal(expected, actual):
            raise ValueError("Resulting broker positions do not match the projected ledger")

        # The ledger remains authoritative for the selected lot and quantity policy.
        self._ledger.record_manual_sale(sale, actual.get(sale.order.symbol, Decimal(0)))

    def resolve_ownership(self, request: OwnershipResolutionRequest) -> OwnershipResolution:
        """Allocate a verified broker quantity without creating a broker order."""
        request = OwnershipResolutionRequest.model_validate(request.model_dump())
        snapshot = self._ledger.snapshot()
        prior = snapshot.ownership_resolutions.get(request.resolution_id)
        if prior is not None:
            if prior.request != request:
                raise ValueError("Ownership resolution ID conflicts with different content")
            return prior
        self._verify_account(snapshot.account_id, request.account_id)
        if self._ledger.pending(request.symbol):
            raise ValueError("Pending app order overlaps ownership resolution")
        open_orders = self._broker.open_orders()
        known_open = tuple(order for order in snapshot.orders.values() if order.pending)
        if len(open_orders) >= 500:
            raise ValueError("Broker open-order observation is incomplete")
        if any(order.symbol == request.symbol for order in open_orders):
            raise ValueError("Broker open order overlaps ownership resolution")
        if reason := account_activity_reason(
            open_orders,
            known_open,
            unresolved_order_incidents=snapshot.entry_halted,
        ):
            raise ValueError(f"Broker account activity is unresolved: {reason}")
        actual = self._position_map(self._broker.positions())
        refreshed_orders = self._broker.open_orders()
        if len(refreshed_orders) >= 500:
            raise ValueError("Broker open-order observation is incomplete")
        if {order.client_order_id: order for order in open_orders} != {
            order.client_order_id: order for order in refreshed_orders
        }:
            raise ValueError("Broker open-order activity changed during ownership resolution")
        if any(order.symbol == request.symbol for order in refreshed_orders):
            raise ValueError("Broker open order overlaps ownership resolution")
        if reason := account_activity_reason(
            refreshed_orders,
            known_open,
            unresolved_order_incidents=snapshot.entry_halted,
        ):
            raise ValueError(f"Broker account activity is unresolved: {reason}")
        if actual.get(request.symbol, Decimal(0)) != request.broker_qty:
            raise ValueError("Fresh broker quantity differs from requested allocation")
        self._verify_account(snapshot.account_id, request.account_id)
        return self._ledger.resolve_ownership(request, self._clock())

    def clear_late_order_incident(
        self,
        client_id: str,
        *,
        actor: str,
        reason: str,
        matched_audit_ref: str,
        account_id: str,
    ) -> IncidentClearanceEvidence:
        """Refresh a late order, then clear only after an exact account position audit."""
        self._require_attestation(actor, reason, matched_audit_ref)
        snapshot = self._ledger.snapshot()
        if client_id not in snapshot.release_evidence:
            raise ValueError("No released uncertain order exists for this client ID")
        self._verify_account(snapshot.account_id, account_id)

        observed = self._broker.lookup(client_id)
        if observed is None:
            raise ValueError("Broker lookup could not confirm the late order")
        observed_at = self._clock()
        self._ledger.apply_order(client_id, observed, observed_at)
        refreshed = self._ledger.snapshot()
        incident = refreshed.late_order_incidents.get(client_id)
        if incident is None:
            raise ValueError("Broker refresh did not create a late-order incident")
        order = refreshed.orders[client_id]
        if not is_terminal(order.status):
            raise ValueError("The refreshed late order is not in a terminal state")
        if self._ledger.pending() or self._broker.open_orders():
            raise ValueError("Open orders prevent a reliable incident position audit")

        actual = self._position_map(self._broker.positions())
        expected = self._expected_positions(refreshed)
        if not self._positions_equal(expected, actual):
            raise ValueError("Fresh broker positions do not exactly match ledger-owned positions")
        checked_at = self._clock()
        evidence = IncidentClearanceEvidence(
            actor=actor,
            reason=reason,
            checked_at=checked_at,
            account_id=account_id,
            matched_audit_ref=matched_audit_ref,
            symbol=incident.symbol,
            expected_qty=expected.get(incident.symbol, Decimal(0)),
            broker_qty=actual.get(incident.symbol, Decimal(0)),
        )
        self._ledger.clear_late_order_incident(client_id, evidence)
        return evidence

    def _verify_account(
        self, ledger_account_id: BrokerAccountNumber | None, supplied_account_id: str
    ) -> Account:
        account = self._broker.account()
        if (
            ledger_account_id is None
            or account.id != ledger_account_id
            or supplied_account_id != account.id
        ):
            raise ValueError("Supplied, broker, and ledger account identities must match")
        return account

    @staticmethod
    def _require_attestation(*values: str) -> None:
        if any(not value.strip() for value in values):
            raise ValueError("Operator attestation and evidence references must be nonblank")

    @staticmethod
    def _position_map(positions: tuple[Position, ...]) -> dict[str, Decimal]:
        result: dict[str, Decimal] = {}
        for position in positions:
            if position.symbol in result:
                raise ValueError("Broker returned duplicate position symbols")
            result[position.symbol] = position.qty
        return result

    @staticmethod
    def _owned_positions(snapshot: LedgerSnapshot) -> dict[str, Decimal]:
        expected: dict[str, Decimal] = defaultdict(Decimal)
        for lot in snapshot.lots.values():
            expected[lot.symbol] += lot.remaining_qty
        return dict(expected)

    @classmethod
    def _expected_positions(cls, snapshot: LedgerSnapshot) -> dict[str, Decimal]:
        expected = cls._owned_positions(snapshot)
        for position in snapshot.external_positions.values():
            expected[position.symbol] = expected.get(position.symbol, Decimal(0)) + position.qty
        return expected

    @staticmethod
    def _positions_equal(expected: dict[str, Decimal], actual: dict[str, Decimal]) -> bool:
        return all(
            expected.get(symbol, Decimal(0)) == actual.get(symbol, Decimal(0))
            for symbol in expected.keys() | actual.keys()
        )
