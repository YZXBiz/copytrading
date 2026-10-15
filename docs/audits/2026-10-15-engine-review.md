# Engine review — October 15, 2026

**Baseline:** `8158df66` (main). 1,647 engine tests passed, 38 skipped.

A review of `engine/src/copytrading_engine` for logic bugs, missing handling, redundancy, and
inefficiency, done as a senior reviewer would before money is at stake. It read the code, the
tests, `docs/architecture.md`, `docs/engine-structure.md`, the ADRs, and the live paper data read
only: the two account ledgers (`primary`, 390 posts and 168 orders; `zhap-account-2`, 663 posts and
413 orders), `application.db`, and `logs/diagnostics.jsonl` (16,710 lines). Every finding below was
reproduced with a test, a script against a copy of the live ledger, or a query on the live files.
Candidates that did not hold up are listed at the end.

Line numbers refer to `8158df66`.

## Findings

Ranked by severity: what can lose money, stop copying, or mislead the owner first.

| # | Severity | Finding | Status |
|---|---|---|---|
| 1 | High | Copying a held call into several accounts is refused in every account when one can't take it | Fixed in #106 |
| 2 | High | Alerts go out inside the copy loop: a slow alert service delays copying, failures retry every 0.5 s, and turning alerts on sends weeks of backlog | Fixed in #110 |
| 3 | High | An idle account check makes 11 Alpaca requests; at the 2 s poll that is ~330 a minute, past Alpaca's 200 | Fixed in #108 |
| 4 | High | An order the broker never received stays "uncertain" forever: its stock is blocked and its reserve counts against the total limit, and the engine's recovery commands have no caller | Left: needs an owner decision and an app flow |
| 5 | Medium | A 100% "maximum below signal price" prices sells at $0, and the first copied sell stops the account | Fixed in #107 |
| 6 | Medium | Fills are journaled up to 10 s before the order that filled (314 of 563 live fills) | Fixed in #105 |
| 7 | Medium | Every read of the ledger on the owner thread deep-copies the whole aggregate: 309 ms of CPU per idle cycle | Fixed in #109 |
| 8 | Medium | The account feed query searches the journal again for every final order update: 113 ms a page, growing with the square of the journal | Fixed in #113 |
| 9 | Medium | Every ledger event rewrites, revalidates, and copies the whole 1.6 MB snapshot, and posts are never pruned | Left: a storage redesign |
| 10 | Medium | Any unexpected error planning one instruction stops the whole account until restart | Left: deliberate fail-closed choice |
| 11 | Low | A manual copy's preview fingerprint covers every order and lot in the account, unlike a lot sale's | Left: conservative, and a policy choice |
| 12 | Low | A lot sale the broker refuses reports Alpaca's raw word; a refused copy reports the fixed code | Fixed in #111 |
| 13 | Low | "What the broker should hold" is computed in four places | Fixed in #112 |
| 14 | Low | Every account limit is declared twice, with its default and bounds | Fixed in #114 |
| 15 | Low | The daily entry cap counts buys the broker refused | Left: policy |
| 16 | Low | The execution outbox's `attempts` and `retry_at` columns are never read or written | Left: schema revision |
| 17 | Low | The app's `correction_incomplete` wording no longer matches when the engine refuses | Left: app copy, next to the copy sheet another worker owns |

### 1. A held call copied into several accounts is refused everywhere when one can't take it

`ManualInterventionService.preview_manual_order` and `confirm_manual_orders`
(`trading/application/manual_intervention.py:171`, `:218`) refused with `correction_incomplete`
unless *every* chosen account's ledger held the correction (`_correction_copies_complete`, `:339`).
Saving a correction is designed to succeed per account: an account that is stopped answers
`account_not_running`, one where the call no longer waits answers `call_not_waiting`, and the app
then previews only the accounts that answered `recorded`
(`app/.../Activity/ManualReviewSheet.swift:510`). So when the owner copied a held call into two
accounts and one of them was stopped, the account that saved the copy was refused too, and kept
being refused for that correction.

