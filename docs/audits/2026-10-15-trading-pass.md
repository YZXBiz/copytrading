# Trading pass — October 15–16, 2026

Worker A of the full test pass: trading on the live paper app installed at
`~/Desktop/CopyTrading.app`. Every post below went to the real Discord test channel, through the
real reader (DeepSeek `deepseek-flash`), the engine's limits and Alpaca paper. Evidence is read
from the account ledgers read-only (`accounts/<id>/execution.sqlite3`), `application.db`, the
`copytrading` CLI, window screenshots (`screencapture -l`, no focus taken), and the macOS unified
log. Scripts and raw results stay in the worker's scratchpad (`battery1.py`, `live.py`, `*.json`,
`*.log`, `shots/`).

Builds under test: local 0.1.0 (115), installed 16:25 ET Thursday, for the extended-hours runs;
0.1.0 (144) from `main` at `affd4f83`, installed 00:23 ET Friday, for the overnight and regular
runs. Build 144 carries the fixes from #120, #123, #126, #127, #130 and #132.

## Preconditions found

| | |
|---|---|
| Sessions | Extended from 16:31 ET Thursday; overnight from 00:22 ET Friday; regular from 9:30 ET Friday |
| zhap-account-2 | Copying, paper, $2,940 equity. Max per order $250, per stock $1,000, total $3,000, daily loss $250, 200 entries a day; buys up to 1% over and sells 1% under the guru's price; extended and overnight on; approve orders off. Held only the PM copy (2.403103 shares, kept), nothing of the owner's own, no open orders |
| primary | Copying, paper, $8,877 equity. Max per order $200, per stock $600, total $5,000. Holds the owner's own CBRS, CIFR, IREN, NBIS, SOXL and 1 NVDA, plus GFS, NVDA and WMT copied from Zhao's channel before the routing changed |
| Routing | **Only Zhao → zhap-account-2.** The Lee guru (→ primary) was removed at 11:26–11:28 ET Thursday (configuration `e13ee61b…` → `7741ca3a…`). A post to #general reads `source_profile_not_configured` and reaches no account, so no primary step that needs a copied post could run |
| App locked | Relaunched locked at about 17:50 ET Thursday and stayed locked (status `locked`, copying stopped) until the owner's Touch ID at 00:21 ET Friday. The overnight run waited for it, checking every 5 minutes, and posted nothing until status answered with both accounts copying |
| Reinstall | The coordinator installed build 144 at 00:23–00:24 ET, during the first overnight posts. Every post in that window was checked in the ledger; none was lost or needed re-posting |

## Results

