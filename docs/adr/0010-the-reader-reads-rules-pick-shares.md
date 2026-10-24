# ADR-0010: The reader reads the words; fixed rules pick the shares

## Status
Accepted, October 2026. Replaces ADR-0007 decisions 4 (*How much*, batches and the default
share) and 8 (*What a sell refers to*). Decisions 5 and 8 to 11 revised 22 October 2026, after a
re-setup showed the limits, the guru's size, and late posts did not work the way an owner assumes.

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
   * "Half" means half of what is left unless the post or playbook says otherwise. Code decides
     which (revised 23 October 2026, after DeepSeek read one "出一半" post both ways): the
     playbook's habit line ("Sell fractions count from the original buy"), unless the reader
     cites post words that name the other basis (原仓, 剩下, "of the original"). A post with no
     such words always counts from the playbook's basis, whatever the model says.
   * A fill is split across the targeted buys in proportion to what each has left; for a stock
     that trades only in whole shares, the remainder goes to the oldest buy.
   One sell is still one order against one lot.
5. **Size.** A stated fraction is that share of the guru's full position, and a stated dollar
   amount is that amount, never more than the full position. A call with no size buys the
   account's *largest single buy* (formerly "maximum per order"), never more than the full position.
   The largest single buy also caps every buy, so a misread post can spend no more than it. A
   batch the playbook gives no size ("第二批 means 1/3") waits for the owner, like a vague trim.
6. **Reposts.** With the guru's re-post check on, the same call within its window counts once, and
   so does a call the reader says repeats one within the window. A call the reader says repeats one
   outside the window waits for the owner. A repeated sell counts once all day. What a sell counts
   from is not part of the call, and a post with the same words as an earlier one repeats its buy
   or sell of the stock however it was read; a trade of the stock the other way in between still
   makes it a new call. With the check off, every post is copied.
7. **Removed.** The four guru switches and the account connection's default share. The saved
   configuration moves to version 8 and the ledger to version 10; earlier ones are not migrated.
8. **Every limit cuts a buy to what it allows.** The largest single buy, the maximum per stock,
   and the maximum total exposure each cut a buy to the room left under them; the order records
   which one cut it (`limited_by`) and what the call asked for. A buy is skipped only when less
   than Alpaca's $1 minimum is left. The daily loss cap still refuses: it is a stop, not a size.
9. **Limits count what CopyTrading bought.** The per-stock and total limits count the shares in
   its lots, at the higher of what they cost and what they are worth now, plus unfilled buys. The
   owner's own shares are not counted, as they are never sold. Cash and buying power stay real.
10. **A sell is never too old.** The maximum signal age (default 600 seconds) applies to buys
    only. A post read back after the app was away is read like any other, whatever its age, if it
    was posted in the last 24 hours (`READ_BACK_WINDOW`); an older one is kept as history, unread.
    The ledger skips a late post's buys as stale, each on the post's timeline, and copies its
    sells. The owner is told once what came of the posts read back ("Read 12 posts posted while
    CopyTrading was off: 2 sells copied, 9 buys too old to copy"), when none has come in for a
    minute, instead of once per post. A sell waits for a bid or an open market instead of being
    skipped; it is planned again at most every 30 seconds (each plan is five Alpaca requests), and
    Activity says "Waiting for a price to sell at". A sell's floor is the guru's sell price less
    the account's allowance (the bid stands in only for a sell that names no price), read late or
    not: it protects the low side, and the order sells whenever the market is at or above it.
    Because a sell can now be processed after a buy the guru posted later, a sell (a close, a
    reduce, a named-price sell, and the original-position basis) takes only from, and counts only,
    buys posted no later than it; with none, it is skipped as `bought_after_sell`, naming when the
    buy was posted. A post older than one already received is out of order: its buys are skipped,
    its sells go through under that rule. A lot sale the owner picks by hand is exempt.
11. **A sell is never given up for waiting, and never held by the account's limits.** Only a
    buy is cancelled when it goes unfilled for the order timeout, and that timeout runs from when
    Alpaca put the order on the market, not from when it was sent (Alpaca can hold an order for
    seconds at the open). A sell keeps working at its floor until it fills, its shares are gone,
    or copying stops; a day order Alpaca expires at the close says the market stayed under the
    floor, and is not sent again by itself. No cap, valuation of other stocks, entry count, or loss
    cap stops or trims a sell, and an order placed outside CopyTrading, or an order incident, holds a
    sell only when it is on the same stock. An open-order list Alpaca can't give whole (500 orders,
    or one listed twice) still holds every order. Whatever can clear holds a sell rather than
    skipping it (`SELL_WAITS`: no bid, market closed, an incomplete order list, an order or
    holdings question or outside order on its stock, overnight halt, a session change, a stop):
    it tries again at most every 30 seconds, and is never lost. A copied sell stopped between being saved and being
    sent (CopyTrading stopping, or the session changing) is journaled as `send_aborted`, its call
    waits again in the same commit, and its next attempt goes out as `copy-<hash>-2` (then `-3`),
    so a crash and restart can neither lose it nor send it twice. A buy so stopped is still
    given up. Orders are marked for extended hours only outside the regular session.
12. **An open order on a stock holds a later post only when it must.** A sell resting at its floor
    can stay open all day, so later posts on the stock do not queue behind it:
    * A buy waits for an earlier open buy of the stock, as before; buys still time out. It does not
      wait for an open sell unless its limit is at or above that sell's limit, which Alpaca refuses
      as a possible wash trade; then it waits, and its age limit still ends the wait.
    * A sell never waits for, or cancels, an open sell. It plans against the shares the open sells
      of the same buys have not yet sold, so "sell half" then "sell half of the rest" sells a half
      and a quarter at once. With none left it is skipped as `already_selling`. Because the lot
      splits a fill across every buy a sell names, a sell that would take shares an open sell of
      other buys in the lot still needs ("sell everything" while "sell the $25 buy" rests) waits
      for that sell instead.
    * A sell cancels an open buy only when it would have sold it: at the buy price it names (any,
      when it names none), posted no later than it. It then waits for that buy to end, so it also
      sells what the buy filled. Any other open buy stays open; the sell waits for it only when
      they would trade (its limit at or under the buy's), and otherwise goes out beside it.
    * A post whose stock Alpaca counts differently only by an open order's unbooked fill waits for
      the next sync instead of being skipped as a mismatch.
    * An order placed by hand still waits for every open order on its stock.
13. **The full position is the guru's.** Each guru's connection keeps its own full position, which
    no longer has to equal the account's maximum per stock. A new guru's left empty is saved as that
    maximum, and a saved one keeps its amount when the maximum changes later; the guru sheet warns
    when it is above the maximum, which still caps buys.

## Consequences
* Guru settings are where they post, the playbook, the account, the full position, and the
  re-post check. The limits stay on the account.
* Every late post is read by the model, so a long time away costs a read for each missed post
  (bounded by the daily model request budget). Captures saved as history before this change keep
  their preview in Activity; no new capture is saved as history.
* The reader is held to the owner's corrections and the guru's open calls, so a mistake is not
  repeated on every later sell.

## Compliance
The reader's output validator rejects words not in the post and a repeat of a call that is not
listed (or is another stock's); a second failure waits for the owner. A named buy price that no
open call of that stock has is asked about once, then believed: the guru may hold buys from before
CopyTrading started, and the account still waits for the owner when it holds no such buy. The ledger
validates that a lot's remaining shares equal the sum of its buys' remaining shares.
