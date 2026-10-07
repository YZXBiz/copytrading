# ADR-0010: The reader reads the words; fixed rules pick the shares

## Status
Accepted, October 2026. Replaces ADR-0007 decisions 4 (*How much*, batches and the default
share) and 8 (*What a sell refers to*).

## Context
The reader saw only the post and the playbook. Because it could not see what the guru had already
bought, the owner set four switches per guru (what a sell refers to, buys in batches, the default
share, and whether a sell counts from the original buy or what is left), and every gap went to
Waiting for You (`sell_names_no_buy`, `missing_or_ambiguous_lot`, `batch_size_unknown`).

## Decision
1. **The model reads; code decides** (unchanged from ADR-0007). The reader turns a post into the
   reading contract. It never picks shares, dollars, or buys.
2. **The reader sees the guru's calls.** Each read receives this guru's calls as facts: every open
   call, uncapped, and the last 10 closed ones (id, buy or sell, ticker, price, size, still open).
   Never old post text. The owner's correction of a post replaces the reader's reading of it.
   Fixed instructions come first and the calls last, so the provider can reuse its cached prefix.
3. **The contract gains two things.** A sell's share may be `NotGiven` (a vague trim), which waits
   for the owner unless the playbook defines it. A reading may name the call it repeats.
4. **Every buy of a stock joins the guru's open lot.** The lot keeps each buy's remaining shares.
   * A sell that names a buy price sells from every buy at exactly that price. A price that
     matches no open buy waits for the owner.
   * A sell that names no buy sells the same share from every buy.
   * "Half" means half of what is left unless the post or playbook says otherwise.
   * A fill is split across the targeted buys in proportion to what each has left; for a stock
     that trades only in whole shares, the remainder goes to the oldest buy.
   One sell is still one order against one lot.
5. **Size.** A stated fraction is that share of the full position (the account's maximum per
   stock). No size asks for the full position; the maximum per order trims it. A batch the
   playbook gives no size ("第二批 means 1/3") waits for the owner, like a vague trim.
6. **Reposts.** With the guru's re-post check on, the same call within its window counts once, and
   so does a call the reader says repeats one within the window. A call the reader says repeats one
   outside the window waits for the owner. A repeated sell counts once all day. With the check off,
   every post is copied.
7. **Removed.** The four guru switches and the account connection's default share. The saved
   configuration moves to version 8 and the ledger to version 10; earlier ones are not migrated.

## Consequences
* Guru settings are where they post, the playbook, the account, and the re-post check. Money rules
  stay on the account.
* Guru examples can state the expected price and, for a sell, the buy price it sells from.
* The reader is held to the owner's corrections and the guru's open calls, so a mistake is not
  repeated on every later sell.

## Compliance
The reader's output validator rejects words not in the post and a repeat of a call that is not
listed (or is another stock's); a second failure waits for the owner. A named buy price that no
open call of that stock has is asked about once, then believed: the guru may hold buys from before
CopyTrading started, and the account still waits for the owner when it holds no such buy. The ledger
validates that a lot's remaining shares equal the sum of its buys' remaining shares.