| Area | Step | Result | Evidence | Fix |
|---|---|---|---|---|
| Copying | 1 · extended battery (30 posts) | PASS | 30 of 30 read, sized, priced and filled as stated: no size → $1,000 cut to $250; "$100 of"; "1/6" → $166.66; 三分之一 → $250; "$400 of" → $250; conditionals → waiting for you; chatter ignored; half, 出一半, all; never-bought VZ → `lot_unavailable`; sell + buy and two-buy posts; a 6-post burst; a #general post reaches nothing. Every buy limit = price × 1.01 (floored), shares = budget ÷ limit | — |
| Copying | 1/7 · overnight battery (30 posts) | PASS | Same 30 posts at 00:22 ET Friday, 30 of 30 filled as stated. The CCL post sent during the reinstall was read 51 s later, not lost | — |
| Copying | 1 · regular battery (30 posts) | PASS | Same 30 posts at 9:31 ET Friday, 30 of 30 as stated. The reworded re-post "Bought $T 1/6" was refused by the reader as `repeats_a_recent_call`, where the earlier runs refused it in the account as `duplicate`; either way nothing was bought twice. One $250 F buy filled 6 shares and paper Alpaca left the rest open; the engine cancelled it at its 60 s order limit and kept the 6 | — |
| Copying | 6 · lid closed (clamshell dark wake) | PASS | 04:27 ET, lid closed since 01:56 ET and the screen locked: "Bought $20 of $F" and "Sold all $F" read in 1.9 s and 3.1 s, both filled | — |
| Copying | Several dollar-sized buys in one post | FAIL → fixed | 18 of 46 five-call posts waited for the owner (`invalid_model_output`): the reader cited "$2", the check wanted "$2 of". Live DeepSeek after the fix: 4 of 4 copied | #127, #132 |
| Copying | A sell of everything after a sell of one buy | FAIL → fixed | "12.30出掉12.41的f" then "Sold all $F at 12.30" a minute later: the second was dropped as `repeats_a_recent_call`, leaving 3.2 F held. The repeat check never compared which buy a sell names, nor a buy's dollars ("$200 of" after "$100 of" at one price) | #149 |
| Limits | 2 · max per order | PASS | $400 → $250; no size → $250 | — |
| Limits | 2 · per stock | PASS | KO at $991.76: $250 refused `symbol_exposure_cap`; exactly $8.24 filled; $1 more refused | — |
| Limits | 2 · total | PASS | $2,766.37 in stocks and resting buys: $250 refused `total_exposure_cap`; exactly $233.63 accepted | — |
| Limits | 2 · entries a day | PASS | Entry 201 ("Bought $2 of $KO at 91.78") refused `daily_entry_cap` | — |
| Limits | 2 · daily loss | Not run: screen locked | Approving an agent's limit proposal asks for a fresh Touch ID or Mac password every time (`AppUnlock.confirm`), so the worker can't approve one. The paper account editor applies without Touch ID, but the lid was closed and the screen locked from 01:56 ET to past 09:20 ET, and macOS blocks accessibility while locked ("no accessibility window"). Ready to run: lower zhap-account-2's daily loss cap under today's loss, post "Bought $20 of $F", expect `daily_loss_cap`, restore $250 | — |
| Limits | 2 · refusal words | PASS | The app reads "Not bought: over your total limit" and "over your KO limit" (`shots/zhap-page.png`) | — |
| Limits | 3 · owner's own shares | PASS (static) / not run live: screen locked | primary's exposure in the app $2,669.95 vs the limit rule rebuilt from Alpaca $2,669.99 (quote drift); external quantities match share for share. The live check routes Zhao into primary in the guru editor (background accessibility) and buys CBRS, where the owner's own 2.878194 shares (about $400) leave about $197 under primary's $600 per stock. The screen stayed locked from 01:56 ET to past 09:20 ET, so the routing couldn't be changed | — |
| Copy by hand | 4 · extended hours | FAIL → fixed | Review read "Can't send · The price quote was too old. Review again in a moment." with "Ask $26.49": after 4 PM the only free quote is 15 minutes old | #120 |
| Copy by hand | 4 · footer = the order sent | FAIL → fixed | Footer "≈ 9.944 shares at $25.14" vs the engine's 9.846 at $25.39 | #130 |
| Copy by hand | 4/7 · overnight, build 144 | PASS | PFE call: the guru's $29.42 is the default; only zhap-account-2 offered; footer "≈ 8.415 shares at $29.71" = the engine's 8.414675 at a $29.71 limit, filled. Market quote refreshed to "≈ $29.37 · 9:39 PM". Confirmed 47 s after the check: "The check expired before you confirmed. Review again."; confirmed 10 s after: accepted and filled. The post then read "Traded smaller · You bought $247.39 of PFE · $250 your max per order · the call asked for $1,000" | — |
| Copy by hand | 4 · refusal words | PASS, one title fixed | Sell of an unheld stock: "Can't send · You hold no shares of this call to sell. Check the account's holdings." The row above it read "zhap-account-2 · trade 1", and the confirm button "Confirm 1 order(s)" | #150 |
| Copy by hand | 4 · regular hours | Not run: screen locked | The T and PFE calls were posted at 9:37 ET and wait for the owner (`review_required`), but the screen stayed locked, so the copy sheet couldn't be driven. The overnight run covered every check | — |
| Selling | 5 · sold all, many positions | PASS | "Sold all" on 10 held stocks sold each one's whole lot, nothing else | — |
| Selling | 5 · one named buy, by post | PASS | Two F buys (4.788507 at 12.41, 3.2 at 12.38) plus T and SOFI held: "12.30出掉12.41的f" sold exactly 4.788507 and left 3.2 | — |
| Selling | 5 · one lot from the app | PASS | With PM, PFE, F and SOFI held: Sell F → All 7.1879 → "Sells 7.187864 shares of F with a limit order at $12.18 … At today's bid of $12.30, about $88.41" → filled 7.187864; PM, PFE and SOFI unchanged | — |
| Restart | 6 · engine killed mid-burst | PASS | `kill -9` of the engine after post 3 of 8 (04:30:27Z); the app had it back within 2 s; all 8 posts read and filled exactly once (posts 4–8 read 14–38 s after posting); no duplicate client ids, no order left open | — |
| Restart | 6 · sleep and wake | FAIL (not run) | No wake can be scheduled without root: as the worker, `pmset relative wake 120` exits 0 but schedules nothing (`pmset -g sched` stays empty), and `sudo` asks for a password. Sleeping with no wake would stop copying until someone opens the Mac, so the worker did not sleep it. Nearest evidence: the lid has been closed since 01:56 ET (`Entering DarkWake state due to 'Clamshell Sleep'`), and at 04:27 ET in that state a buy and a sell of F copied (read 1.9 s and 3.1 s, both filled). The Mac stays up there only because of a `caffeinate -s` started October 13; CopyTrading itself holds just `PreventUserIdleSystemSleep` ("CopyTrading is copying trades"), so without it a closed lid sleeps the Mac and copying stops | — |
| Updates | 8 · why the app quit at a Sparkle check | FAIL, cause partly found | See below | Follow-up |
| Speed | 9 · post to fill, extended | — | Median of 20 orders: read 1.74 s, order prepared 3.47 s, sent 3.63 s, broker acknowledged 3.90 s, filled 5.25 s. Burst max 14.35 s (posts are read one at a time) | — |
| Speed | 9 · post to fill, overnight | — | Median of 53 orders: read 2.08 s, prepared 3.47 s, sent 3.66 s, acknowledged 3.98 s, filled 5.16 s. Slow outliers: the reinstall (51 s) and the engine kill (14–38 s) | — |
| Speed | 9 · post to fill, regular | — | Median of 20 orders: read 1.82 s, prepared 2.79 s, sent 3.01 s, acknowledged 3.31 s, filled 6.10 s. Burst max read 15.13 s. Slowest fill 53 s: paper Alpaca filled a $100 SOFI buy in two parts | — |

