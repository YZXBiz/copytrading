# CopyTrading desktop (Electron + React)

The new UI for the Python engine in `../engine`. React, English only, no unlock gate. The
engine is unchanged; the app talks to it over the same JSON-lines pipe the SwiftUI app uses.

```
shared/contract.ts      every operation, with request and reply types: the one file both sides import
electron/main/          main process: engine lifecycle, the setup file, the key store, confirmations
electron/preload/       exposes window.copytrading (read.*, act.*, engine.*) and nothing else
src/features/<name>/    one folder per screen; src/features/shell/ is the frame
src/components/         arc/ (the component set) and icons/: reuse, don't restyle
tests/                  vitest; a fake engine process in tests/fake-engine.cjs
```

`npm run dev` starts the app on a throwaway engine (needs a Python runtime with the engine's dependencies:
`dist/desktop-runtime/prepared`, else the installed app's, read-only; or set `COPYTRADING_PYTHON`).
`npm test`, `npm run typecheck`, `npm run build` are the CI gates.

## Add a screen

1. Add its id to `SCREEN_IDS` in `src/features/shell/route.ts` (skip if it already has one; every screen in the
   sidebar does). The route is `location.hash`: `#/gurus`, `#/accounts/<id>`.
2. In `src/features/shell/screens.tsx` replace its `render` with your component. Title and icon come from the same
   entry; the sidebar and the top bar's title read them. `route.id` is the second segment.
3. Put the screen in `src/features/<name>/`, named per component (`GuruPage.tsx`). Link with
   `<a href={href("gurus", id)}>` or `navigate("gurus", id)`.

## Call a read

```tsx
const posts = useResult(() => window.copytrading.read.getGuruActivity({ guru_id }), guru_id)
// posts.status: "loading" | "error" | "ready" (posts.data), posts.retry()
```

Every call returns `Result<T>`: `{ ok: true, value }` or `{ ok: false, error }`. Errors are sentences for the
owner. Field names are the engine's (snake_case); money arrives as decimal strings, so format them with
`src/lib/format.ts`. Untrusted text (Discord posts) renders as text, never HTML.

To add a read the contract lacks: its types in `ReadOperations`, its name in `READS` (the compiler checks the two
match), and a handler in `READ_HANDLERS` in `electron/main/api.ts`, usually one line: `ask("engine_op", value("reply_key"))`.

## Call an action

```tsx
const result = await window.copytrading.act.confirmLotSale({ sale })
if (!result.ok && result.cancelled) return // the owner pressed Cancel; show nothing
```

These actions show a native dialog from the main process first, and send nothing to the engine on Cancel:
`confirmManualOrders`, `confirmLotSale`, `startTrading`, `applyChanges`, `pauseTrading`, `controlAccount`, `approveProposal`,
`deleteAccountRecord`, `activateRestore`, `rollbackRestore`, `setAgentAccess`, `updateAccountLimits` (it changes copying at once;
the dialog lists each limit before and after). A restore is only for a backup this session previewed (`previewRestore`) or a
half-finished one the engine holds, and is refused while a start, an unstarted saved setup or unsaved typed keys exist. The page cannot skip or reword the dialog: main builds its text from what
the engine said or the saved setup holds, not from the request.

- An order is confirmed after a preview in the same session: call `read.previewLotSale` / `read.previewManualOrder`
  first. Main keeps the plan the engine returned and words the dialog from it ("Sell 2.052463 SOXS at $40.45 or
  better from zhap-account-2?"). Confirming an order it never saw is refused.
- `approveProposal` sends the digest the engine holds; the page's is ignored.
- A preview id is used once: previewing again needs a new id.
- `startTrading` starts the **saved** setup and keys as main read them when the dialog opened, never ones in the request.

Other actions (`validateTrading`, `checkConnection`, `saveSetup`, backups, …) place no order and change nothing copying does.
A new action that moves money or changes copying must be added to `ACT_HANDLERS` through `confirmed(...)`, with its
wording in `confirmations.ts` and a case in `tests/api.test.ts`.

## Setup and keys

- The setup is `trading-configuration.json` in the engine's data folder, in the format the SwiftUI app writes
  (`electron/main/setup-file.ts`; `tests/fixtures/` has one). `read.getSetup()` returns it with the engine's
  `revision` and whether its keys are in this app. Starting is `act.validateTrading({ configuration })`, then
  `act.saveSetup({ configuration, revision: report.configuration_revision })` (only while paused), then
  `act.startTrading({ activation_id, validation_token })`. `act.updateAccountLimits` changes limits while copying
  (after a confirmation).
- A start is journaled in the setup file, as `TradingConfigurationStore.swift` does: `startTrading` stages the saved setup
  as a pending start (with the setup before it), sends it, then looks at the engine's own record (`get_trading_activation`)
  with `AppModel.reconcilePendingTradingActivation`'s rules: committed → finalized, stopped without committing → the setup
  before it is saved again and the error names the account or service (`shared/start-failure.ts`), anything else stays
  pending until the next `getSetup` or `getStatus` read settles it (the page polls `getSetup` while a start is pending). A
  committed start also resumes each account the engine holds with buys off, as `turnOnEveryAccount` does: the start's
  dialog named every account, so that asks nothing more. A Cancel in the dialog puts the setup before the save back.
  The page's state for all of this, and the setup form, is `src/features/connections/setup-store.ts`.
- `applyChanges` is the same start while copying runs (`AppModel.applyChangesWhileCopying`): one confirmation, then main
  pauses, validates, saves and starts the new setup, and when a check fails or the start does not take it starts the saved
  setup again (no second dialog) and gives back the buys of the accounts that were buying. A key the change lacks is
  refused before anything pauses.
- Keys the owner types are held by `act.setSecrets` in main's memory only. `SecretStore.stage()` writes them to disk with
  the keys before them when a start is journaled, `settle()` drops the old ones once the engine commits, and `rollback()`,
  a Cancel (`discard()`), a refused start, or `act.discardSecrets` ("Discard changes") leaves the file as it was; a crash
  mid-start leaves both on disk for the next launch's reconcile.
- Keys (Discord token, model key, each account's Alpaca key and secret, once a start has saved them) live encrypted with Electron `safeStorage` in
  `userData`. The renderer writes them with `act.setSecrets` and sees only `read.getSecretStatus()` (booleans).
  Main adds them to the engine request for `validateTrading`, `startTrading`, `checkConnection`,
  `learnGuruPlaybook`, `evaluateHistoricalProfile` and `assistantAsk`, overriding anything the page sent, and
  withholds any reply or error that contains a stored key (the engine's stopped-reason is redacted the same way).
  Never log or render them. The model key is sent only to a request naming the provider it was typed for
  (`SecretUpdate.provider_name`), and `validateTrading` / `startTrading` send only the accounts the setup has.

## Engine and safety

Main starts the engine on launch, shows its state in the sidebar footer (`window.copytrading.engine`), and on quit
asks it to stop, then terminates, then kills it, as `ProcessSupervisor.swift` does. Dev and tests use a throwaway
data folder under `$TMPDIR`; `engine/safety.ts` refuses the owner's `~/Library/Application Support/CopyTrading`.
Never point an engine at it. Only the built app (`app.isPackaged`) runs on it, through `engine/data-root.ts`;
`COPYTRADING_STATE_ROOT=<existing folder under $TMPDIR>` gives the built app a throwaway folder instead, and with
`COPYTRADING_SMOKE=1` it quits 0 once the page loaded and the engine answered.

The engine holds no broker keys of its own until copying starts, so main hands it each saved account's keys with
`attach_account_readers` (`electron/main/readers.ts`, `AccountReaders`): after every engine start, and after any action that saves the
setup or changes its keys. They go from the key store to the engine only. Without them a paused account has no balance, history or live
price (`get_equity_history` and `get_quote` answer `not_found`). The engine's stderr is kept in `logs/engine.log` (256 KB, then
`engine.log.1`) beside the diagnostics journal.

## Background duties (main process)

- **Installation folder** (`engine/paths.ts`, port of `RuntimePaths.swift`): `installation-id`, `active-generation`,
  `generations/<uuid>/` (the engine's `--data-dir`), `logs/`, `control/cli.sock`, `agent-access.json`, `preferences.json`.
  `data-root.ts` picks the folder (dev: a fresh one under `$TMPDIR`, `ct-…`, removed at quit; the packaged app: the owner's, or
  `COPYTRADING_STATE_ROOT`). The engine is started again on whichever generation is active (`engineTarget`), and `EngineProcess`
  can be started again after a stop.
- **Agent connection** (`agents/`): `AgentAccessController` owns `agent-access.json` (`off | read_pause | propose`) and the
  socket, `AgentRelay` serves the `copytrading` CLI and MCP server: one JSON line per connection, 64 KB, 4 at once, 30 s,
  folder 0700 and socket 0600, lines sent as the engine's `control` operation with the owner's level. Setup operations are
  answered "cannot change its setup from here". `tests/relay.test.ts` runs the real CLI's `status` against a relay (needs `uv`).
- **Keychain move** (`keychain-move.ts`): once, when the saved setup names keys the store does not hold, reads the SwiftUI
  app's item with `/usr/bin/security` and moves it into the store. macOS may ask the owner to allow it. The Keychain item
  is left alone.
- **Restore** (`restore.ts`, port of `RestoreActivationCoordinator.swift`): `act.activateRestore` / `rollbackRestore` stop the
  engine, switch the generation pointer, start on the candidate, check the broker, complete, restart; any failure switches back.
- **Notifications** (`alerts/`): `AlertMonitor` polls a running engine every 2 s and posts macOS notifications for fills,
  an agent's request, an account that stopped, and copying paused after a quit. Closing the window leaves it all running;
  quitting stops the relay, the monitor, then the engine.
- **Crash restarts** (`engine/supervise.ts`): an engine that exits without being asked to stop is started again, 1 s later, up
  to 3 times (`ProcessSupervisor.swift`); copying resumes if it was on (the update relaunch's `resumeCopying`). After the last
  failure the footer shows the engine's reason and a notification says so. A restore or a quit owns the engine meanwhile.
- **One app at a time**: the packaged app takes `app.requestSingleInstanceLock()`; a second launch quits and the first one
  comes forward, with a new window if it had been closed.

## Fixtures and capture

`COPYTRADING_FIXTURES=1` serves the account captured on 2026-11-03 (`electron/main/fixtures/`, real engine shapes; the
saved setup is `fixtures-setup.ts`, a first run with `COPYTRADING_FIXTURE_SETUP=none`, copying paused with
`COPYTRADING_FIXTURE_TRADING=paused`)
instead of an engine; operations without a fixture answer "is not in the captured fixtures". Add a read there by
adding it to `READS` in `fixtures.ts`.

`npm run capture` builds, then opens the app offscreen (no window, no focus) and saves light and dark PNGs to
`dist/capture/`. Add a screen with a `[name, env]` pair in `scripts/capture.mjs`; set
`COPYTRADING_CAPTURE_HASH` to its route. Read the PNGs: they are the visual check. `node scripts/capture.mjs settings logs`
captures only the entries whose name has one of those words; `COPYTRADING_CAPTURE_SCRIPT` runs a page script first (the
assistant panel and the time zone list open that way). Fixtures can also serve acts (`ACTS` in `fixtures.ts`), and
`COPYTRADING_FIXTURE_STATE=pending-restore` shows a half-finished restore, `agents-problem` an agent socket that could not open.

## Settings and the assistant

`src/features/settings/` is Settings (`#/settings/general|agents|backups|logs`; the journal is read by main from the
engine's log folder, newest 2000 records, `electron/main/journal.ts`). `src/features/assistant/` is the assistant, docked on the
right of the page and opened by the header's Assistant button or ⌘J. The time zone lives in `src/lib/time-zone.ts` and `format.ts` reads it. A request only the
app can carry out (a setup change) cannot be approved yet: main refuses it, the pages offer Reject only.

An account page opens its sheet from the route, so a capture can show one: `#/accounts/<id>?open=review|sale|limits`.
`COPYTRADING_FIXTURE_SCENE=attention` serves the states the captured account never had (a stopped account, a holdings
mismatch). `calls` puts six calls waiting for the owner on the page, `quiet` none; `busy` adds a dozen posts to Nov 3 and `empty` serves no posts at all (Activity and the guru page). `COPYTRADING_CAPTURE_SIZE=1280x860` captures a window
of that size instead of one tall page. Capture waits until no region is still loading before it saves.

## Theme and window

The desk opens dark. Settings > General has Dark, Light and System (`getTheme` / `setTheme`, saved in `preferences.json`).
Main sets `nativeTheme.themeSource` from it before the window exists, so the page's `prefers-color-scheme` and macOS
vibrancy are right at first paint; `src/main.tsx` only follows that media query. The window has a hidden title bar
(`hiddenInset`, traffic lights inset in the sidebar), a `sidebar` vibrancy material and a transparent background: `body`
is transparent so the sidebar shows the desktop through its `--sidebar` fill, and the page paints `--background` itself. A capture
renders offscreen, where there is no desktop, so it paints `--window` instead. The top bar and the strip above the
sidebar logo are drag areas; anything pressable inside is `no-drag` (one rule in `index.css`). The window is at
least 980×640.

## Design foundation

`src/components/arc/` holds the shared foundation (`foundation.css`, motion presets) and the pieces built on it: the sidebar
frame, the ⌘K search, the notice stack and the dialog. `foundation.css` is imported once, in `src/index.css`, inside a
layer that sits below Tailwind's, so the screens that still use the older components keep their own tokens and sizes
until they move. `index.css` maps the foundation's semantic names (`--surface`, `--text-secondary`, `--accent`, `--danger`,
the control tokens) onto the desk's own colours, in dark (the default) and light, with the indigo accent in both; the older
hover fill that was called `--accent` is `--ui-accent` now. `main.tsx` sets both the `dark` class and `data-theme`. Fonts are
Geist (`--font-geist`) and Inter (`--font-inter`), bundled with fontsource; the new pieces set Inter on their own roots.

## Rolling numbers

The balance, the stat strip and the chart's hover readout are `<RollingNumber>`
(`src/components/rolling-number.tsx`, NumberFlow): digits roll to a new value, in the direction it moved, and the first
render and Reduce Motion show the number at once. It formats with the `*_OPTIONS` in `balance-panel/format.ts`, the same
ones the text formatters use. To watch it, build with `npx electron-vite build --mode tick` and set
`COPYTRADING_FIXTURE_TICK=1` (with `COPYTRADING_FIXTURES=1`): every accounts read moves the balance. A normal build has no
tick. `COPYTRADING_CAPTURE_FRAMES=<n>` saves n frames in a row after the capture script (`node scripts/capture.mjs account-roll`).

## Live prices, the fill toast and logos

- **Live prices.** The account page's Positions ask for each held stock's quote through the account's read keys
  (`getQuote`) every 5 s while the window is visible, and stop while it is hidden (`src/lib/visible-interval.ts`,
  `features/live/`). The price rolls, the row's value and gain are recomputed from it, and the row flashes green or red
  for under 600 ms (`TickFlash`, opacity only; none with Reduce Motion). A quote older than two minutes is not live.
  `COPYTRADING_FIXTURE_TICK=1` in a tick build also moves the fixture quote (`node scripts/capture.mjs account-live-tick`).
- **Sparklines.** Each Positions row shows a 1-day line from `getBars`: the five-minute IEX
  bars of the stock's latest session (Alpaca, through the account's read keys; the engine caches each symbol for 60 s),
  asked once for all held stocks every minute while the window is visible (`features/account/use-bars.ts`). The line is
  the gain color when the session closed at or above its first open, the loss color below it; a stock with no bars shows
  no line. The fixtures serve real SOXL and SOXS bars of Nov 4 (`electron/main/fixtures/bars.json`).
- **Guru performance.** A guru's page opens with what their copied sales made (`getGuruPerformance`): the
  cumulative realized line, realized, unrealized, win rate, best and worst call, or "No closed trades yet". The engine
  reads it from the account's ledger and journal, replaying each sell through the ledger's own lot reduction; a sale it
  cannot match to its buys is counted as unmatched and left out. The captured account has no sales, so
  `COPYTRADING_FIXTURE_SCENE=performance` serves synthetic figures for the capture (`node scripts/capture.mjs guru-performance`).
- **Fill toast.** The alert monitor's fill notes also go to the page as `engine:fill`; `FillToasts` shows a stacked notice (newest in front, spread open under the pointer, View opens the account).
  The macOS banner shows only when no window is focused.
- **Logos.** `<SymbolLogo>` shows `ct-logo://<SYMBOL>` (`electron/main/logos.ts`): main fetches
  `assets.parqet.com/logos/symbol/<SYMBOL>?format=png` once, keeps it in `<userData>/logos/`, and asks again for a ticker
  Parqet lacks no sooner than a day later. Only the ticker is sent. A miss is a 404 and the page shows a letter tile;
  fixture mode never reaches the network, so its captures show letter tiles.

## Pictures

A post's captured pictures reach the page as `ct-picture://<evidence_id>` (`electron/main/pictures.ts`). Main notes each
attachment the engine reports as its reply passes through, and serves a file from `<data dir>/attachments/<sha[:2]>/<sha>`
only when its size and SHA-256 match that record, it is a plain raster picture, and the path is not a link; anything else is a 404.
The page never supplies the size or hash. Use `<PostPicture attachment={...}>`; fixture mode writes one picture to a temp folder.

## Not here yet

- `stop`, `control`, `authorize_setup`, `attach_account_readers`, `detach_account_readers` stay main-only (lifecycle,
  the agent-socket relay, paused-account readers); no page may send them.
- The setup upgrade from an earlier version: `setup-file.ts` refuses such a file and says so.
- Packaging: `make desktop-build` builds `dist/CopyTrading.app` (`app/scripts/build_desktop.py`; the packaged app
  runs on the owner's data folder, `engine/data-root.ts`; updates in `update.ts`; see `docs/releases.md`).
- The installation lock (`.app.lock`) that keeps this app and the SwiftUI app off one folder: only Electron's
  single-instance lock guards the packaged app, so quit the SwiftUI app first.
- Resetting the crash-restart count: like `ProcessSupervisor.swift`, 3 restarts per run of the app, however long the engine ran between them.
