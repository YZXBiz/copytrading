"""The guru's stops, as the account keeps them (ADR-0015).

Alpaca takes a stock's stop only for the day, so the order that protects a buy does not outlive
the session. What lasts is the stop itself: the price the guru posted and the buys it protects.
Each regular session places it again as a stop order for what those buys still hold, until its
shares are gone or a newer stop for the same buy replaces it.
"""

import hashlib

from pydantic import AwareDatetime, Field

from copytrading_engine.execution.domain.values import Identifier, Positive, Value


class StopRule(Value):
    """A stop the account follows: sell what `entries` (buys in the lot `lot_id`) still hold when
    the price falls to `stop_price`. The post that set it is its source."""

    key: Identifier
    symbol: Identifier
    lot_id: Identifier
    entries: tuple[Identifier, ...] = Field(min_length=1)
    stop_price: Positive
    message_id: Identifier
    # Where the stop sits among the post's orders: after its instructions (ledger_state).
    order_index: int = Field(ge=0)
    set_at: AwareDatetime


def stop_rule_key(message_key: str, stop_index: int) -> str:
    """One stop per post and stop, so a post that is processed twice sets it once."""
    return "stop-" + hashlib.sha256(f"{message_key}:{stop_index}".encode()).hexdigest()[:40]


def stop_client_id(rule_key: str, attempt: int) -> str:
    """The client order ID of a stop's `attempt`-th day order: the number is hashed in, so the ID
    stays inside Alpaca's 48 characters however many sessions the stop outlives."""
    return "stp-" + hashlib.sha256(f"{rule_key}:{attempt}".encode()).hexdigest()[:40]
