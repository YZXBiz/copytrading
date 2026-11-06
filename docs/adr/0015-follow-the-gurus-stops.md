# ADR-0015: Follow the guru's stops

## Status
Accepted, November 2026.

## Context
Gurus post protective exits: "剩下一半49.5的tqqq 设置下 跌破50.95出剩下的保护" (stop TQQQ at 50.95 on
what is left of the 49.5 buy), "剩下的一点soxl做个跌破44.5全出的保护" (all of the SOXL, no buy named),
"43.4加了3分之一常规仓soxl 止损放38.4" (a buy and the stop on that same buy). None of these is a
sell now and none is conditional: the guru names a price at which the shares go. Until now the
reader treated them as chatter or as a sell at the stop price, which would have sold at once.

What Alpaca does with a stop, from its documentation and from paper checks on 328T on 6 November
2026:

* A fractional order must be a `day` order ([Fractional trading](https://docs.alpaca.markets/docs/fractional-trading)).
  Stops trigger in the regular session only, and extended hours take limit orders only
  ([Orders at Alpaca](https://docs.alpaca.markets/docs/orders-at-alpaca)). A day stop placed outside
  regular hours is accepted (`accepted`) and waits for the open. Whole and fractional quantities
  (3 and 2.5 shares of SOFI) were both accepted.
* Alpaca reserves the shares of an open sell: with a stop on all 3 shares, a sale of 1 was refused
  (403, "insufficient qty available for order (requested: 1, available: 0)").
* A buy of the stock while a sell stop rests is refused as a possible wash trade (403, "potential
  wash trade detected. use complex orders"). The stop stays accepted.
* A sell stop at or above the market is refused (422, "stop price must be less than current
  price"). Cancelling a stop and then selling worked every time.

## Decision
1. **Off by default, per account.** `follow_stops` sits beside the limits in the saved setup. A
   setup without it reads as false ([ADR-0013](0013-saved-setups-upgrade.md): the field has a
   default, so no ledger or setup version moves). With it off, a stop post is recorded as skipped
   with `follow_stops_off` ("Following the guru's stops is off"). It is never held for the owner.
2. **A stop is a call of its own.** The reading ([ADR-0007](0007-one-reading-contract.md)) gains
   `stop`: the stock, an exact price whose words are in the post, and which buy it protects: a named
   buy price (`lot`), the buy in the same post (`alongside`, by call index), or none (`not_said`,
   all CopyTrading-held shares of the stock for this guru). The usual grounding applies, and the
   reader profile version moves to `stock-reading-v10`.
3. **A rule, then orders.** A stop is a durable rule in the ledger (`StopRule`), and the order at
   Alpaca is its current expression: a sell `stop` order, `day`, regular session, for the shares of
   the protected buy that CopyTrading still holds ([ADR-0010](0010-the-reader-reads-rules-pick-shares.md)'s
   per-buy `entry_remaining`), never more, never the owner's own shares, never for a buy that did
   not fill. A stop beside a buy waits for the buy's fill to settle.
4. **Every copied order goes through the stops.** Alpaca reserves a sell's shares and refuses a buy
   beside a resting stop, so before a copied sell or buy is submitted the engine cancels the stock's stops and waits for each cancel to confirm; if one
   will not clear, the order is aborted (`stop_still_open`; a sell tries again). When it is done, the
   stop is placed again for what is left, or ended when nothing is. A new stop for the same buy
   replaces the old one. Sells and stops are never trimmed or blocked by caps.
5. **A stop fill is a sell from that buy**, recorded with the stop's post as its source, so lots,
   Activity, and the account page read it like any copied sell.
6. **The day order is placed again every regular session.** Because the order lasts a day, each
   `process()` re-places any rule whose order has ended while the regular session is open. A
   refused stop (for example one at or above the market) backs off for five minutes.
7. **Coins are skipped** (`stop_not_for_coins`): a coin's orders are good-till-canceled, with no
   stop type in this design.
8. **Closing the engine leaves stops working.** `close()` cancels the engine's working orders but
   not stops: they keep guarding at Alpaca, and recovery reads them back from the rule.
9. **A buy beside a resting stop** would be refused by Alpaca as a wash trade, so it cancels the
   stop first (point 4). The stop is off while the buy works (up to the buy's timeout) and comes back
   for the buys it protects; a stop does not grow to cover a later buy unless the guru posts one.

## Not covered
* **No protection outside regular hours.** The stop does not trigger before 9:30 or after 4:00 New
  York time, nor on weekends and holidays. A stock that gaps through the price at the open sells at
  the open's price, not the stop's. The setting's line says so: "Regular hours only."
* **No software price-watching.** Nothing in CopyTrading watches the price and sells for the owner.
* **Out of scope:** trailing stops, take-profit orders, and stops the guru did not post.

## Consequences
* A stop is only as good as the day order: if CopyTrading is not running at the open, the stop is
  placed at the next `process()` after the open, and the shares are unprotected until then.
* The control wire, the CLI, and the agent proposals carry `follow_stops` with the other limits.
