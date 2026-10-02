# Validation and remaining gates

This page records local verification on September 25 – October 1, 2026. It does not certify a production release. Earlier server-stack logs remain in Git history.

## Coverage — October 2

The engine suite (1,177 tests, 11 opt-in live checks skipped) measures **83% line and branch coverage** with `make coverage` (`pytest --cov`). By package: assistant 94%, parsing 92%, execution 88%, control 88%, host 85%, trading 84%, backup 81%, sources 81%. The weakest modules are the ones that need a real Discord session (`sources/session.py`, 45%) and the process entry points. The `make coverage` gate fails under 80%. Coverage shows what the tests execute; it does not show that the assertions are strong. `make check-mutations` probes the execution policy for that.

## 0.1.0-alpha.2 — October 1

Then, before the release was rebuilt on October 2:

- **简体中文 (#119):** strict Swift build, `make lint-swift`, AppLocalizationTests, DesktopCoreTests, the 43-check contract suite, and 78 build-script tests passed. All 23 UI journeys passed, and the account editor was reviewed in both languages.
- **The in-app assistant (#120):**
  - Built task by task, each task independently reviewed, then a whole-branch review and one fix wave.
  - 1,132 engine tests passed, including the prompt-injection, budget, cancel and reset, and scenario-rig insight tests. The opt-in live DeepSeek assistant check passed.
  - Strict Swift build, lint, DesktopCoreTests, AppLocalizationTests, and the contract suite passed.
  - **All 24 UI journeys passed**, including J30 (the assistant answers through a local OpenAI-compatible stub) and J27 (Check Setup against live Discord, DeepSeek, and Alpaca paper).
  - The release commit's tree is identical to the tree that ran those journeys.

Verified on the release branch (workspace redesign, positions by post, People, any model service, lots in
the agent API, and the scenario suite) in a clean worktree with its own freshly built bundle:

- **1,036 engine tests passed** (9 opt-in skips), with `ruff check`, `ruff format --check`, and `ty
  check src` clean. They include 29 end-to-end scenarios (`engine/tests/scenarios`): a mock guru's posts
  drive the real runtime, routing, risk, ledger, lots, and lot sales against a simulated broker that moves
  cash with every fill. Covered: spending all the cash (the next buy is skipped as `insufficient_cash` and
  never reaches the broker), selling and buying again, trims and closes by lot, shares held outside the
  app, unexplained shares (`ownership_incident`), order, symbol, total, and daily-entry caps, the daily
  loss cap (buys stop, sells go), paused entries, late posts (review), resting limits that fill later,
  reposts inside and after the ten-minute window, chatter, several accounts, fraction sizing, and selling
  lots from Accounts. Shrinking the repost window to 60 seconds makes a scenario fail.
- Every OpenAI-style model service gets its expected request (address, key header, model, temperature,
  token field) through the real client with a mocked transport; owner-entered addresses must be https
  unless local. The generic reader was also checked live against DeepSeek's OpenAI-compatible endpoint: it
  ignored chatter and read "Bought NVDA 1/6 at 121.38" as a buy of NVDA at $121.38 for one sixth.
- The strict Swift build, `make lint-swift`, all **29 DesktopCore checks**, the **43-check contract
  suite**, and the **76 build-script tests** passed.
- `app/scripts/ui_journeys.py` passed **all 23 journeys** against the real window, including J27 (Check
  Setup against the real Discord, DeepSeek, and Alpaca paper services), J28 (the grouped interpreter list
  and an Ollama panel with Base URL), and J18 (the bundled `copytrading` helper against the running app).
- Earlier today J27 failed twice while DeepSeek's chat endpoint took minutes to answer (Alpaca and
  Discord answered normally); it passed once DeepSeek recovered. On one of those runs J16 found two
  processes alive 60 seconds after Quit; it has not recurred in four later runs and is not yet explained.

## Guided setup — October 1

Getting Started, the Connections split, and the Technical details redesign
were verified locally on the branch merged with the
OpenObserve removal (#107):

- 958 engine tests passed (9 opt-in skips), with `ruff check`, `ruff format --check`, and `ty check
  src` clean; the strict Swift build, `make lint-swift`, all 28 DesktopCore checks, and the 76
  build-script tests passed; `make desktop-build` produced a team-signed, verified bundle.
- The contract suite (39 checks) passed, including the new guided-setup checks: the checklist ticks
  from what is typed and saved (and not for a guru copying into a missing account); every help
  article has steps and an https link; new drafts start empty, the first account is `primary`, new
  gurus get distinct valid IDs, the first account attaches to a guru waiting for one, and renaming
  an account keeps the guru's link; unsaved-change detection follows the saved setup and Discard
  Changes returns to it; a failed check keeps typed keys and opens its results, a passing one allows
  Start Copying, and changing a typed key afterwards discards it.
- `app/scripts/ui_journeys.py` passed all 22 journeys against the real window, including the new
  J25 Getting Started (Connect Discord reads "To do", then "Done" and "1 of 5" once a channel and a
  token are typed), J26 Help menu, and J27 first check: from nothing saved, Connections with
  DeepSeek, a paper account with keys, and a named guru read "4 of 5", and Check Setup passed
  against the real Discord, DeepSeek, and Alpaca paper services and enabled Start Copying. The
  screenshots were read: the guide, Connections with its help links, unsaved account and guru cards
  under the changes bar, the shortcut reference, and the passing check.
- Every new view was also rendered off-screen in light and dark and inspected: the guide at 0, 2,
  and 5 of 5 steps, each screen's figure, the "You're copying" card, a Connections header with its
  status, and the new Technical details.

## Diagnostics journal replaces the log server — September 30

The engine now writes redacted diagnostics to a private journal the app reads directly; the bundled log server, its disk image, certificate, credentials, and release assets are gone. The app bundle is 173 MB, down from 515 MB.

- `make desktop-check` passed: **958 engine tests (9 opt-in skips), 76 packaging tests**, Ruff, formatting, Ty, swift-format lint, the strict Swift build, XCTests, the contract suite, all **28 DesktopCore checks** with the packaged runtime (including the managed engine writing and the app reading its journal, and an unwritable log leaving the engine running with command recovery intact), and bundle verification.
- `tests/integration/test_diagnostics_journal.py` runs a workflow through capture, DeepSeek-shaped parsing, and two-account delivery across a restart, then reads back complete, correlated payloads and delivery attempts with registered credentials absent.
- A debug build was driven in the background on a throwaway state root (no focus taken): the self-test's three stages appeared in Diagnostics with readable fields and the redacted payload, the Problems filter showed its empty state, Settings → Logs saved 8 days and the restarted engine received `RETENTION_DAYS=8` and the 256 MB limit, Support showed the log size, and Quit left no process behind. Dark mode was not visually checked in this pass, and `make ui-journeys` was not run because the Mac was in use.

## Product redesign — September 29

The redesign was verified locally:

- `make check`, `make desktop-check`, `make check-editor`, and `make check-mutations` passed: 967 engine tests (9 opt-in skips), 69 packaging tests, the strict Swift build, all native checks including the new balance, fill-price, instruction, and equity-history fixture decoding, bundle verification, and every probed mutant killed.
- New engine behavior has red-to-green tests: the overview carries the broker's equity, previous close, day change, cash, buying power, and observation time; orders keep the broker's average fill price; the Alpaca equity curve keeps exact decimals, skips gaps, and rejects misaligned series; the owner asks the broker for a curve at most once a minute; source activity carries the interpreted instructions; the pipe serves `get_equity_history` and refuses an unknown account or period.
- `make ui-journeys` passed all 16 journeys that ran against the real window (J8 skipped without paper keys), including the new J20 toolbar and J21 Settings sections, and the updated J2, J3, J4, J5, J14, J18, and J19 for the new structure. The screenshots were read: first-run welcome, empty states on Activity, People, and Accounts, the stopped-engine banner with Start Engine, the Settings sections, and the retention confirmation.
- Every screen was rendered with a full demo day (three gurus, a paper and a live account, fills, partial fills, skips, a post needing review, day and month curves) in light and dark and inspected: Today, Activity, People, Accounts, Setup, Settings, and the first-run welcome.

## Agent control, step 3 — September 28

The owner-facing controls ([plan](agent-control.md)) were verified locally:

- `make desktop-check` passed:
  - 962 engine tests (7 opt-in skips) and 69 packaging tests
  - the strict Swift build
  - all 33 native checks, including the new **agent access and approvals** check: the setting is off until chosen and stored owner-only; invalid or symlinked settings never grant access; proposal and audit fixtures decode; `AppUnlock.confirm` is refused while locked, prompts afresh for each approval, and is cancelled by locking during the prompt
  - bundle verification
- The engine validates the shared proposal and audit fixtures against its contract, so the app and engine cannot drift. `make check-editor` and `make desktop-smoke` passed.
- `make ui-journeys` passed all 14 journeys that ran (J8 skipped without paper keys), including the new **J18 agent access**:
  - the command is refused before access is allowed
  - choosing Read and pause shows Listening
  - the command then reads status, pauses processing, and is refused a proposal
  - the requests appear in the recent list as "copytrading command"
  - choosing Nothing refuses the command again
- The approval sheet was rendered from the manual-order fixture and inspected: the order in plain words, a Paper/Live badge, the requester, the expiry, the untrusted-text warning, and Reject/Approve. A full approval journey needs an activated account (Discord token, model key, and paper keys), so approval behavior is covered by engine, pipe, and native tests instead.

## Agent control, step 2 — September 28

The app relay ([plan](agent-control.md)) was verified locally:

- `make desktop-check` passed:
  - 960 engine tests (7 opt-in skips) and 69 packaging tests
  - the strict Swift build
  - all 32 native checks, including two new ones:
    - **agent relay socket:** owner-only folder and socket modes; the access level, lock state and caller PID and path reach the engine; pass-through answers; `unavailable` and `invalid_request` error lines; the connection cap; refusal to replace a non-socket file; the socket-path length limit; socket removal on stop.
    - **agent control with the engine:** a real engine behind the relay, driven by the real Python `copytrading` client: status through the relay, a proposal refused for an unknown account, reads refused while locked, pause allowed while locked, and "not running" after the relay stops.
  - bundle verification with the new `Contents/Helpers/copytrading` launcher
- **The real debug app, launched with `COPYTRADING_AGENT_ACCESS=read_pause`:**
  - The bundled `copytrading` command read status and accounts from the live engine, was refused a proposal (exit 5), and paused processing.
  - `copytrading mcp` over stdio listed 14 tools, returned live status, refused the proposal with `forbidden`, and paused processing.
- `make ui-journeys` first stopped because the Mac's screen was locked. A rerun on the renamed app passed all 13 journeys that ran (J8 skipped without paper Alpaca keys). The screenshots show the window title and lock screen as CopyTrading, the engine Ready, and every screen opening. The agent journeys arrive with step 3's user interface.

## Agent control, step 1 — September 28

The engine `control` package, the `copytrading` CLI and the MCP server ([plan](agent-control.md)) were verified locally; the app relay does not exist yet:

- `make check` passed twice: **958 engine tests** (4 opt-in skips) and 68 packaging tests, with Ruff, formatting and Ty. The control tests cover every tier, access level and lock state; a Hypothesis state machine over proposals; a Hypothesis property that approval-tier actions happen only through the owner's approval and at most once; CLI and MCP calls through a fake app socket to a real `PipeServer`; the committed contract schema; and the audit component in the backup catalog. `make check-editor` passed.
- `make check-mutations` killed all **24** mutants, including five new control mutants: resume treated as safe, reads served while locked, approval without the shown digest, a second approval, and a flood blocking pause.
- `make desktop-build`, bundle verification, `make desktop-check` (all native contract and DesktopCore harnesses), and `make desktop-smoke` passed. The MCP SDK installed from the hash-pinned engine lock.
- The bundled Python ran `copytrading status` (exit 3, "not running", with no app) and served the MCP server over real stdio: 14 tools, with a clean `access_off` tool error.
- One unrelated full-suite run failed `test_provider_cancellation_marks_partial_response_and_closes_stream`. It uses a 0.05-second decode timeout and passed alone five times and in the next two full runs; it is a timing-sensitive test, not a control regression.

## Engine structure refactor — September 28

Branch `refactor/engine-structure` reorganized the engine by capability, split `TradingRuntime` by caller task, made execution domain values strict, gave every store one public schema component, and removed compatibility paths; the decisions are in the [engine structure plan](engine-structure.md). At the branch head:

- `make check` passed: **897 engine tests, 4 opt-in skips; 53 packaging tests; Ruff with BLE, SLF, ANN, and RUF; formatting; Ty**.
- `make desktop-check` passed after every Swift-affecting commit: strict Swift build and package tests, all 30 native contract and DesktopCore harnesses against the packaged runtime, and bundle verification. `make desktop-smoke` passed.
- `make check-mutations` killed all **19** mutants, including new sizing, ownership-resolution, and redaction mutants.
- Found and fixed: a late account-owner close task that could be collected before releasing its lock; pipe requests validated in Python mode (every `Decimal` request would fail under strict values); snapshot validators that bypassed JSON-mode conversion; unchecked SQLite literals in source recovery; a provider payload-capture protocol too loose for type checking; and an untested rule that resolution may not move external shares into app lots.

`application.db` is now format version 3 with no migration. Existing development state from earlier builds will not open and must be recreated. The real-provider and disposable-paper workflow was repeated on the refactored engine; see the next section.

## Real workflow on the refactored engine — September 28

All three runs used the app bundle and engine source built at `21153e5` (engine structure refactor and ADRs). The only later engine change on `main` (`operator_queries` fresh-install listing, with its test) is not in that bundle. Each run used fresh isolated state, the disposable paper account, and the Telegram **2nd** channel. The existing trading deployment was not read or changed. The Alpaca adapter source hash was `12362dac…58ce3` in all three runs.

| Run | Observed result |
| --- | --- |
| Full chain after close (16:13 ET) | A guarded `GET /v2/clock` reported the market closed, next open 09:30 ET on September 29. Real DeepSeek parsed the controlled buy once. Two Telegram sends were accepted, and exactly **one** durable `outside_session` outcome was recorded. After restart: one source row, one parser-inbox row, **zero** Telegram resends, one `outside_session` outcome, and an unchanged paper snapshot, with **zero** blocked mutation attempts across 128 guarded broker requests. Registered secrets and canaries were absent from the diagnostics. |
| Full chain during the session (12:36 ET) | Discord read-only recovery completed on an empty window. Paper identity, zero positions and open orders, and the Telegram title were confirmed before any send. Real DeepSeek parsed the controlled buy, and the account owner reached `order_prepared` and `submit_started`. The harness's GET-only guard then blocked the order `POST` before any HTTP request (68 guarded requests), so no order reached Alpaca. The run stopped at its `outside_session` assertion, as expected while the market was open. This shows the owner submits during a session and that the guard holds. |
| Paper adapter order probe (12:39 ET) | The adapter submitted one nonmarketable AAPL limit buy (quantity 1, $1, `buy_to_open`, day) with client ID `e2e-paper-aapl-20260928T163903`. Two client-ID lookups returned the same order as `new`. Cancellation was confirmed terminal (`canceled`). Requests: 1 `POST`, 1 `DELETE`, 17 `GET`, 0 blocked. Final state: zero positions and zero open orders. This is an adapter check, not a fill or an application workflow. |

Two after-close attempts failed on a transient network error at the Telegram destination check, before any send. The harness now reads the market clock during preflight and ignores the clock when comparing paper snapshots.

## Current acceptance checkpoint

- At `1a542f7`, `make desktop-check` passed: **863 engine tests, with 4 opt-in skips; 53 packaging tests; Ruff lint/format; Ty; strict Swift build and package tests; both native harnesses; and bundle verification**. The source-specific capture test waits for the actual source parse rather than counting the startup readiness probe.
- The separate paper order was submitted, found by client ID, and canceled; no positions or open orders remained.
- `make desktop-smoke` passed against that rebuilt app. It inspected the selected operational generation and exercised both owned children, duplicate-owner rejection, a two-destination engine self-test, and Stop. Seven focused smoke-harness tests also passed.
- Combined native storage-pressure reclamation passed as recorded below. The final test-only correction at `d93a0d1` makes failed or malformed disk inspection fail acceptance and checks both the exact image and expected mount. Its strict Swift build, negative-case probes, and full bundled native contract passed; Stop confirmed the image detached and mount unoccupied. Final review at `26c2da7` passed Task 10 specification and quality and approved source merge. The strengthened-run transcript records final success assertions; its wrapper did not retain the numeric process exit code. The accepted staged-package cleanup limitation is listed below.

## Earlier bundled baseline

The table below describes `d0e2bfe`; it is retained as historical evidence, not the current test count.

| Area | Current evidence |
| --- | --- |
| Python quality and packaging | Ruff lint/format and Ty passed. **45 packaging tests passed**. The unsigned Apple Silicon bundle builds with pinned runtime/dependency checks; the source-only Discord dependency has a hash-checked source archive and build tools. Bundle verification passed. |
| Native integration | Strict-concurrency Swift build and Swift test commands passed. All **18 manual native harness checks passed** against the new bundled runtime, including Keychain, trading configuration, versioned persistence, IPC, process supervision, restart/command recovery, local diagnostics, and port reuse. |
| App launch smoke | A relocated app launched with private state and both managed child processes, rejected a second instance, completed a two-destination engine self-test, and stopped its owned processes. This does not verify real Discord/model/broker traffic. |
| Repository cleanup | `app/`, `engine/`, and `docs/` replace the former service/package layout. Server services, tracked deployment files, and obsolete plans were removed. Private files mounted by an existing installation are preserved and ignored. |

## Real integration checks — September 26

These bounded checks used isolated local state and the authorized disposable paper account. The existing trading deployment was not changed.

| Boundary | Observed result |
| --- | --- |
| Rebuilt runtime with notifications and diagnostics | Repeating the controlled-source workflow with the rebuilt bundle confirmed parser trade/review and execution skip notifications in their SQLite outboxes after real Telegram sends. Restart produced no duplicate outbox rows. The checked source, provider, broker, Telegram, and diagnostics credentials were absent from the recorded diagnostics, which flushed healthy with zero dropped records. |
| Discord → source SQLite | Actual login and bounded history recovery succeeded. Replaying the same message after restart kept one stored capture. It remained historical, with zero pending live deliveries; no Discord writes or broker execution were involved. |
| Controlled source → real model → paper execution owner | Production `TradingRuntime` used a synthetic source session, real DeepSeek HTTP, SQLite, and the real paper broker's read API. One live buy was parsed once, delivered, and durably skipped as `outside_session`. A historical capture never entered parsing/execution. Restart and duplicate delivery preserved the existing result. The harness recorded zero broker mutation attempts; a separate guard would have rejected any unexpected mutation. |
| Provider failure | An invalid provider credential produced a persisted `provider_rejected` review outcome while the paper account continued reconciliation cycles. |
| Paper broker adapter | The bundled adapter decoded account, asset, quote, and calendar responses; submitted one nonmarketable limit order; found the same order through repeated client-ID lookup; and confirmed cancellation. Final state: zero positions and zero open orders. This exercised broker operations directly, separately from application policy; it did not prove a fill or an application entry/exit cycle. |
| Close-only admission probe | On Saturday, the guarded disposable paper account had zero holdings/orders, shorting enabled, and a shortable AAPL asset. Two nonmarketable one-share sell requests with explicit `sell_to_close` returned HTTP 422: the broker inferred `sell_to_open` and rejected the intent mismatch. Client-ID lookup found no order; final holdings and open orders remained zero. This verifies admission rejection on an empty position, not fills or concurrent manual-sale behavior. The [order API](https://docs.alpaca.markets/us/v1.1/reference/postorder) exposes the intent field; ownership commit `57c33b2` now sends explicit position intent. |
| Explicit opening-intent adapter check | At `57c33b2`, the guarded disposable paper account normalized as ACTIVE/USD. The source adapter submitted AAPL quantity 1 at a $1 limit with `buy_to_open`; Alpaca returned that same intent and the same order on repeated client-ID lookup. Cancellation completed, with zero positions and open orders afterward. Market clock was closed and today's stock calendar empty. This is an adapter request/lookup/cancel check, not an application workflow or fill. |
| Telegram | The production notifier sent to the verified second testing channel. The API returned success and a message ID for the expected destination. This proves API acceptance, not a recipient read receipt. |

The market was closed during these checks. Actual paper fills and an app-driven entry/exit cycle require a market session. The fixtures do not establish parser accuracy across guru conventions, real multi-account behavior, or sustained capacity.

## Reviewed source change — per-connection sizing

Commits `27ab246`, `35b57dd`, and `c3ad1ac` add fixed/proportional sizing per guru-account connection, grounded optional source fractions, saved destination terms, typed missing-fraction review outcomes, and native settings/pre-risk previews. The full engine gate passed **599 tests, 2 skipped** before the final parser-only correction; that correction passed **57 parser/worker tests** and static checks. The app script suite passed **45 tests**, all **9 risk mutations** were caught, and the native contract executable exercised actual Save, reload, and Start methods with a version-2 profile and a non-network collaborator.

Independent review caught and then cleared native version validation, explicit-fraction omission, and compound-funding defects. Compound messages now retain their initial observed funding bound: fresh broker debits are not subtracted twice, stale balances do not expand the bound, and canceled unfilled reservations release. Later deposits do not increase an old automatic message's funding. No broker fill was attempted for this change.

## Reviewed source change — external ownership

Commits `57c33b2`, `6d48ab1`, and `f79ba2e` add separate external inventory, durable symbol incidents, conserved explicit ownership resolutions, account valuation/activity checks, and explicit broker order direction. Snapshot version 7 and execution SQLite revision 3 refuse earlier development formats. Resolutions use ledger allocation revisions, independent of wall-clock ordering. Account inspection exposes valuation and activity separately; app cost basis is not presented as aggregate broker exposure.

The initial full engine run passed **628 tests, 2 skipped**. Review fixes passed **427 execution tests**, then **84 focused checks** after final identity/schema tests; the final clearance correction passed **55 focused checks** and static gates. Independent review cleared account-wide exit admission, currency evidence, inter-read activity checks, persisted allocation validation, and post-clearance audit handling. Real SQLite rollback, reopen, cancellation, duplicate/conflicting resolutions, mixed 100 external + 50 app-owned shares, and retained audit evidence are covered with controlled brokers.

Broker HTTP observations are not an atomic snapshot: activity after the final read remains possible and subsequent reconciliation remains necessary. The real paper request/lookup/cancel probes above do not prove long-position fills or concurrent manual-sale behavior. Native ownership/lifecycle controls and rebuilt-app integration remained later checklist work at that commit; the later account-lifecycle source change is recorded below.

## Reviewed source change — account lifecycle

Commit `e3476fb` adds durable account pause/enable and recovery preferences, owner-backed account/activity/audit queries, strict private-pipe contracts, and native account actions. New accounts start disabled with manual recovery. Snapshot schema 8 and execution SQLite revision 4 replace the earlier development formats.

The implementer reported **135 focused Python tests passed**, then **24 affected tests passed** after final projection changes, with Ruff/Ty checks. The native contract executable exercised pending/error display, same-command retry, resume/status refresh, and lock clearing; the app built successfully. Independent review found two gaps: unpaged account lists and a lock race that could restore private data after a pending read. Commit `2fa6108` adds bounded account pages with a stable ID cursor and invalidates pending native reads/commands on lock. The focused fix gate passed **25 Python tests**, Ruff, Ty, the native contract executable with suspended-operation cases, and the app build; scoped re-review cleared both findings. Retained account discovery still scans directory entries per page, while response rows and opened ledgers are bounded. These are controlled-broker/source checks, not a rebuilt-app or real-market qualification.

## Reviewed source change — manual commands

Commit `5236423` adds immutable correction copies for selected accounts, read-only order previews, explicit confirmed commands, typed private IPC, and a native review sheet. The owner persists command and intent before broker submission, and a duplicate command reuses its result. Per-account outcomes are independent; compound same-account commands are checked in order. The implementer reports **68 focused Python tests passed**, and **710 passed, 2 skipped, 1 failed** in the full engine run. The architecture dependency failure reproduced at base `cb7a4de`; the separate fix is recorded below. Ruff, Ty, Swift build, and native contract actions passed; Independent review found five operator workflow gaps. Commits `aace50e` and `bc0ec2b` close them: partial correction retry preserves identity, stale preview refreshes use fresh IDs, a bounded source/account history page recovers uncertain results after lock or paused restart, selected accounts are isolated from unrelated corrupt ledgers, and the review sheet shows prior outcomes and owned lot references. The final full engine run passed **671, with 2 skipped**; Ruff, Ty, and strict Swift build/native contract checks passed across the respective changes. Re-review cleared all five findings. Minor broad-exception diagnostics and command-page sort cost remain for final triage. No real account order or fill was exercised for this change.

## Reviewed architecture boundary fix

Commit `763940c` moves the unchanged immutable `QueueSnapshot` value from execution to the shared package and updates its importers. Parsing no longer imports execution. The architecture test failed before the change and passed afterward without changing its rule. A focused run passed **33 tests**; the engine suite run from `engine/` passed **666, with 2 skipped**, and Ruff/Ty passed. Independent review found no blocking issue. The full repository gate remains a separate final check.

## Reviewed source change — profiles and guided setup

Commits `df57c88` and `34c1f41` add immutable guru/profile revisions, finite profile conventions, many-to-many destination terms, capability probes, typed native setup screens, and read-only historical evaluation. Review fixes `f238d5f` and `76a47d0` add an activation journal with activation-specific readiness evidence, saved live resume, an actual bounded Discord history-read probe, and example-driven suggestions and interpretation review before activation. An ambiguous Start retains both credential references until the engine's matching status can be reconciled; a mismatch remains review-only and cannot start trading. The source evaluator never opens an execution owner or creates an order outbox.

The final local gate passed **708 engine tests, 2 skipped**, Ruff, formatting, Ty, and **45 app-script tests**. The strict Swift build, Swift package test, and both directly run native contract executables passed their available checks. Independent review cleared four original workflow findings and a same-revision activation regression in a second scoped round. These checks used controlled fakes and local SQLite; real model accuracy and public noncoder Discord authorization remain unqualified. The latter is shown as an unsupported public authorization capability, while the retained existing source adapter remains available for controlled installations.

## Reviewed source change — diagnostic capture and evidence

Commits `a2d1ef0`, `704dd57`, and `ef3478a` add bounded original source-event and attachment evidence, actual model transport request/response capture, persisted workflow/destination/attempt identities, finite operation labels, and typed source activity records. Source-owned attachments use validated CDN origins, bounded streaming, private content-addressed files, and opaque read IDs; rejected attachments retain an explicit skipped status without a fetch. Diagnostic copies are redacted before they are queued or written and mark oversize, missing, or dropped captures as gaps. Review fix `3e51e5d` registers runtime-loaded credentials before source/model capture, including candidate validation and preview paths; a full in-memory registry disables payload capture with visible gaps while operational work continues.

The final local gate passed **737 engine tests, 4 skipped**, Ruff, formatting, Ty, and **45 app-script tests**. Strict arm64 Swift build/test and both directly run native contract executables passed their available checks. Independent review cleared the two credential and rejected-evidence findings.

## Reviewed source change — app unlock and lifecycle

Commits `0b99a32`, `9067ab6`, and `7fdecd3` give each actual app-window opening one macOS owner-auth session shared by protected native controls and Diagnostics. The menu exposes bounded health and Stop. Stop/Quit coordinate owned shutdown and show whether the engine acknowledged its drain, including forced local termination and the possibility of broker-accepted orders remaining open. A wake event refreshes status for an already-running supervisor without overriding deliberate Stop or durable account pause/recovery preferences.

Independent review cleared a stale window-auth race, a false graceful-drain message, missing native close-callback coverage, and a concurrent startup-cleanup/Stop race. The final `make desktop-check` passed: **753 engine tests, 4 skipped**, **45 app-script tests**, strict Swift build and package tests, native contract and DesktopCore harnesses with packaged runtime paths, and bundle verification. Controlled tests exercised the registered `NSWindow.willCloseNotification` callback, injected owner authentication, stale callbacks, shutdown failure, and wake generations. Real Touch ID/passcode, visible window close/reopen, OS sleep/wake, Keychain denial, and interactive AppKit Quit remain final macOS runtime gates; no account mutation was used.

## Restore activation — reviewed source

Through `9176081`, typed candidate preparation, read-only preflight, and one-time completion are connected to the native System controls. A focused restore coordinator retains ownership through Stop, generation switching, gated restart, activation, and rollback. Candidate inspection uses immutable SQLite reads to preserve its hash-bound tree; completion exits the gated process before a fresh writable engine starts. Account controls remain disabled with manual recovery. A typed inspection port separates activation policy from SQLite and archive inspection.

The engine suite passed **839 tests, 4 skipped**, Ruff lint/format and Ty passed, and **45 app-script tests passed**. The focused restore/pipe suite passed **52 tests**. Strict native compilation and **30 listed native checks** passed, with five runtime-dependent subchecks skipped because their paths were unset. One initial native run failed a stale-child assertion; the isolated case and full retry passed. Coverage includes lost preparation/completion replies, candidate-active restart, preflight rollback, failed pointer switching, and recovery without a live engine client. Independent restore review found no Critical or Important issues; recovery from a lost rollback-abort reply was carried into Task 10. No real broker or existing deployment was used for these restore checks.

## Controlled updates — reviewed source

Commit `a9d398b` connects user-chosen installation to package verification, writable-target preflight, atomic app-bundle exchange, retained recovery evidence, and replacement-process startup. Forward installation and rollback both preserve the normal app path through `RENAME_SWAP`. Package extraction uses an absent child destination, verified with an actual disposable `pkgbuild`/`pkgutil` fixture. Cleanup of superseded staged downloads was carried into Task 10.

Focused update checks, strict Swift compilation, native contract tests, and the unsigned app build and bundle verification passed. Tests cover tampering, exchange failure, partial-copy recovery, rollback, and replacement startup failure. Independent review found no Critical or Important issues. There is no configured Developer ID identity or trusted signed release artifact on this Mac: these local checks do not qualify signed installation, notarization, or distribution.

## External integration verification — September 27

Fresh read-only checks confirmed the verified disposable paper account is active, with no positions or open orders at the recorded baseline. Production capability probes successfully logged into the existing Zhao Discord source, read bounded history, and called the configured DeepSeek model. Telegram identified the configured destination as **2nd**. No messages or broker orders were sent in these checks. These results establish available inputs; the complete rebuilt-app workflow remains a separate acceptance gate.

A subsequent isolated run at `a9d398b` verified current engine imports against source hashes and exercised the production model, execution owner, SQLite outboxes, and notifier:

| Boundary | Observed result |
| --- | --- |
| Real source capture | The authorized 120-second Discord recovery window was empty. A separate read of exactly one older, attachment-free item persisted it as historical; replay retained one row and the same workflow/trace identities. It never entered parsing or execution. |
| Controlled source → real DeepSeek → paper owner | Public account resume changed disabled/manual to enabled/manual after reconciliation. One synthetic message was parsed and persisted once, ending in one durable `outside_session` outcome. All **125 broker requests were GET/paper**, with zero attempted mutations and unchanged positions/open orders. |
| Telegram and restart | Telegram **2nd** accepted two notifications. Parser and signal outboxes drained; restart preserved the existing outcome and sent **zero duplicates**. |

The disposable backend and source databases were cleaned up. This verifies current engine source with the pinned backend, independently of the final rebuilt app. It does not establish fills, an entry/exit cycle, multi-account broker behavior, general parser accuracy, or workload capacity.

The rebuilt unsigned bundle at `dad0158` repeated this chain using its own CPython and packaged engine. Import origins and critical module hashes matched the current source, including the manual-recovery correction. It again recorded one real DeepSeek interpretation, one durable `outside_session` outcome, two accepted Telegram notifications, no restart duplicates, 125 paper GET requests and zero mutation attempts. The real Discord recovery window was empty. Bundle integrity verification passed both before and after the run. This qualifies the packaged engine for that bounded scenario; it does not qualify visible native interaction or market fills.

A separate fresh paper-adapter probe submitted exactly one AAPL `buy_to_open` order for one share at a $1 DAY limit. Repeated client-ID lookups returned the same order, and cancellation reached `canceled`. The guarded run made one POST, one DELETE, and 17 GETs; it ended with zero positions and zero open orders in the verified disposable account. This establishes request/lookup/cancel behavior for the current adapter, separately from application policy and fills.

## Known local limitations

- Manual-command history is paged for display but still sorts retained commands in memory. Account listing scans retained account directories. Large retained histories therefore need separate latency and capacity qualification.
- The telemetry worker polls its idle queue every 10 ms and uses a bounded shutdown join. This remains an idle-wakeup and shutdown-latency limitation.
- Successful update completion attempts to remove its staged package. A filesystem deletion error can leave that package behind; cleanup failure does not reverse the installed update.
- `OrderTerms` still infers position intent when omitted. Current execution and broker callers supply it explicitly, and persisted snapshots require it. Remove that constructor fallback before adding new position directions or exposing this type as an external input.

## Remaining product and distribution gates

The local checks above qualify their recorded scenarios only. Public release still needs a supported noncoder Discord authorization flow; clean-device installation; signing, notarization, and trusted signed-update handoff; three noncoder trials; five paper market sessions with actual application entry/exit fills; real multiple-account broker behavior; separately authorized live qualification; Real Touch ID/passcode, visible window close/reopen, OS sleep/wake, Keychain denial, and interactive Quit also remain unqualified. Controlled native tests and packaged integration do not replace those checks.

Use `make check`, `make desktop-check`, and `make desktop-smoke` for the current local gates. These checks do not submit real orders unless a deliberately configured runtime action is invoked. Keep private credentials and operational data out of test artifacts.