Reproduced by `test_an_account_that_recorded_a_correction_previews_while_another_could_not`, which
failed with `correction_incomplete` on main. The check now requires the acting account's own copy
and refuses (`correction_conflict`) only when another account holds a *different* copy under the
same name.

### 2. Alerts inside the copy loop

`TradingRuntime._work_loop` (`trading/entrypoints/runtime.py:758`) sent every pending alert inline,
in the same pass that forwards captures, parses posts, and fans calls out to accounts: up to 100
from the parser outbox and 100 from each account (`sqlite_ledger.py:233`), each a blocking HTTPS
request with a 5 s timeout (`trading/adapters/notifications.py`). Three consequences:

- A slow or unreachable Telegram or Discord webhook delayed every copy by up to the send timeout.
- A failed send was retried on the next pass, every 0.5 s (`runtime.py:806`), with no backoff.
- The outboxes keep every alert written while alerts are off. The live data holds 2,925
  undelivered alerts (1,053 in `application.db`, 656 and 1,216 in the two ledgers), going back to
  October 8. Turning alerts on would have sent all of them, oldest first, 100 per outbox per pass,
  holding the copy loop for minutes.

`AlertRelay` (`trading/application/alerts.py`) now runs as its own task, marks alerts more than an
hour old delivered without sending them, and waits 5 s, 15 s, … up to 5 minutes between failed
passes. The runtime still reports `notification_unavailable` while it fails. Tests:
`tests/trading/test_alerts.py`.

### 3. Eleven Alpaca requests per idle check

Counted with a broker that records its calls (`test_an_idle_cycle_reads_each_broker_fact_once_per_check`):
an idle `ExecutionResources.cycle` (`resources.py:330`) read the positions four times (each
reconcile's audit at `engine.py:229`, the cycle's audit, and the ownership inspection) and the
account twice, and every `AlpacaBroker.positions()` fetched the account again for its currency
(`broker.py:279`). That is 11 HTTP requests per check. The account checks every 2 s whenever the
order stream is down or anything is outstanding (`trading/application/accounts.py`, `check_seconds`),
so about 330 requests a minute per account against Alpaca's limit of 200. A 429 at submit marks
the order uncertain (`ledger.py:1082`), which leads into finding 4.

The broker now keeps the account currency from its first read, `reconcile` returns the positions
its audit read, and the cycle passes that read and its one account read to the audit and the
inspection: four requests per idle check.

### 4. An order the broker never received has no way out (left)

A submit that times out or gets a 5xx or 429 becomes `uncertain` (`ledger.py:1082`), as does a
prepared order found after a crash with no broker record (`engine.py:209`). Reconcile looks it up
by client order ID every cycle; if Alpaca never accepted it, the lookup answers 404 forever and the
order stays uncertain. While it does:

- its stock is blocked: every later call for it waits (`wait_pending_order`) until it ages out;
- a buy's full limit notional stays reserved in `account_exposure`, counting against
  `max_total_usd` and `max_symbol_usd` for good;
- the app tells the owner "It checks again on its own and never sends the order twice"
  (`LotSaleSheet.swift:260`), which is true but never ends.

The engine has the recovery commands (`RecoveryApplication.release_uncertain_intent`,
`clear_late_order_incident`, `record_manual_sale`, `recovery.py:83`), tested and exposed on
`ExecutionOwner`, but nothing calls them: no pipe request, control tool, or app screen. A released
order that later appears at the broker opens a late-order incident, which halts every buy on the
account, and that incident can't be cleared from the app either. No uncertain order exists in the
live ledgers today, and finding 3's fix makes the 429 path rarer.

Left because the fix is a money-safety policy, not a code repair. Two options: release an uncertain
order automatically once Alpaca has answered 404 for its client ID for several minutes and the
stock's count matches (the late-order incident already catches the rare late arrival), or give the
owner a Release and Clear flow in Accounts. Either needs the owner's decision first.

### 5. A 100% sell allowance stops the account

