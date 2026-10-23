"""What a symbol names: a US stock or ETF ("NVDA", "BRK.B"), or a coin's US dollar pair ("BTC/USD").

One spelling per instrument runs through the engine. A coin is always its pair, as Alpaca takes it
in orders and quotes; Alpaca writes a coin it holds without the slash ("BTCUSD"), and its adapter
turns that back into the pair (ADR-0014).
"""

import re
from typing import Final

STOCK_PATTERN: Final = r"[A-Z]{1,5}(?:[.][A-Z])?"
CRYPTO_PATTERN: Final = r"[A-Z]{2,10}/USD"
SYMBOL_PATTERN: Final = rf"^(?:{STOCK_PATTERN}|{CRYPTO_PATTERN})$"
QUOTE_CURRENCY: Final = "USD"

# The coins Alpaca trades against the US dollar, and the names a post may call them by. Stablecoins
# are left out: there is nothing to copy in a dollar bought with dollars.
_COINS: Final[dict[str, tuple[str, ...]]] = {
    "AAVE": ("aave",),
    "ADA": ("cardano", "艾达币"),
    "ARB": ("arbitrum",),
    "AVAX": ("avalanche",),
    "BAT": ("basic attention token",),
    "BCH": ("bitcoin cash", "比特币现金"),
    "BONK": ("bonk",),
    "BTC": ("bitcoin", "比特币", "大饼"),
    "CRV": ("curve dao",),
    "DOGE": ("dogecoin", "狗狗币"),
    "DOT": ("polkadot", "波卡"),
    "ETH": ("ethereum", "ether", "以太坊", "以太币", "二饼"),
    "FIL": ("filecoin",),
    "GRT": ("the graph",),
    "HYPE": ("hyperliquid",),
    "LDO": ("lido dao",),
    "LINK": ("chainlink",),
    "LTC": ("litecoin", "莱特币"),
    "ONDO": ("ondo",),
    "PAXG": ("pax gold",),
    "PEPE": ("pepe",),
    "POL": ("polygon",),
    "RENDER": ("render token",),
    "SHIB": ("shiba inu", "柴犬币"),
    "SKY": ("sky protocol",),
    "SOL": ("solana", "索拉纳"),
    "SUSHI": ("sushiswap",),
    "TRUMP": ("trump coin", "川普币"),
    "UNI": ("uniswap",),
    "WIF": ("dogwifhat",),
    "XRP": ("ripple", "瑞波币"),
    "XTZ": ("tezos",),
    "YFI": ("yearn finance",),
}
_NAMES: Final = {name.casefold(): coin for coin, names in _COINS.items() for name in names}
# A coin written as a pair: BTC/USD, BTC-USD, BTCUSD, and the stablecoin quotes a guru may write.
_PAIR: Final = re.compile(r"([A-Z]{2,10}?)[/-]?(?:USDT|USDC|USD)")


def is_crypto(symbol: str) -> bool:
    """Whether the symbol is a coin's pair rather than a stock."""
    return "/" in symbol


def coin(symbol: str) -> str:
    """The coin a pair trades, "BTC" of "BTC/USD"."""
    return symbol.split("/", 1)[0]


def crypto_pair(words: str) -> str | None:
    """The pair the post's words name, or None when they name no coin Alpaca trades: the coin's
    ticker (BTC, $btc), its pair however written (BTC/USD, btc-usd, BTCUSD), or its name (bitcoin,
    比特币)."""
    text = words.strip().lstrip("$#").strip()
    named = _NAMES.get(text.casefold())
    if named is not None:
        return f"{named}/{QUOTE_CURRENCY}"
    upper = text.upper()
    if upper in _COINS:
        return f"{upper}/{QUOTE_CURRENCY}"
    match = _PAIR.fullmatch(upper)
    if match is not None and match.group(1) in _COINS:
        return f"{match.group(1)}/{QUOTE_CURRENCY}"
    return None


def held_symbol(symbol: str, asset_class: str) -> str:
    """The pair for a coin Alpaca lists as held ("BTCUSD" is "BTC/USD"); a stock is unchanged."""
    if asset_class != "crypto" or is_crypto(symbol):
        return symbol
    if not symbol.endswith(QUOTE_CURRENCY) or len(symbol) <= len(QUOTE_CURRENCY):
        return symbol
    return f"{symbol[: -len(QUOTE_CURRENCY)]}/{QUOTE_CURRENCY}"


def path_symbol(symbol: str) -> str:
    """The symbol as an Alpaca URL path takes it: a pair without its slash."""
    return symbol.replace("/", "")
