# ADR-0007: Every post is read into one contract; plain rules turn it into orders

## Status
Accepted, October 2026. Extends ADR-0006. Amended October 2026: the market-move hold (Y below)
was removed; a buy is bounded by its limit alone.

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
2. **One contract, with no invalid states.** Every post is read into a `PostReading`, built from
   tagged alternatives so a combination that makes no sense cannot be written down:
   ```
   PostReading = TradeMade | Instruction | Conditional | Suggestion | Commentary | Unclear
   Call        = Buy | Sell
   Price       = Exact | Range | AtMarket | NotGiven
   Size        = Fraction | Batch | NotGiven          (a buy)
   Share       = Fraction | All                       (a sell)
   SellFrom    = Lot | NotSaid
   ```
   `shared/reading.py` holds the contract; the reader model is given its JSON schema.
   Every stated value carries the post's own words beside it, so a value without its evidence
   cannot exist. A field the post does not state is `NotGiven` or `NotSaid`; the reader never
   fills a gap. The model's output is validated strictly, without coercion.
3. **Checks before trading.** The contract's shape is valid; every cited word is in the post; a
   name becomes a ticker only through the playbook; a trade made or an instruction has no
   conditional or past-tense words. The checks run as the reader agent's output validator, so a
   failed check gives the model one retry with the reason; a second failure sends the post to
   review.
4. **Three rules, one pure function.** `decide(reading, guru rules, account limits, market)`
   returns an order, a wait with its reason, a skip with its reason, or ignore. It is the policy;
   placing orders and keeping lots stay the engine's mechanism, which receives only the simple
   executable call `decide` builds, as today.
   * *Act or ask.* `trade_made` and `instruction` trade. `suggestion`, `conditional`, and any range
     wait for the owner. `commentary` is ignored. A guru can be set to ask before every trade.
   * *How much.* One guru copies into one account, so the account's maximum per stock is that
     guru's full position. A buy is its share of it: the stated fraction, 1/N for a batch (N per
     guru), or the guru's default share, the whole position unless lowered, when no size is
     given. Amounts round down to the cent, so six 1/6 calls fill the position exactly.
   * *At what price.* A buy is a limit at the guru's price plus X%, set per account. Nothing
     else looks at how far the market has moved: the limit alone bounds the buy. (A hold when the
     market was more than Y% away was tried and removed: on the way up the limit already stops a
     buy that can't fill, and the owner preferred fewer settings to a prompt after a drop.) A sell
     is a limit too, at the guru's price less Z%
     (Z defaults to 1%, set per account), so it never fills far below what the guru got; one that
     hasn't filled by the order timeout is cancelled and the shares stay. A call with no price
     waits for the owner, and so does a call at market, a batch until its guru's N is set, and a
     sell that names no buy for a guru whose sells refer to the buy price.
5. **Limits only protect.** Maximum per order trims a buy and the trim is shown. A buy that would
   pass the maximum per stock or the maximum total, the daily loss cap, or the entries per day is
   skipped, with the reason shown.
6. **Five outcomes.** Every post ends as traded, traded smaller, waiting for you, skipped, or
   ignored. Activity shows the post, how it was read, and what the account did.
7. **Waiting for you.** A post waits when the reader leaves it for the owner, or when an account
   holds a call back (it asks to approve every order, ADR-0008). It shows Copy and Skip, raises an alert when alerts are
   on, and can be copied until its trading day ends (20:00 New York time). Copy opens the calls the
   engine suggests in the review sheet: a range as a limit at its top, a batch the guru has no N for
   at the default share. The owner checks them, then each account previews the order under its
   own limits before anything is placed. Only a post an account is waiting on can be copied, so a
   copy never doubles an order already sent. Skip only takes the post off the owner's list.
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
