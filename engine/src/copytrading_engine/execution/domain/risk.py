"""Pure entry-budget policy: input facts in, approved budget or reason out."""

from dataclasses import dataclass
from decimal import ROUND_DOWN, ROUND_HALF_UP, Decimal
from typing import Literal, Protocol

from copytrading_engine.execution.domain.market import Position
from copytrading_engine.execution.domain.orders import BuyLimit, OrderRecord, OwnedLot
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


PRODUCT_PLACES = Decimal("1e-10")
# Alpaca's smallest order in dollars: a limit with less room than this leaves nothing to buy.
MINIMUM_ORDER_USD = Decimal("1")


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
    # What the call asked for before a limit cut it.
    requested: Decimal | None = None
    # The limit that cut it, when one did.
    limited_by: BuyLimit | None = None

    @property
    def trimmed(self) -> bool:
        return (
            self.budget is not None and self.requested is not None and self.budget < self.requested
        )


def requested_entry_budget(
    connection: RouteConnection,
    source_fraction: Decimal | None,
    source_usd: Decimal | None,
    *,
    unsized_usd: Decimal | None,
) -> BudgetDecision:
    """What the call asks for, before account facts and limits: the dollars the post names, never
    more than the full position; else its share of the full position. A call that states no size
    buys the account's largest single buy (`unsized_usd`), never more than the full position;
    without one, it is `unsized_buy` (ADR-0010)."""
    if source_usd is not None:
        if not source_usd.is_finite() or source_usd <= 0:
            raise ValueError("A dollar size must be positive")
        return _asked(min(source_usd, connection.full_position_usd))
    if source_fraction is None:
        if unsized_usd is None:
            return BudgetDecision(None, "unsized_buy")
        return _asked(min(unsized_usd, connection.full_position_usd))
    if not source_fraction.is_finite() or not 0 < source_fraction <= 1:
        raise ValueError("Source fraction must be between zero and one")
    # A third is 0.333…3 in Decimal, so first settle the product's last digits (a third of $3000
    # is $1000, not $999.99), then round down to the cent so six sixths never pass the position.
    exact = (connection.full_position_usd * source_fraction).quantize(PRODUCT_PLACES, ROUND_HALF_UP)
    return _asked(exact)


def _asked(amount: Decimal) -> BudgetDecision:
    requested = amount.quantize(Decimal("0.01"), rounding=ROUND_DOWN)
    if requested <= 0:
        return BudgetDecision(None, "below_minimum_budget")
    return BudgetDecision(requested, "ready", requested=requested)


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
    """What CopyTrading has in each stock, in USD: the shares it bought, at the higher of what they
    cost and what they are worth now, plus unfilled buy reserves. The owner's own shares are not
    counted; the limits bound what CopyTrading does."""
    if account_currency != "USD":
        raise ValueError("Unsupported account valuation currency")
    if len({position.symbol for position in positions}) != len(positions):
        raise ValueError("Duplicate broker positions prevent account risk evaluation")
    shares: dict[str, Decimal] = {}
    cost: dict[str, Decimal] = {}
    for lot in lots:
        if lot.remaining_qty:
            shares[lot.symbol] = shares.get(lot.symbol, Decimal(0)) + lot.remaining_qty
            cost[lot.symbol] = (
                cost.get(lot.symbol, Decimal(0)) + lot.remaining_qty * lot.average_price
            )
    held = {position.symbol: position for position in positions}
    by_symbol: dict[str, Decimal] = {}
    for symbol, basis in cost.items():
        worth = Decimal(0)
        position = held.get(symbol)
        if position is not None and position.qty:
            if position.qty < 0 or position.asset_class != "us_equity":
                raise ValueError("Unsupported short or non-equity broker position")
            value = position.market_value
            if position.currency != "USD" or value is None or not value.is_finite() or value <= 0:
                raise ValueError("Broker position valuation is unavailable or non-USD")
            worth = shares[symbol] * value / position.qty
        by_symbol[symbol] = max(worth, basis)
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
    source_usd: Decimal | None = None,
) -> BudgetDecision:
    """Each buy gets its destination's budget once. The largest single buy and the room left
    under the per-stock and total limits cut it; it is refused only when that room is under
    Alpaca's $1 minimum. The daily loss cap refuses outright: it is a stop, not a size."""
    if not facts.account_active:
        return BudgetDecision(None, "account_blocked")
    if facts.equity - facts.last_equity <= -config.daily_loss_cap_usd:
        return BudgetDecision(None, "daily_loss_cap")
    if facts.entries_today >= config.max_entries_per_day:
        return BudgetDecision(None, "daily_entry_cap")
    asked = requested_entry_budget(
        connection, source_fraction, source_usd, unsized_usd=config.max_order_usd
    )
    if asked.budget is None:
        return asked
    requested = asked.budget
    budget, limited_by = requested, None
    room: tuple[tuple[BuyLimit, Decimal], ...] = (
        ("largest_single_buy", config.max_order_usd),
        ("symbol_exposure_cap", config.max_symbol_usd - facts.symbol_exposure),
        ("total_exposure_cap", config.max_total_usd - facts.total_exposure),
    )
    for limit, left in room:
        if left < budget:
            budget, limited_by = left, limit
    budget = max(budget, Decimal(0)).quantize(Decimal("0.01"), rounding=ROUND_DOWN)
    if budget < MINIMUM_ORDER_USD:
        breaches = tuple(
            breach
            for breach in (
                ExposureBreach("symbol", facts.symbol_exposure, requested, config.max_symbol_usd),
                ExposureBreach("total", facts.total_exposure, requested, config.max_total_usd),
            )
            if breach.limit - breach.current < MINIMUM_ORDER_USD
        )
        scopes = {breach.scope for breach in breaches}
        reason = (
            "symbol_and_total_exposure_cap"
            if len(scopes) == 2
            else f"{next(iter(scopes))}_exposure_cap"
            if scopes
            else "below_minimum_budget"
        )
        return BudgetDecision(None, reason, breaches, requested)
    if budget > min(facts.cash, facts.buying_power):
        return BudgetDecision(None, "insufficient_cash", requested=requested)
    return BudgetDecision(budget, "ready", requested=requested, limited_by=limited_by)
