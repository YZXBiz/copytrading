"""A labelled set of real-style posts, English and Chinese (ADR-0012): how sure a decent decision
model is that each one is chat, the reading the reader gives it when it is handed the post, and
what the engine must do with it. `test_triage.py` drives them through the triaged reader with a
fake decision model and a scripted reader."""

from dataclasses import dataclass
from typing import Literal

type Label = Literal["trade", "review", "ignore"]


@dataclass(frozen=True)
class Case:
    post: str
    label: Label
    # How likely the decision model finds it that the post is chat.
    chat: float
    # What the reader answers when the post reaches it: a reading, or None for chat.
    reading: dict | None = None
    reason: str | None = None


def _buy(ticker: str, words: str, said: str, price: dict, size: dict | None = None) -> dict:
    return {
        "action": "buy",
        "action_words": said,
        "stock": {"ticker": ticker, "words": words},
        "price": price,
        "size": size or {"kind": "not_given"},
    }


CASES = (
    # Chat the decision model is sure of: settled there, the reader never asked.
    Case("hi", "ignore", 0.99, reason="chatter"),
    Case("how's going", "ignore", 0.96, reason="chatter"),
    Case("👍", "ignore", 0.98, reason="chatter"),
    Case("早上好", "ignore", 0.97, reason="chatter"),
    Case("大家晚安", "ignore", 0.95, reason="chatter"),
    Case("哈哈哈 今天好热", "ignore", 0.99, reason="chatter"),
    # Chat it is unsure of: the reader decides, and calls it chat.
    # A trap: the owner has seen "hm" asked about a trade, so the decision model must not settle
    # it alone; the reader, with the guru's calls beside it, does.
    Case("hm", "ignore", 0.6, reason="chatter"),
    Case("lol nice 😂", "ignore", 0.7, reason="chatter"),
    Case("gm", "ignore", 0.77, reason="chatter"),
    # Market talk: the decision model hands it on; the reader calls it commentary.
    Case(
        "TSLA 373 is still resistance today",
        "ignore",
        0.05,
        {"kind": "commentary", "summary": "TSLA 373 is resistance"},
    ),
    Case(
        "大盘今天很弱，小心",  # noqa: RUF001 - a Chinese post types the full-width comma
        "ignore",
        0.2,
        {"kind": "commentary", "summary": "大盘今天很弱"},
    ),
    # Something tradeable the engine can't place on its own: waits for the owner.
    Case(
        "buy nvda at the current price",
        "review",
        0.02,
        {
            "kind": "instruction",
            "summary": "Buy NVDA at the current price",
            "calls": [_buy("NVDA", "nvda", "buy", {"kind": "at_market", "words": "current price"})],
        },
        "price_at_market",
    ),
    Case(
        "nvda looks good, adding",
        "review",
        0.1,
        {
            "kind": "trade_made",
            "summary": "Adding NVDA",
            "calls": [_buy("NVDA", "nvda", "adding", {"kind": "not_given"})],
        },
        "price_not_given",
    ),
    Case("trim some", "review", 0.3, {"kind": "unclear", "summary": "Trims some"}, "unclear"),
    Case("加点英伟达", "review", 0.1, {"kind": "unclear", "summary": "加点英伟达"}, "unclear"),
    # Traps from the live run of gpt-6-luna: slang a decision model takes for chat. Each sits
    # below the route threshold (the live chat probability where measured), so the reader reads it.
    # 跑路了 alone is "sold everything" with no stock named: the reader cannot place it.
    Case("跑路了", "review", 0.57, {"kind": "unclear", "summary": "跑路了"}, "unclear"),
    Case("该出手了", "review", 0.43, {"kind": "unclear", "summary": "该出手了"}, "unclear"),
    Case("nvda?", "review", 0.32, {"kind": "unclear", "summary": "Asks about NVDA"}, "unclear"),
    Case(
        "you know what to do",
        "review",
        0.3,
        {"kind": "unclear", "summary": "Hints at a trade"},
        "unclear",
    ),
    Case(
        "buy 1/6 nflx at 73",
        "trade",
        0.01,
        {
            "kind": "instruction",
            "summary": "Buy a sixth of NFLX at 73",
            "calls": [
                _buy(
                    "NFLX",
                    "nflx",
                    "buy",
                    {"kind": "exact", "value": "73", "words": "73"},
                    {"kind": "fraction", "value": "1/6", "words": "1/6"},
                )
            ],
        },
    ),
    Case(
        "sell half wmt",
        "trade",
        0.01,
        {
            "kind": "instruction",
            "summary": "Sell half of WMT",
            "calls": [
                {
                    "action": "sell",
                    "action_words": "sell",
                    "stock": {"ticker": "WMT", "words": "wmt"},
                    "price": {"kind": "not_given"},
                    "share": {"kind": "fraction", "value": "0.5", "words": "half"},
                    "sell_from": {"kind": "not_said"},
                }
            ],
        },
    ),
    # Trades said casually: the decision model leans chat but not past the threshold.
    Case(
        "nflx 出掉了 lol",
        "trade",
        0.5,
        {
            "kind": "trade_made",
            "summary": "出掉了 NFLX",
            "calls": [
                {
                    "action": "sell",
                    "action_words": "出掉了",
                    "stock": {"ticker": "NFLX", "words": "nflx"},
                    "price": {"kind": "not_given"},
                    "share": {"kind": "all", "words": "出掉了"},
                    "sell_from": {"kind": "not_said"},
                }
            ],
        },
    ),
    Case(
        "哈哈 加了点 soun 5.85",
        "trade",
        0.55,
        {
            "kind": "trade_made",
            "summary": "加了 SOUN",
            "calls": [
                _buy("SOUN", "soun", "加了", {"kind": "exact", "value": "5.85", "words": "5.85"})
            ],
        },
    ),
    Case(
        "lol 5.85加了soun 6分之一",
        "trade",
        0.6,
        {
            "kind": "trade_made",
            "summary": "加了六分之一 SOUN",
            "calls": [
                _buy(
                    "SOUN",
                    "soun",
                    "加了",
                    {"kind": "exact", "value": "5.85", "words": "5.85"},
                    {"kind": "fraction", "value": "1/6", "words": "6分之一"},
                )
            ],
        },
    ),
)
