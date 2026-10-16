# Validation

What is proven about CopyTrading, how, and what is not proven yet. This is a
developer preview: none of this certifies it for production or live trading.

## Checked on every change

GitHub Actions runs these on every push and pull request, and every Monday:

- **Engine:** the full test suite (1,200+ tests), Ruff, Ty, and line-and-branch
  coverage, which fails under 80% and is published as the README badge. The
  suite includes end-to-end scenarios that drive the real runtime, routing, risk,
  ledger, and lots with a mock guru's posts against a simulated broker that moves
  cash with every fill: spending all the cash (the next buy never reaches the
  broker), selling and buying again, trims and closes by lot, shares held outside
  the app, every limit, paused entries, late posts, resting limits, reposts,
  several accounts, fraction sizing, and selling lots from Accounts.
- **App:** a strict Swift 6.4 build (complete concurrency checking, warnings as
  errors), the Swift tests, and `swift format` lint.

Every release, and every pull request that changes how a release is built,
additionally builds the release, verifies the bundle, smoke-tests the released app,
and checks each asset against its manifest and checksums (see
[releases](releases.md)).

## Checked against real services

These run only when a developer supplies paper-trading keys, because they talk
to real services. They use a disposable Alpaca **paper** account and never a live
one.

- **Broker adapter:** submits a one-share nonmarketable limit order, finds it
  again by client ID, and cancels it, ending with no positions or open orders
  (`engine/tests/trading/test_paper_broker_probe.py`).
- **Whole pipeline:** 22 scenarios replay a guru's posts through DeepSeek
  interpretation, routing, risk, and the ledger into Alpaca paper and check what
  reached the account: full, partial, and added buys; partial and full sells at
  the guru's price less the allowance; every limit (per order, per stock, account
  total, entries per day, cash); approval, entries off, and exits not copied;
  chatter, late posts, unknown tickers, and a post delivered twice; overnight
  rules; orders placed outside the app; a restart that keeps the lot; and a burst
  of posts. Each scenario starts with no open orders and no shares of its stocks,
  and sells back what it bought (`engine/tests/integration/test_paper_scenarios.py`).
- **The real window:** journey J31 in `make ui-journeys` sets up and starts copying
  against live Discord, DeepSeek, and Alpaca paper, then shows that an agent's
  request runs only after the owner approves it, once, and that a rejected one
  changes nothing ([acceptance](acceptance.md)).

- **Live Discord to Alpaca paper, two gurus:** on October 13–14, 2026, about 650
  posts were sent through a real Discord channel pair into the released app, during
  the overnight session and regular hours: one guru into one paper account, then
  two gurus at once, each into its own account. A randomized battery mixed buys,
  sells, fractions, dollar sizes, English and Chinese, chatter, pictures, options
  and shorts, conditionals, re-posts, and bursts of up to 22 posts, and checked
  every post: it settled, reached only its own account, was read as written, broke
  no limit, and the accounts ended flat. One run force-killed the engine mid-burst.
  Six faults it found were fixed (0.1.0-alpha.10); the final build's run of 169
  posts, crash included, had none.
- **Full test pass, October 15–16, 2026:** three parallel passes over the
  installed app, every step recorded as passed or failed with evidence.
  - **Trading:** a 30-post battery through the real Discord channel into Alpaca
    paper, run in the extended, overnight and regular sessions, read, sized,
    priced and filled all 90 posts as written. Every limit refused at exactly its
    edge, including the daily loss and shares the owner bought outside the app.
    Copying a call by hand sent exactly the order its footer showed; selling one
    named buy, one lot, or everything sold exactly that. A burst survived the
    engine being killed mid-way with each post filled once, and copying continued
    with the lid closed. Median post to fill was 5 to 6 seconds.
  - **Controls:** every button, switch, link, menu item, tab, sheet and shortcut,
    in English and 简体中文.
  - **Visuals:** every screen in both languages and both appearances, against
    the design rules.
  - **Fixes:** each failure was fixed at its cause before release. Among them,
    a sell of everything right after a sell of one named buy was dropped as a
    re-post. An update the app couldn't install from an iCloud-synced folder
    used to quit it and leave copying off.

In bounded runs with the market closed, one real interpretation produced one
durable outcome, restarts sent no duplicate orders or notifications, Telegram
accepted every notification, and a run that only read from the broker attempted
no orders.

## Not proven yet

- Paper copying across many sessions and days, and load beyond a few hundred
  posts a day.
- Parser accuracy across many real gurus' writing styles (the live battery's
  posts were written for the test).
- Signing with a Developer ID, notarization, and trusted signed updates.
- Installation on a clean Mac, and trials with people who do not write code.
- Real Touch ID and passcode prompts, sleep and wake (a scheduled wake needs
  administrator rights the test pass didn't use), Keychain denial, and closing
  and reopening the window, outside controlled tests.
- Live trading, which needs its own separately authorized qualification.

## Known limitations

- Manual-command history and account listings scan everything retained, so very
  large histories need their own latency checks.
- The diagnostics writer polls its idle queue every 10 ms and has a bounded
  shutdown wait.
- A failed cleanup can leave a staged update package on disk; it does not undo
  the installed update.
