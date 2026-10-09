# ADR-0011: Holdings changed outside the app sync from the broker's filled count

## Status
Accepted, October 2026.

## Context
When the broker's share count left what the ledger expected (the owner bought or sold in Alpaca,
or another program traded the account), the engine opened a holdings question and every call for
that stock waited until the owner answered. Owners who trade by hand met this often, and the
answer was always the same arithmetic.

## Decision
1. **A question still opens** the moment a count leaves what the ledger expects, so the stock's
   calls wait for one sync.
2. **The next sync settles it** from the broker's filled count, once nothing in the stock is in
   flight: no app order pending, no uncertain late order, and no open broker order the app didn't
   place (that order can still move the count).
3. **The arithmetic is fixed.** Copied shares the broker still holds stay copied; the rest count
   as the owner's own. A count below the copied shares means copied shares were sold outside the
   app, and the oldest buys count as sold first, the way the app's own sells take them.
4. **Each settle is recorded** with its reason (`owner_bought_outside`, `owner_sold_own_shares`,
   `owner_sold_copied_shares`, `broker_matches_again`) and shows in the account's Activity as a
   plain sentence.

## Consequences
Copying keeps going when the owner trades by hand. The owner can no longer say that extra shares
were the app's own lost fill; a lost fill is covered instead by the uncertain-order checks, which
hold the sync. The manual answer stays for a question raised by a manual sale.
