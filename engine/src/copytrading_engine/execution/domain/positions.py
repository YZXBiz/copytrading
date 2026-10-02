"""Compare broker holdings with filled lots, allowing only known in-flight fills."""

from collections import defaultdict
from dataclasses import dataclass
from decimal import Decimal

from copytrading_engine.execution.domain.market import Position
from copytrading_engine.execution.domain.orders import OrderRecord, OwnedLot
from copytrading_engine.execution.domain.ownership import ExternalPosition


@dataclass(frozen=True, slots=True)
class PositionComparison:
    symbol: str
    expected: Decimal
    actual: Decimal
    minimum: Decimal
    maximum: Decimal

    @property
    def mismatched(self) -> bool:
        return not self.minimum <= self.actual <= self.maximum


@dataclass(frozen=True, slots=True)
class PositionAudit:
    positions: tuple[PositionComparison, ...]

    @property
    def matched(self) -> bool:
        return all(p.actual == p.expected for p in self.positions)

    def health(self) -> dict:
        return {
            "status": "matched"
            if self.matched
            else ("mismatch" if any(p.mismatched for p in self.positions) else "reconciling"),
            "differences": [
                {
                    "symbol": p.symbol,
                    "expected_qty": str(p.expected),
                    "broker_qty": str(p.actual),
                    "pending_fill_possible": not p.mismatched,
                }
                for p in self.positions
                if p.actual != p.expected
            ],
        }


def compare_positions(
    lots: tuple[OwnedLot, ...],
    pending: tuple[OrderRecord, ...],
    positions: tuple[Position, ...],
    external: tuple[ExternalPosition, ...] = (),
) -> PositionAudit:
    expected: dict[str, Decimal] = defaultdict(Decimal)
    buys: dict[str, Decimal] = defaultdict(Decimal)
    sells: dict[str, Decimal] = defaultdict(Decimal)
    for lot in lots:
        if lot.remaining_qty:
            expected[lot.symbol] += lot.remaining_qty
    for holding in external:
        expected[holding.symbol] += holding.qty
    for order in pending:
        # Prepared orders have not reached Alpaca and cannot explain a difference.
        if order.pending and order.submit_started_at is not None:
            remaining = order.qty - order.filled_qty
            (buys if order.side == "buy" else sells)[order.symbol] += remaining
    actual = {position.symbol: position.qty for position in positions}
    if len(actual) != len(positions):
        raise ValueError("Duplicate broker position symbols")
    return PositionAudit(
        tuple(
            PositionComparison(
                symbol,
                expected[symbol],
                actual.get(symbol, Decimal(0)),
                max(Decimal(0), expected[symbol] - sells[symbol]),
                expected[symbol] + buys[symbol],
            )
            for symbol in sorted(expected.keys() | actual.keys() | buys.keys() | sells.keys())
        )
    )
