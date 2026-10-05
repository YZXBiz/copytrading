# ADR-0007: Every post is read into one contract; plain rules turn it into orders

## Status
Accepted, October 2026. Extends ADR-0006.

## Context
Gurus write very differently. 赵哥 states every trade, its size as a share of his normal
position (加了6分之一常规仓), and the buy each sell comes from (出一半39.5的iren). 分析师 mostly
posts price levels, zones (建仓区域160-179), and conditions (如果明天20以下我会买第一批), and his
rare sells name no buy (Rcl 260 跑路了). The reader's output covered only the first style, so the
others went to review or could not be copied, and every new habit raised the question of new
code.

Sizing had grown the same way. A connection was a fixed amount or a proportional one, the
account's maximum per order also acted as a trade size, and a guru's 1/2 call could come out the
same as his 1/6.

## Decision
1. **The model reads; code decides.** The reader only turns a post into the contract below. Every
   decision about money is plain code, the same for every guru.
2. **One contract.** Every post is read into a `PostReading`:
   * `kind`: `trade_made` (he did it), `instruction` (do it now), `conditional` (if…), `suggestion`
     (consider…, a zone), or `commentary`.
   * `calls`, each with `action` (buy or sell), the stock and how it was written, `price` (exact,
     range, at market, or not given), `size` (a fraction, a batch, or not given), for sells which
     shares (a lot at a price, all, what's left, or not said) and whether a fraction counts from
     the original buy or what's left, a `condition` for conditionals, and the post's own words
     behind every field.
   * A field the post does not state is "not given". The reader never fills a gap.
3. **Checks before trading.** The contract's shape is valid; every cited word is in the post; a
   name becomes a ticker only through the playbook; a failed check gives the model one retry with
   the reason, then the post goes to review.
4. **Three rules.**
   * *Act or ask.* `trade_made` and `instruction` trade. `suggestion`, `conditional`, and any range
     wait for the owner. `commentary` is ignored. A guru can be set to ask before every trade.
   * *How much.* One guru copies into one account, so the account's maximum per stock is that
     guru's full position. A buy is its share of it: the stated fraction, 1/N for a batch (N per
     guru), or the guru's default share, the whole position unless lowered, when no size is
     given. Amounts round down to the cent, so six 1/6 calls fill the position exactly.
   * *At what price.* A buy is a limit at the guru's price plus X%. When the market is more than
     Y% away from the guru's price, above or below, the call waits for the owner. X and Y are set
     per account; Y defaults to 5% in regular hours and 10% outside them. A call with no price
     waits for the owner.
5. **Limits only protect.** Maximum per order trims a buy and the trim is shown. A buy that would
   pass the maximum per stock or the maximum total, the daily loss cap, or the entries per day is
   skipped, with the reason shown.
6. **Five outcomes.** Every post ends as traded, traded smaller, waiting for you, skipped, or
   ignored. Activity shows the post, how it was read, and what the account did.
7. **Waiting for you.** A call that waits shows Copy and Skip, raises an alert when alerts are on,
   and expires at the close. Copying applies the same rules; a range buys at market inside it, or
   rests at its top until the close.
8. **What a sell refers to** is set per guru. *The buy price*: each buy is its own lot, and a sell
   names the lot it sells from, as 赵哥 does. *The whole position*: every buy of a stock joins one
   lot, so a sell that names no buy, as 分析师's 跑路了, sells all of it or the stated share. Either
   way a sell is one order against one lot.
9. **No migration.** The contract and one-guru-per-account replace the previous configuration.
   As in ADR-0006, the app discards an older setup and asks the owner to set up again.

## Consequences
* A new style is a playbook and a few choices, not code: kinds, sizes, and lot references are
  shared vocabulary.
* The owner can see, on every post, exactly what the model understood and what the account did.
* Two gurus cannot share an account. Live trading with two gurus needs a second broker account
  until a guru's own full position inside a shared account is added.
* Sizes given in percent, dollars, or share counts wait for the owner in this version.
* A wrong reading can still trade when its words are in the post. The examples gate from
  ADR-0006, the price check, and the account's limits bound that risk.