`max_below_signal_pct` accepted 100 (`execution/domain/pricing.py:35`,
`trading/domain/config.py:96`), so `exit_limit_price` returned `0.0000` (`pricing.py:52`).
`OrderPlan.limit_price` must be positive (`orders.py:23`), so planning the first copied sell raised
`ValidationError` inside the account cycle; the supervisor treats a non-broker error as a failure
(`trading/application/accounts.py:258`) and the account stopped copying until a restart, and failed
again on the same queued sell until it aged out. Reproduced with a script that delivers a buy and a
sell under that setting. Both models now take values under 100.

### 6. Fills journaled before their orders

`cycle` reconciled after `process` with the time the cycle was *asked for* (`resources.py:350`),
and the supervisor takes that time before the call waits for the owner's worker
(`accounts.py:250`). A buy placed and filled within one cycle was journaled as filled before it was
prepared. In the live journals, 73 of 161 fills in `primary` and 241 of 402 in `zhap-account-2`
are stamped before their `order_prepared` event, by up to 9.8 s, so Activity and the account feed
can show a fill ahead of its order. Each reconcile now records the time it runs. Because both
reconciles in a cycle used to share one time, a holdings question opened by the first could not
settle in the second; that wait for a later sync (ADR-0011) is kept explicitly with
`settle_before`. Test: `tests/execution/test_cycle_clock.py`.

### 7. Whole-ledger copies on every read

`TradingLedger.snapshot()` deep-copies the aggregate (`ledger.py:182`), and the owner thread
called it for single fields (`engine.py:197`, `:222`, `:236`, `:316`, `:370`, `:448`, `:504`,
`:561`; `resources.py:150`–`:437`; every `RecoveryApplication` read). `observation()` then copied
the copy again with `deepcopy` (`resources.py:325`). Measured against the live ledgers loaded into
an engine with a scripted broker:

| | `primary` (0.9 MB) | `zhap-account-2` (1.6 MB) |
|---|---|---|
| One copy | 17 ms | 32 ms |
| Idle cycle before (9 copies) | 172 ms | 309 ms |
| Status refresh before (3 copies) | 51 ms | 82 ms |
| Idle cycle after (1 copy) | 18 ms | 31 ms |
| Status refresh after | 0 ms | 0 ms |

The worker threads hold the GIL while copying, so this also slowed the event loop that answers the
app. The live engine used 9 min 49 s of CPU in 1 h 26 min of market hours. `TradingLedger.state`
now exposes the published snapshot for reads on the owner thread (every transition publishes a new
object, so it never changes under a reader); `snapshot()` stays the copy for anything that leaves
the thread. Test: `tests/execution/test_ledger_reads.py`.

### 8. The account feed query

`_FEED_EVENTS` (`sqlite_ledger.py:302`) found each order's first final update with a correlated
`NOT EXISTS` that re-scanned every earlier journal row through `json_extract`. One page took 46 ms
on `primary` (2,181 events) and 113 ms on `zhap-account-2` (4,265 events), on the account's owner
thread, growing with the square of the journal. A grouped `min(id)` per order takes 2–3 ms and
returns the same rows on both ledgers at three cursors. Test: no correlated subquery in the plan.

### 9. Whole-snapshot persistence (left)

Each ledger transition rebuilds the aggregate with a full dump and revalidation (`_replace`,
`ledger.py:623`; 32 ms on the 1.6 MB ledger), copies it again for the repository
(`ledger.py:268`; 32 ms), serializes it (10 ms), and rewrites the single `snapshot` row with
`synchronous=FULL` (`sqlite_ledger.py:174`). A copied buy takes about nine transitions. Posts are
never pruned (`messages` is 1.25 MB of the 1.6 MB), so every cost grows with history. Left because
the fix is a storage redesign (per-entity tables, or archiving finished posts out of the snapshot)
that touches backup and restore validation; the copy at `ledger.py:268` is kept on purpose, since
`test_repository_cannot_retain_mutable_ownership_of_loaded_or_saved_state` guards it.

### 10. One instruction's planning error stops the account (left)