### Step 8: the exit at 22:31 PT on October 14

- CopyTrading (pid 20494) exited cleanly at 22:31:13.97 PT. Computer Use sent synthetic clicks at
  22:31:00.9 and 22:31:13.7. Sparkle's `Updater.app` ran 22:31:04–22:31:16. That is the
  **Install Update → Install and Relaunch** flow, pressed by an automation agent. It was not a
  scheduled check: a scheduled check only shows the banner, because
  `standardUserDriverShouldHandleShowingScheduledUpdate` returns false.
- After the exit, nothing installed and nothing relaunched. The bundle was never re-registered, and
  no CopyTrading process ran until 07:20 PT on October 15, so copying was off all night.
- The update (alpha.11, build 94) is ad-hoc signed with the same EdDSA key, so Sparkle's own
  validator should accept it. The installed build was team-signed (4FHVN52S93), while Sparkle's
  `Autoupdate`, `Updater.app` and XPC services inside it were ad-hoc. Sparkle requires the installer
  connection to match the host's signing requirement. That mismatch is the likely reason the
  installer never finished, but the unified log keeps no Sparkle lines from that minute and no
  download cache remains, so it is unconfirmed.
- Follow-up:
  1. Reproduce in isolation with a debug build, `COPYTRADING_UPDATE_FEED` and a test EdDSA key.
  2. In local team signing (`app/scripts/build_app.py`), sign Sparkle's helpers with the same team.
  3. Keep automation agents away from the update banner.

## Needs the owner

- Unlock the Mac (or open the lid) so the worker can route Zhao into primary for the step 3 live
  check and lower zhap-account-2's daily loss cap for the step 2 refusal; both are scripted
  (`battery1.py primary`, `battery1.py loss`) and restore the routing and the cap afterwards.
- Sleep and wake: `sudo pmset relative wake 120 && pmset sleepnow` while the app is copying.
- Decide whether a closed lid should keep copying. Today only a `caffeinate -s` left running since
  October 13 keeps the Mac up with the lid closed; CopyTrading's own assertion stops idle sleep only.

## Afterwards

At 9:45 ET Friday: every test share sold (11 stocks in zhap-account-2 by "Sold all" posts); zhap-account-2 holds only the PM it held before the pass, primary only its earlier GFS, NVDA and WMT copies and the owner's own stocks; no open orders in either account; no limit, route or switch changed; `copytrading status` reads both accounts "running, copying on". The T and PFE calls posted for the by-hand step still wait for the owner and expire on their own.
