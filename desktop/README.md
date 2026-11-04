# CopyTrading desktop (Electron + React)

The new UI for the Python engine in `../engine`. React on ReUI/shadcn, English only, no unlock gate. The
engine is unchanged; the app talks to it over the same JSON-lines pipe the SwiftUI app uses.

```
shared/contract.ts      every operation, with request and reply types: the one file both sides import
electron/main/          main process: engine lifecycle, the setup file, the key store, confirmations
electron/preload/       exposes window.copytrading (read.*, act.*, engine.*) and nothing else
src/features/<name>/    one folder per screen; src/features/shell/ is the frame
src/components/         ui/ (shadcn) and reui/ (ReUI): reuse, don't restyle
tests/                  vitest; a fake engine process in tests/fake-engine.cjs
```

`npm run dev` starts the app on a throwaway engine (needs a Python runtime with the engine's dependencies:
`dist/desktop-runtime/prepared`, else the installed app's, read-only; or set `COPYTRADING_PYTHON`).
`npm test`, `npm run typecheck`, `npm run build` are the CI gates.

## Add a screen

1. Add its id to `SCREEN_IDS` in `src/features/shell/route.ts` (skip if it already has one; every screen in the
   sidebar does). The route is `location.hash`: `#/gurus`, `#/accounts/<id>`.
2. In `src/features/shell/screens.tsx` replace its `render` with your component. Title and icon come from the same
   entry; the sidebar and breadcrumb read them. `route.id` is the second segment.
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
`confirmManualOrders`, `confirmLotSale`, `startTrading`, `pauseTrading`, `controlAccount`, `approveProposal`,
`deleteAccountRecord`, `completeRestoreCandidate`, `updateAccountLimits` (it changes copying at once; the dialog
lists each limit before and after). The page cannot skip or reword the dialog: main builds its text from what
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
- Keys (Discord token, model key, each account's Alpaca key and secret) live encrypted with Electron `safeStorage` in
  `userData`. The renderer writes them with `act.setSecrets` and sees only `read.getSecretStatus()` (booleans).
  Main adds them to the engine request for `validateTrading`, `startTrading`, `checkConnection`,
  `learnGuruPlaybook`, `evaluateHistoricalProfile` and `assistantAsk`, overriding anything the page sent, and
  withholds any reply or error that contains a stored key (the engine's stopped-reason is redacted the same way).
  Never log or render them.

## Engine and safety

Main starts the engine on launch, shows its state in the sidebar footer (`window.copytrading.engine`), and on quit
asks it to stop, then terminates, then kills it, as `ProcessSupervisor.swift` does. Dev and tests use a throwaway
data folder under `$TMPDIR`; `engine/safety.ts` refuses the owner's `~/Library/Application Support/CopyTrading`.
Never point an engine at it.

## Fixtures and capture

`COPYTRADING_FIXTURES=1` serves the account captured on 2026-11-03 (`electron/main/fixtures/`, real engine shapes)
instead of an engine; operations without a fixture answer "is not in the captured fixtures". Add a read there by
adding it to `READS` in `fixtures.ts`.

`npm run capture` builds, then opens the app offscreen (no window, no focus) and saves light and dark PNGs to
`dist/capture/`. Add a screen with a `[name, env]` pair in `scripts/capture.mjs`; set
`COPYTRADING_CAPTURE_HASH` to its route. Read the PNGs: they are the visual check. `node scripts/capture.mjs settings logs`
captures only the entries whose name has one of those words; `COPYTRADING_CAPTURE_SCRIPT` runs a page script first (the
assistant panel and the time zone list open that way). Fixtures can also serve acts (`ACTS` in `fixtures.ts`), and
`COPYTRADING_FIXTURE_STATE=pending-restore` shows a half-finished restore.

## Settings and the assistant

`src/features/settings/` is Settings (`#/settings/general|agents|backups|logs`; the journal is read by main from the
engine's log folder, newest 2000 records, `electron/main/journal.ts`). `src/features/assistant/` is the assistant panel,
mounted once in the sidebar (⌘J). The time zone lives in `src/lib/time-zone.ts` and `format.ts` reads it. A request only the
app can carry out (a setup change) cannot be approved yet: main refuses it, the pages offer Reject only.

## Pictures

A post's captured pictures reach the page as `ct-picture://<evidence_id>` (`electron/main/pictures.ts`). Main notes each
attachment the engine reports as its reply passes through, and serves a file from `<data dir>/attachments/<sha[:2]>/<sha>`
only when its size and SHA-256 match that record, it is a plain raster picture, and the path is not a link; anything else is a 404.
The page never supplies the size or hash. Use `<PostPicture attachment={...}>`; fixture mode writes one picture to a temp folder.

## Not here yet

- `stop`, `control`, `authorize_setup`, `attach_account_readers`, `detach_account_readers` stay main-only (lifecycle,
  the agent-socket relay, paused-account readers); no page may send them.
- The start journal (`pendingActivation` stage, finalize, rollback) and the setup upgrade: `setup-file.ts` reads and
  preserves a pending start but does not create one.
- Moving the owner's Keychain items into the key store, a persistent data folder, and the packaged-app flag that
  allows the owner's folder: wave 3.
- Restarting a crashed engine: the footer says why it stopped.