Any exception other than `BrokerError` raised while planning or preparing an instruction (a
`ValidationError`, a `RuntimeError` identity check) propagates out of `cycle`, and the supervisor
fails the account (`accounts.py:258`) until the app restarts copying. The queued post is retried
after the restart until it ages out (at most `max_signal_age_seconds`, 120 s here). Finding 5 was
one such error. Left: failing closed on an unexpected planning error is a defensible safety choice;
turning it into a per-instruction skip would hide real ledger faults. Worth revisiting if another
input-driven error appears.

### 11. Two definitions of a preview's account facts (left)

A manual copy's fingerprint covers every order and every lot in the ledger
(`manual_commands.py:361`–`:362`); a lot sale's covers only pending orders and the sold lot
(`lot_sales.py:259`). So a fill of any other stock between a manual preview and its confirm (30 s)
refuses the confirm with `account_facts_changed`, while a lot sale goes ahead. Both re-plan at
confirm, which already re-checks limits and cash. This is the same family as today's quote
fingerprint fix, but it refuses rather than misorders, and narrowing it is a policy choice, so it
is left. The two rejections in the live data (October 13 and 15) predate the quote fix.

### 12. A refused lot sale's reason

`lot_sale_result_from_snapshot` (`lot_sales.py:303`) gave the order's raw broker status as the
reason, `None` when Alpaca refused the submit, while the manual path gives `broker_rejected`
(`manual_commands.py:430`). Both now use one `owner_order_reason`.

### 13. "What the broker should hold", four times

`TradingLedger.expected_position` (`ledger.py:207`), `compare_positions` (`positions.py:60`),
`RecoveryApplication._owned_positions`/`_expected_positions` (`recovery.py:283`, `:290`), and
`restore_reconciliation._expected_positions` (`:98`) each summed lots and the owner's own shares,
differing only in whether they kept stocks with none. `positions.expected_holdings` is now the one
rule, exposed as `LedgerSnapshot.expected_holdings`.

### 14. Account limits, twice

`CopyConfig` (`execution/domain/signals.py:15`) and `AccountPolicy` (`trading/domain/config.py:78`)
declared every limit with its default and bounds, and the pricing percentages a third time in
`EntryPricingPolicy`. They had drifted (only `CopyConfig` refused an infinite maximum per order),
and finding 5 had to be fixed in two places. `AccountLimits` now holds them for both.

### 15. Refused buys count toward the daily entry cap (left)

`entries_today` (`engine.py:430`) counts every buy order of the trading day except one aborted
before submit, so orders Alpaca rejected or that failed to submit use up `max_entries_per_day`.
Left as a policy question: whether an entry means a buy sent or a buy that reached the market.

### 16. Unused outbox columns (left)

The execution `notifications` table declares `attempts` and `retry_at` (`sqlite_ledger.py:46`);
nothing reads or writes them. Removing them is a schema revision with backup-catalog changes for
no behavior, so they stay until the next revision of that component.

### 17. App wording for `correction_incomplete` (left)

After finding 1, the engine refuses with `correction_incomplete` only when the acting account
lacks the copy, but the app still says "This call isn't saved in every account you chose"
(`ManualRefusalText.swift:52`). Left to the worker on the copy sheet, which owns that flow.

## Checked and dropped

- **Duplicate detection cost.** `_repeats` scans the source's earlier posts on every receive, but
  it stops at the first instruction comparison: under 1 ms for 663 posts.
- **Sessions and trading days.** `trade_date` moves 20:00 ET to the next day and the broker
  calendar decides whether that day trades, so Friday nights, weekends, holidays, and early closes
  classify correctly; overnight requires extended hours in both models.
- **Rounding.** Buy limits round down to the tick and sell floors round up; quantities round down
  to 1e-6, and to whole shares for non-fractionable stocks; one-third sizing settles its digits
  before rounding to the cent.
- **Manual corrections for an account the post never reached** (`call_not_received`) and **the
  quote in the preview fingerprint** were already fixed on main.
- **Removed-account Setup Check and the copy sheet.** No engine fault found in either.
