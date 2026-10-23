# ADR-0014: Coins copy like stocks, on paper accounts only

## Status
Accepted, October 2026.

## Context
US stocks do not trade from Friday 8 pm to Sunday 8 pm New York time, so the live buy, sell, and lot
checks could not run at weekends. Alpaca paper accounts trade coins against the dollar (BTC/USD,
ETH/USD) at every hour. Until now every symbol, order, session, and price in the engine was a
stock's.

A paper round trip on 23 October 2026 showed how Alpaca treats a coin:

* Orders, fills, quotes, and assets name the pair, `BTC/USD`; positions name the coin held, `BTCUSD`.
* Only `gtc` and `ioc` are accepted (`day` is refused as "invalid crypto time_in_force").
* A buy whose cost at its limit is under $10 is refused ("cost basis must be >= minimal amount of
  order 10"); a sale of any size, even under the asset's `min_order_size`, goes through.
* The fee is kept out of the coin bought: 0.000123071 BTC filled, 0.000122763 BTC arrived (0.25%).
  The order and its fill activities do not carry the fee, and the `CFEE` activity is posted at the
  day's end.

## Decision
1. **One spelling.** A coin is its dollar pair everywhere (`shared/symbols.py`): the reader's ticker,
   the call, the order, the lot, the app. The Alpaca adapter turns a held `BTCUSD` into `BTC/USD`
   and asks for an asset without the slash. Only dollar pairs are copied, since every limit is in
   dollars.
2. **The reader reads coins.** A coin's words are its ticker, its pair however written, or its name
   (BTC, BTC/USD, BTCUSD, bitcoin, 比特币, 大饼); a playbook line may map any other name. A bare
   BTC at a stock's price is the ETF of that ticker.
3. **The rules are the stock rules.** Sizing, the limits that cut a buy, lots, named-price sells,
   floors, waits, reposts, and late sells are unchanged. Only the broker's terms differ: a coin's
   order is good-till-canceled and carries no extended-hours flag, its session is
   `around_the_clock` (no calendar, extended-hours, or overnight rule applies), its prices and
   quantities move in the asset's own `price_increment` and `min_trade_increment`, and a buy is
   refused under Alpaca's $10 (`MINIMUM_CRYPTO_BUY_USD`) or the asset's `min_order_size`. A buy is
   still cancelled after the order timeout; a sell rests at its floor, as ADR-0010 decision 11 says.
4. **A lot holds what arrived.** The fee is counted from the holding: each sync that reads a coin's
   holding while none of its orders moved (every open order is looked up again after the read)
   takes the shortfall under its lots as the fee on the buys filled since the last count, split by
   what each filled. A shortfall a fee cannot be (more than 1% of those fills, or a surplus) is
   left to the holdings check (ADR-0011). Until the fee is counted the holding may sit that 1%
   under its lots without opening a question, and the coin's next call waits for the count. The
   order keeps Alpaca's filled quantity and records `fee_qty`; the lot and every "of the original"
   share count what was received. An order saved before this change has no fee, which is right
   for a stock, so the ledger keeps its version.
5. **Paper only.** The engine refuses a coin on a live account, in every path (copied, by hand, or
   a lot sale), as `crypto_paper_only`; the notification names the account.

## Consequences
* The live battery runs at weekends on BTC/USD and ETH/USD.
* A coin bought while the owner trades the same coin by hand in Alpaca can have its fee and the
  owner's trade counted together; the lot and the owner's holding still add up to Alpaca's.
* A copied coin buy needs a largest single buy of at least $10.
