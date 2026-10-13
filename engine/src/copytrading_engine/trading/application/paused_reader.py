"""Read-only broker reads for accounts while copying is paused, so the app shows them live.

Copying decides whether orders go out; it should not decide whether the owner can see their
money. The app hands over read keys when the owner unlocks and takes them back when they lock.
The keys stay in memory, and the reader can only ask for an account, its positions, its equity
curve, and a stock's latest quote: it has no path to an order.
"""

import asyncio
import datetime as dt
import logging
from collections.abc import Callable, Iterable
from dataclasses import dataclass
from typing import Literal, Protocol

from pydantic import SecretStr

from copytrading_engine.execution.application.ports import BrokerError
from copytrading_engine.execution.domain.market import (
    Account,
    EquityHistory,
    HistoryWindow,
    Position,
    Quote,
)

log = logging.getLogger(__name__)

# The app reads accounts about this often; a read inside it is answered from the last one.
FACTS_REUSE = dt.timedelta(seconds=10)
HISTORY_REUSE = dt.timedelta(seconds=60)
# A stock typed into the trade sheet is quoted as the owner types; a repeat inside this is reused.
QUOTE_REUSE = dt.timedelta(seconds=2)


class ReadOnlyBroker(Protocol):
    """The reads the paused reader may make, and nothing that places or cancels."""

    def account(self) -> Account: ...
    def positions(self) -> tuple[Position, ...]: ...
    def equity_history(self, window: HistoryWindow) -> EquityHistory: ...
    def quote(self, symbol: str) -> Quote: ...
    def close(self) -> None: ...


@dataclass(frozen=True, slots=True)
class ReadKeys:
    account_id: str
    environment: Literal["paper", "live"]
    key: SecretStr
    secret: SecretStr


@dataclass(frozen=True, slots=True)
class LiveFacts:
    account: Account
    positions: tuple[Position, ...]
    observed_at: dt.datetime


class PausedAccountReader:
    """Answers account reads for paused accounts from the broker, briefly cached."""

    def __init__(
        self,
        broker_factory: Callable[[ReadKeys], ReadOnlyBroker],
        clock: Callable[[], dt.datetime] = lambda: dt.datetime.now(dt.UTC),
    ) -> None:
        self._factory = broker_factory
        self._clock = clock
        self._brokers: dict[str, ReadOnlyBroker] = {}
        self._facts: dict[str, LiveFacts] = {}
        self._histories: dict[tuple[str, HistoryWindow], tuple[dt.datetime, EquityHistory]] = {}
        self._quotes: dict[tuple[str, str], tuple[dt.datetime, Quote | None]] = {}

    def attach(self, keys: Iterable[ReadKeys]) -> None:
        """Hold these accounts' read keys until `detach`, replacing any held before."""
        self.detach()
        for item in keys:
            self._brokers[item.account_id] = self._factory(item)

    def holds(self, account_id: str) -> bool:
        return account_id in self._brokers

    def detach(self) -> None:
        """Forget every key and every cached read, as when the owner locks the app."""
        for broker in self._brokers.values():
            broker.close()
        self._brokers.clear()
        self._facts.clear()
        self._histories.clear()
        self._quotes.clear()

    async def facts(self, account_id: str) -> LiveFacts | None:
        """The account and its positions as the broker reports them now, or None."""
        broker = self._brokers.get(account_id)
        if broker is None:
            return None
        now = self._clock()
        cached = self._facts.get(account_id)
        if cached is not None and now - cached.observed_at < FACTS_REUSE:
            return cached
        try:
            account, positions = await asyncio.gather(
                asyncio.to_thread(broker.account), asyncio.to_thread(broker.positions)
            )
        except BrokerError as exc:
            log.warning("paused_read_failed id=%s status=%s", account_id, exc.status)
            return cached
        facts = LiveFacts(account=account, positions=positions, observed_at=now)
        self._facts[account_id] = facts
        return facts

    async def equity_history(self, account_id: str, window: HistoryWindow) -> EquityHistory | None:
        """The broker's curve for a paused account, fetched at most once a minute."""
        broker = self._brokers.get(account_id)
        if broker is None:
            return None
        now = self._clock()
        cached = self._histories.get((account_id, window))
        if cached is not None and now - cached[0] < HISTORY_REUSE:
            return cached[1]
        try:
            history = await asyncio.to_thread(broker.equity_history, window)
        except BrokerError as exc:
            log.warning("paused_history_failed id=%s status=%s", account_id, exc.status)
            return cached[1] if cached is not None else None
        self._histories[(account_id, window)] = (now, history)
        return history

    async def quote(self, account_id: str, symbol: str) -> Quote | None:
        """The stock's latest quote from this account's market data, or None when the account
        has no keys here or the broker has no quote for the symbol."""
        broker = self._brokers.get(account_id)
        if broker is None:
            return None
        now = self._clock()
        cached = self._quotes.get((account_id, symbol))
        if cached is not None and now - cached[0] < QUOTE_REUSE:
            return cached[1]
        try:
            quote: Quote | None = await asyncio.to_thread(broker.quote, symbol)
        except BrokerError as exc:
            # An unknown symbol answers 4xx: it has no quote, which the sheet says plainly.
            log.warning("paused_quote_failed id=%s status=%s", account_id, exc.status)
            quote = None
        if quote is not None and quote.bid is None and quote.ask is None:
            quote = None
        self._quotes[(account_id, symbol)] = (now, quote)
        return quote
