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
- **Whole pipeline:** a real post goes through DeepSeek interpretation, routing,
  and risk into Alpaca paper, and the orders it placed are cancelled
  (`engine/tests/integration/test_paper_trade_end_to_end.py`).
- **The real window:** journeys J27 and J31 in `make ui-journeys` pass Check Setup
  against live Discord, DeepSeek, and Alpaca paper, then show that an agent's
  request runs only after the owner approves it, once, and that a rejected one
  changes nothing ([acceptance](acceptance.md)).

In bounded runs with the market closed, one real interpretation produced one
durable outcome, restarts sent no duplicate orders or notifications, Telegram
accepted every notification, and a run that only read from the broker attempted
no orders.

## Not proven yet

- Actual paper fills and a full entry-and-exit cycle during a market session,
  over several sessions.
- Real behavior with several broker accounts, parser accuracy across many gurus'
  writing styles, and sustained load.
- Signing with a Developer ID, notarization, and trusted signed updates.
- Installation on a clean Mac, and trials with people who do not write code.
- Real Touch ID and passcode prompts, sleep and wake, Keychain denial, and
  closing and reopening the window, outside controlled tests.
- Live trading, which needs its own separately authorized qualification.

## Known limitations

- Manual-command history and account listings scan everything retained, so very
  large histories need their own latency checks.
- The diagnostics writer polls its idle queue every 10 ms and has a bounded
  shutdown wait.
- A failed cleanup can leave a staged update package on disk; it does not undo
  the installed update.
