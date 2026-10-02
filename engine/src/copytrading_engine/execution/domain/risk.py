"""Pure entry-budget policy: input facts in, approved budget or reason out."""

from dataclasses import dataclass
from decimal import ROUND_HALF_UP, Decimal
from typing import Literal, Protocol

from copytrading_engine.execution.domain.market import Position
from copytrading_engine.execution.domain.orders import OrderRecord, OwnedLot
from copytrading_engine.execution.domain.sizing import RouteConnection


class EntryLimits(Protocol):
    """Read-only limits needed by this policy; no signal or startup configuration."""

    @property
    def max_order_usd(self) -> Decimal: ...
    @property
    def max_symbol_usd(self) -> Decimal: ...
    @property
    def max_total_usd(self) -> Decimal: ...
    @property
    def daily_loss_cap_usd(self) -> Decimal: ...
    @property
    def max_entries_per_day(self) -> int: ...


@dataclass(frozen=True, slots=True)
class EntryFacts:
    symbol_exposure: Decimal
    total_exposure: Decimal
    cash: Decimal
    buying_power: Decimal
    equity: Decimal
    last_equity: Decimal
    entries_today: int
    account_active: bool


@dataclass(frozen=True, slots=True)
class ExposureBreach:
    scope: Literal["symbol", "total"]
    current: Decimal
    proposed: Decimal
    limit: Decimal


@dataclass(frozen=True, slots=True)
class BudgetDecision:
    budget: Decimal | None
    reason: str
    breaches: tuple[ExposureBreach, ...] = ()


def requested_entry_budget(
    connection: RouteConnection,
    source_fraction: Decimal | None,
) -> BudgetDecision:
    """Return destination sizing before account facts and risk limits are applied."""
    if connection.mode == "proportional":
        fraction = source_fraction if source_fraction is not None else connection.default_fraction
        if fraction is None:
            return BudgetDecision(None, "missing_source_fraction_review")
        if not fraction.is_finite() or not 0 < fraction <= 1:
            raise ValueError("Source fraction must be between zero and one")
        requested = connection.amount_usd * fraction
    else:
        requested = connection.amount_usd
    # Connection amounts are cents. Decimal ratios such as 1/6 are repeating;
    # normalize their product to cents before broker quantity is rounded down.
    requested = requested.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
    if requested <= 0:
        return BudgetDecision(None, "below_minimum_budget")
    return BudgetDecision(requested, "ready")


@dataclass(frozen=True, slots=True)
class AccountExposure:
    by_symbol: dict[str, Decimal]
    total: Decimal

    def symbol(self, name: str) -> Decimal:
        return self.by_symbol.get(name, Decimal(0))


def account_exposure(
    positions: tuple[Position, ...],
    lots: tuple[OwnedLot, ...],
    pending: tuple[OrderRecord, ...],
    *,
    account_currency: str,
) -> AccountExposure:
    """Conservative USD holdings plus unfilled buy reserves, with no fill double count."""
    if account_currency != "USD":
        raise ValueError("Unsupported account valuation currency")
    by_symbol: dict[str, Decimal] = {}
    if len({position.symbol for position in positions}) != len(positions):
        raise ValueError("Duplicate broker positions prevent account risk evaluation")
    for position in positions:
        if position.qty == 0:
            continue
        if position.qty < 0 or position.asset_class != "us_equity":
            raise ValueError("Unsupported short or non-equity broker position")
        value = position.market_value
        if position.currency != "USD" or value is None or not value.is_finite() or value <= 0:
            raise ValueError("Broker position valuation is unavailable or non-USD")
        by_symbol[position.symbol] = value
    for lot in lots:
        if lot.remaining_qty:
            basis = lot.remaining_qty * lot.average_price
            by_symbol[lot.symbol] = max(by_symbol.get(lot.symbol, Decimal(0)), basis)
    for order in pending:
        if order.pending and order.side == "buy":
            if order.limit_price is None:
                raise ValueError("Pending purchase has no valuation")
            by_symbol[order.symbol] = (
                by_symbol.get(order.symbol, Decimal(0))
                + (order.qty - order.filled_qty) * order.limit_price
            )
    return AccountExposure(by_symbol, sum(by_symbol.values(), Decimal(0)))


def entry_budget(
    config: EntryLimits,
    facts: EntryFacts,
    connection: RouteConnection,
    source_fraction: Decimal | None,
) -> BudgetDecision:
    """Each buy gets its destination's budget once; limits apply to that result."""
    if not facts.account_active:
        return BudgetDecision(None, "account_blocked")
    if facts.equity - facts.last_equity <= -config.daily_loss_cap_usd:
        return BudgetDecision(None, "daily_loss_cap")
    if facts.entries_today >= config.max_entries_per_day:
        return BudgetDecision(None, "daily_entry_cap")
    requested = requested_entry_budget(connection, source_fraction)
    if requested.budget is None:
        return requested
    budget = min(requested.budget, config.max_order_usd)
    breaches = []
    if facts.symbol_exposure + budget > config.max_symbol_usd:
        breaches.append(
            ExposureBreach("symbol", facts.symbol_exposure, budget, config.max_symbol_usd)
        )
    if facts.total_exposure + budget > config.max_total_usd:
        breaches.append(ExposureBreach("total", facts.total_exposure, budget, config.max_total_usd))
    if breaches:
        scopes = {breach.scope for breach in breaches}
        reason = (
            "symbol_and_total_exposure_cap"
            if len(scopes) == 2
            else f"{next(iter(scopes))}_exposure_cap"
        )
        return BudgetDecision(None, reason, tuple(breaches))
    if budget > min(facts.cash, facts.buying_power):
        return BudgetDecision(None, "insufficient_cash")
    return BudgetDecision(budget, "ready")
