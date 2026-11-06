// Opens the built app offscreen once per screen and saves light and dark PNGs of each to dist/capture:
// the account page, its sheets and the screens on fixtures, then live runs on a throwaway data dir (empty states).
// Add a screen: add a [name, env] pair with COPYTRADING_CAPTURE_HASH set to its route, and
// COPYTRADING_CAPTURE_CLICK to a selector to press first (a sheet), or COPYTRADING_CAPTURE_SCRIPT to a page script
// for a panel that needs more than one press. Never shows a window or takes focus.
// `node scripts/capture.mjs settings logs` captures only the entries whose name contains one of the words.
import { spawnSync } from "node:child_process"
import { mkdtempSync, rmSync } from "node:fs"
import { createRequire } from "node:module"
import { tmpdir } from "node:os"
import { join, resolve } from "node:path"

const electron = createRequire(import.meta.url)("electron")
const out = resolve("dist/capture")
const fixtures = { COPYTRADING_FIXTURES: "1" }
const zhao = encodeURIComponent("赵哥")

// A page script that clicks the first element whose text starts with `text`, then waits `ms`.
const click = (selector, text, ms = 800) =>
  `(async () => { const el = [...document.querySelectorAll(${JSON.stringify(selector)})].find((e) => e.textContent.trim().startsWith(${JSON.stringify(text)})); el.click(); await new Promise((r) => setTimeout(r, ${ms})) })()`
const settings = (page, extra = {}) => ({ ...fixtures, COPYTRADING_CAPTURE_HASH: `#/settings/${page}`, ...extra })
// Base UI opens a combobox on a full press, not on a bare click event.
const openTimeZones = `(() => { const t = document.querySelector('[data-slot="input-group-button"]'); for (const type of ["pointerdown", "mousedown", "pointerup", "mouseup", "click"]) t.dispatchEvent(new MouseEvent(type, { bubbles: true, button: 0 })) })()`
const askAssistant = `(async () => { await ${click("button", "Assistant", 1500)}; const s = [...document.querySelectorAll("button")].find((e) => e.textContent.includes("What's in my paper account?")); s.click(); await new Promise((r) => setTimeout(r, 3000)) })()`

// ⌘K opens the search; its posts need a moment to load.
const pressSearch = `window.dispatchEvent(new KeyboardEvent("keydown", { key: "k", metaKey: true, bubbles: true })); await new Promise((r) => setTimeout(r, 1500))`

// Getting Started and Connections: a first run, a saved setup that is paused, one that is copying, and each editor sheet
// (#/settings/connections/<discord|interpreter|account:N|guru:N> opens it).
function setupCaptures() {
  const fixture = (hash, setup, trading) => ({
    ...fixtures,
    COPYTRADING_CAPTURE_HASH: hash,
    COPYTRADING_FIXTURE_SETUP: setup,
    COPYTRADING_FIXTURE_TRADING: trading,
  })
  // Each screen at 1280×860 and at the SwiftUI app's 980-wide minimum, in each state the screen has.
  const screens = [
    ["getting-started", "#/getting-started", ["first-run:none:paused", "saved:saved:paused", "copying:saved:running"]],
    ["connections", "#/settings/connections", ["first-run:none:paused", "saved:saved:paused", "copying:saved:running"]],
  ]
  const sized = screens.flatMap(([screen, hash, states]) =>
    states.flatMap((state) => {
      const [label, setup, trading] = state.split(":")
      return ["1280x860", "980x860"].map((size) => [`${screen}-${label}-${size}`, { ...fixture(hash, setup, trading), COPYTRADING_CAPTURE_SIZE: size }])
    }),
  )
  const broken = [["getting-started", "#/getting-started"], ["connections", "#/settings/connections"]].flatMap(([screen, hash]) =>
    ["error", "loading"].flatMap((state) =>
      ["1280x860", "980x860"].map((size) => [`${screen}-${state}-${size}`, { ...fixture(hash, "saved", "paused"), COPYTRADING_FIXTURE_STATE: `reads-${state}`, COPYTRADING_CAPTURE_SIZE: size }]),
    ),
  )
  return [
    ...sized,
    ...broken,
    // Scrolled to the end: the last section must clear the floating setup bar.
    ...["1280x860", "980x860"].map((size) => [
      `connections-first-run-end-${size}`,
      {
        ...fixture("#/settings/connections", "none", "paused"),
        COPYTRADING_CAPTURE_SIZE: size,
        COPYTRADING_CAPTURE_SCRIPT: `(async () => { const r = document.querySelector('[role="region"]'); r.scrollTop = r.scrollHeight; await new Promise((x) => setTimeout(x, 700)) })()`,
      },
    ]),
    ["footer-degraded", fixture("#/accounts/zhap-account-2", "saved", "degraded")],
    ["sheet-discord", fixture("#/settings/connections/discord", "saved", "paused")],
    ["sheet-interpreter", fixture("#/settings/connections/interpreter", "saved", "paused")],
    ["sheet-account", fixture("#/settings/connections/account:0", "saved", "paused")],
    ["sheet-account-copying", fixture("#/settings/connections/account:0", "saved", "running")],
    ["sheet-guru", fixture("#/settings/connections/guru:0", "saved", "paused")],
    // The real engine on a throwaway data folder: a first run reads its status and the (absent) setup.
    ["live-connections", { COPYTRADING_CAPTURE_HASH: "#/settings/connections" }],
  ]
}

// Posts in the fixtures, oldest first: 3 a skipped sell, 5 a buy that timed out, 6 a picture, 8 a fill, 9 a post waiting for the owner.
for (const [name, env] of [
  ["fixture", fixtures],
  // The balance rolling to a new value: needs a build made with `electron-vite build --mode tick` (a normal build has no tick); COPYTRADING_FIXTURE_TICK moves it on every 5 s read, and the script waits for the figure to change.
  [
    "account-roll",
    {
      ...fixtures,
      COPYTRADING_FIXTURE_TICK: "1",
      COPYTRADING_CAPTURE_FRAMES: "3",
      COPYTRADING_CAPTURE_SIZE: "1280x860",
      COPYTRADING_CAPTURE_HASH: "#/accounts/zhap-account-2",
      COPYTRADING_CAPTURE_SCRIPT: `(async () => { const read = () => document.querySelector("main [data-rolling] > [aria-label]").getAttribute("aria-label"); const before = read(); for (let i = 0; i < 300 && read() === before; i++) await new Promise((r) => setTimeout(r, 40)) })()`,
    },
  ],
  // A held row's live price ticking: needs the same tick build. Waits for the first held row's gain to change (a read every 5 s),
  // then saves frames while its row flashes and the digits roll.
  [
    "account-live-tick",
    {
      ...fixtures,
      COPYTRADING_FIXTURE_TICK: "1",
      COPYTRADING_CAPTURE_FRAMES: "3",
      COPYTRADING_CAPTURE_SIZE: "1280x1500",
      COPYTRADING_CAPTURE_HASH: "#/accounts/zhap-account-2",
      COPYTRADING_CAPTURE_SCRIPT: `(async () => { const read = () => [...document.querySelectorAll("ul li")].find((e) => e.innerText.includes(" shares"))?.querySelector("[data-rolling] > [aria-label]")?.getAttribute("aria-label"); await new Promise((r) => setTimeout(r, 1500)); const before = read(); for (let i = 0; i < 400 && read() === before; i++) await new Promise((r) => setTimeout(r, 40)) })()`,
    },
  ],
  // The guru's stops (docs/adr/0015): the switch off (the default) and on in the account's limits, a holding with a stop on the account page
  // and the stock's page, and a stop post resting at Alpaca (12), filled (9), and skipped because the account does not follow stops ("stops-off").
  ...["1280x860", "980x860"].flatMap((size) => {
    const win = { ...fixtures, COPYTRADING_CAPTURE_SIZE: size }
    const on = { ...win, COPYTRADING_FIXTURE_SCENE: "stops" }
    const toSwitch = `(async () => { document.getElementById("behavior-follow_stops").scrollIntoView({ block: "center" }); await new Promise((r) => setTimeout(r, 400)) })()`
    return [
      [`stops-limits-off-${size}`, { ...win, COPYTRADING_CAPTURE_HASH: "#/accounts/zhap-account-2?open=limits", COPYTRADING_CAPTURE_SCRIPT: toSwitch }],
      [`stops-limits-on-${size}`, { ...on, COPYTRADING_CAPTURE_HASH: "#/accounts/zhap-account-2?open=limits", COPYTRADING_CAPTURE_SCRIPT: toSwitch }],
      // Holdings sit below the first screen, so the account page is also captured tall.
      [`stops-account-${size.replace("860", "1500")}`, { ...on, COPYTRADING_CAPTURE_SIZE: size.replace("860", "1500"), COPYTRADING_CAPTURE_HASH: "#/accounts/zhap-account-2" }],
      [`stops-stock-${size}`, { ...on, COPYTRADING_CAPTURE_HASH: "#/stock/SOXL?account=zhap-account-2" }],
      [`stops-activity-${size}`, { ...on, COPYTRADING_CAPTURE_HASH: "#/activity" }],
      [`stops-post-placed-${size}`, { ...on, COPYTRADING_CAPTURE_HASH: "#/activity/12" }],
      [`stops-post-filled-${size}`, { ...on, COPYTRADING_CAPTURE_HASH: "#/activity/9" }],
      [`stops-post-off-${size}`, { ...win, COPYTRADING_FIXTURE_SCENE: "stops-off", COPYTRADING_CAPTURE_HASH: "#/activity/9" }],
    ]
  }),
  ["account-review", { ...fixtures, COPYTRADING_CAPTURE_HASH: "#/accounts/zhap-account-2?open=review" }],
  ["account-sale", { ...fixtures, COPYTRADING_CAPTURE_HASH: "#/accounts/zhap-account-2?open=sale" }],
  ["account-limits", { ...fixtures, COPYTRADING_CAPTURE_HASH: "#/accounts/zhap-account-2?open=limits" }],
  // The account page in a 1280×860 window, at the SwiftUI app's 980-wide minimum, and as one tall page ("full"):
  // no waiting calls, the two the captured account has, and six.
  ...["quiet", "", "calls"].flatMap((scene) => ["1280x860", "1440x900", "980x860", ""].map((size) => [scene, size])).map(([scene, size]) => [
    `account-${scene || "default"}-${size || "full"}`,
    { ...fixtures, COPYTRADING_FIXTURE_SCENE: scene, COPYTRADING_CAPTURE_SIZE: size, COPYTRADING_CAPTURE_HASH: "#/accounts/zhap-account-2" },
  ]),
  // A stock's page (#/stock/SOXL) in a 1280×860 window, at the 980-wide minimum, and as one tall page ("full").
  ...["1280x860", "980x860", ""].map((size) => [`stock-${size || "full"}`, { ...fixtures, COPYTRADING_CAPTURE_SIZE: size, COPYTRADING_CAPTURE_HASH: "#/stock/SOXL?account=zhap-account-2" }]),
  // Copying paused: the primary action is Start Copying.
  ["account-paused", { ...fixtures, COPYTRADING_FIXTURE_TRADING: "paused", COPYTRADING_CAPTURE_SIZE: "1280x860", COPYTRADING_CAPTURE_HASH: "#/accounts/zhap-account-2" }],
  // Pressing Copy on the open waiting call opens the review.
  ["account-row-review", { ...fixtures, COPYTRADING_CAPTURE_HASH: "#/accounts/zhap-account-2", COPYTRADING_CAPTURE_CLICK: '[id$="-detail"] button' }],
  // The queue of waiting calls on the account page, in the "reasons" scene (a suggestion, an unclear post, a named buy that never filled,
  // one that never reached the account, a condition, an approval): the queue, a reason opened, J/K moving, S skipping one, Skip all, and nothing waiting.
  ...["1280x860", "980x860"].flatMap((size) => {
    const win = { ...fixtures, COPYTRADING_FIXTURE_SCENE: "reasons", COPYTRADING_CAPTURE_SIZE: size, COPYTRADING_CAPTURE_HASH: "#/accounts/zhap-account-2" }
    const pause = (ms) => `await new Promise((r) => setTimeout(r, ${ms}))`
    const keydown = (key, target = "document.activeElement") => `${target}.dispatchEvent(new KeyboardEvent("keydown", { key: ${JSON.stringify(key)}, bubbles: true }))`
    const first = `document.querySelector("[data-trigger]")`
    // The card sits below the first screen: bring it to the top of the window before anything else.
    const card = `document.querySelector('[aria-labelledby="posts-title"]').scrollIntoView({ block: "start" }); ${pause(300)}`
    const script = (steps) => ({ ...win, COPYTRADING_CAPTURE_SCRIPT: `(async () => { ${card}; ${steps} })()` })
    return [
      [`triage-queue-${size}`, script(pause(300))],
      [
        `triage-reason-${size}`,
        script(`[...document.querySelectorAll("[data-trigger]")].find((e) => e.textContent.includes("AEHR")).click(); ${pause(700)}; document.querySelector('[id$="-detail"] button[aria-expanded]').click(); ${pause(700)}`),
      ],
      [`triage-keys-${size}`, script(`${first}.focus(); ${keydown("j")}; ${pause(500)}; ${keydown("j")}; ${pause(700)}`)],
      [`triage-skip-${size}`, script(`${first}.focus(); ${keydown("s")}; ${pause(900)}`)],
      [`triage-undo-${size}`, script(`${first}.focus(); ${keydown("s")}; ${pause(600)}; ${keydown("s", "document.querySelector('[data-trigger]')")}; ${pause(600)}; [...document.querySelectorAll("button")].find((e) => e.textContent.startsWith("Undo")).click(); ${pause(900)}`)],
      [`triage-skipall-${size}`, script(`[...document.querySelectorAll("button")].find((e) => e.textContent.trim() === "Skip all").click(); ${pause(900)}`)],
      [`triage-none-${size}`, { ...win, COPYTRADING_FIXTURE_SCENE: "quiet", COPYTRADING_CAPTURE_SCRIPT: `(async () => { ${card} })()` }],
    ]
  }),
  ["account-attention", { ...fixtures, COPYTRADING_FIXTURE_SCENE: "attention", COPYTRADING_CAPTURE_HASH: "#/accounts/zhap-account-2" }],
  ["activity-timed-out", { ...fixtures, COPYTRADING_CAPTURE_HASH: "#/activity/5" }],
  ["activity-picture", { ...fixtures, COPYTRADING_CAPTURE_HASH: "#/activity/6" }],
  ["activity-filled", { ...fixtures, COPYTRADING_CAPTURE_HASH: "#/activity/8" }],
  ["activity-waiting", { ...fixtures, COPYTRADING_CAPTURE_HASH: "#/activity/9" }],
  ["activity-skipped", { ...fixtures, COPYTRADING_CAPTURE_HASH: "#/activity/3" }],
  ["activity-needs-you", { ...fixtures, COPYTRADING_CAPTURE_HASH: "#/activity", COPYTRADING_CAPTURE_CLICK: '[aria-label="Filter posts"] button:nth-child(3)' }],
  // Activity and a guru's page in a 1280×860 window and at the 980-wide minimum, on a day of the captured posts,
  // a busy day (a dozen more) and an empty one. "post" opens a post, in the pane beside the list or the sheet.
  ...["", "busy", "empty"].flatMap((scene) => ["1280x860", "1440x900", "980x860"].map((size) => [scene, size])).flatMap(([scene, size]) => {
    const env = { ...fixtures, COPYTRADING_FIXTURE_SCENE: scene, COPYTRADING_CAPTURE_SIZE: size }
    const name = `${scene || "day"}-${size}`
    return [
      [`activity-${name}`, { ...env, COPYTRADING_CAPTURE_HASH: "#/activity" }],
      ...(size === "1440x900" ? [] : [[`guru-${name}`, { ...env, COPYTRADING_CAPTURE_HASH: `#/gurus/${zhao}` }]]),
    ]
  }),
  // A guru's page with figures: the empty performance is the default (guru-day-*); this scene serves synthetic figures with a line, a best and a worst call.
  ...["1280x860", "1440x900", "980x860", ""].map((size) => [`guru-performance-${size || "full"}`, { ...fixtures, COPYTRADING_FIXTURE_SCENE: "performance", COPYTRADING_CAPTURE_SIZE: size, COPYTRADING_CAPTURE_HASH: `#/gurus/${zhao}` }]),
  // A guru's performance card: the empty state is the default (guru-day-*); this scene serves synthetic figures with a line, a best and a worst call.
  ...["1280x860", "980x860"].map((size) => [`guru-performance-${size}`, { ...fixtures, COPYTRADING_FIXTURE_SCENE: "performance", COPYTRADING_CAPTURE_SIZE: size, COPYTRADING_CAPTURE_HASH: `#/gurus/${zhao}` }]),
  // The whole page, down to the table.
  ...["", "busy"].map((scene) => [`activity-full-${scene || "day"}`, { ...fixtures, COPYTRADING_FIXTURE_SCENE: scene, COPYTRADING_CAPTURE_SIZE: "1280x1500", COPYTRADING_CAPTURE_HASH: "#/activity" }]),
  ["activity-full-980", { ...fixtures, COPYTRADING_CAPTURE_SIZE: "980x1500", COPYTRADING_CAPTURE_HASH: "#/activity" }],
  // The outcome flow card, scrolled into view (it sits below the first screen at the 980-wide minimum).
  ...["", "busy"].flatMap((scene) =>
    ["1280x860", "980x860"].map((size) => [
      `outcome-flow-${scene || "day"}-${size}`,
      {
        ...fixtures,
        COPYTRADING_FIXTURE_SCENE: scene,
        COPYTRADING_CAPTURE_SIZE: size,
        COPYTRADING_CAPTURE_HASH: "#/activity",
        COPYTRADING_CAPTURE_SCRIPT: `(async () => { document.getElementById("outcome-flow").scrollIntoView({ block: "center" }); await new Promise((r) => setTimeout(r, 1500)) })()`,
      },
    ]),
  ),
  // A post's steps in order: 8 a fill, 5 a buy cancelled at the timeout, 3 a skipped sell with its reason, 2 a coin buy held until Start Copying that filled in two parts;
  // the stops scene adds a stop resting at Alpaca (12) and one that filled hours later (9). "card" opens the card of a step: the pointer on the third step of an account.
  ...["1280x860", "980x860"].flatMap((size) => {
    const win = { ...fixtures, COPYTRADING_CAPTURE_SIZE: size }
    const step = (name, post, extra = {}) => [`post-steps-${name}-${size}`, { ...win, COPYTRADING_CAPTURE_HASH: `#/activity/${post}`, ...extra }]
    const hover = `(async () => { const bar = document.querySelectorAll("button[data-span-id]")[4]; bar.scrollIntoView({ block: "center" }); await new Promise((r) => setTimeout(r, 300)); bar.dispatchEvent(new PointerEvent("pointerover", { bubbles: true, pointerType: "mouse" })); bar.dispatchEvent(new PointerEvent("pointerenter", { pointerType: "mouse" })); await new Promise((r) => setTimeout(r, 700)) })()`
    const scroll = `(async () => { document.querySelector("[aria-labelledby]")?.scrollIntoView(); const t = [...document.querySelectorAll("h3")].find((h) => h.textContent === "Step by step"); t.scrollIntoView({ block: "center" }); await new Promise((r) => setTimeout(r, 600)) })()`
    return [
      step("filled", 8, { COPYTRADING_CAPTURE_SCRIPT: scroll }),
      step("timeout", 5, { COPYTRADING_CAPTURE_SCRIPT: scroll }),
      step("skipped", 3, { COPYTRADING_CAPTURE_SCRIPT: scroll }),
      step("held", 2, { COPYTRADING_CAPTURE_SCRIPT: scroll }),
      step("stop-placed", 12, { COPYTRADING_FIXTURE_SCENE: "stops", COPYTRADING_CAPTURE_SCRIPT: scroll }),
      step("stop-filled", 9, { COPYTRADING_FIXTURE_SCENE: "stops", COPYTRADING_CAPTURE_SCRIPT: scroll }),
      step("card", 2, { COPYTRADING_CAPTURE_SCRIPT: hover }),
    ]
  }),
  // The card of what came in since the owner last looked: they last looked at 2:00 PM on Nov 3 (the fixtures' clock is 9:00 PM), on Activity and, shorter, on the account page.
  // "dismissed" presses Dismiss; "calls" has six calls waiting; "busy" a dozen fills; nothing new (no card) is every other Activity and account capture.
  ...["1280x860", "980x860"].flatMap((size) => {
    const since = { ...fixtures, COPYTRADING_FIXTURE_LAST_LOOKED: "2026-11-03T14:00:00Z", COPYTRADING_CAPTURE_SIZE: size }
    const dismiss = `(async () => { await new Promise((r) => setTimeout(r, 600)); [...document.querySelectorAll("button")].find((b) => b.textContent.trim() === "Dismiss").click(); await new Promise((r) => setTimeout(r, 900)) })()`
    return [
      [`catch-up-activity-${size}`, { ...since, COPYTRADING_CAPTURE_HASH: "#/activity" }],
      [`catch-up-activity-calls-${size}`, { ...since, COPYTRADING_FIXTURE_SCENE: "calls", COPYTRADING_CAPTURE_HASH: "#/activity" }],
      [`catch-up-activity-busy-${size}`, { ...since, COPYTRADING_FIXTURE_SCENE: "busy", COPYTRADING_CAPTURE_HASH: "#/activity" }],
      [`catch-up-activity-dismissed-${size}`, { ...since, COPYTRADING_CAPTURE_HASH: "#/activity", COPYTRADING_CAPTURE_SCRIPT: dismiss }],
      // Each line's arrow opens its post in the drawer; the short card's "See all activity" goes to Activity.
      [`catch-up-open-post-${size}`, { ...since, COPYTRADING_CAPTURE_HASH: "#/activity", COPYTRADING_CAPTURE_SCRIPT: `(async () => { await new Promise((r) => setTimeout(r, 600)); document.querySelector('button[aria-label^="Open the post"]').click(); await new Promise((r) => setTimeout(r, 1500)) })()` }],
      [`catch-up-see-all-${size}`, { ...since, COPYTRADING_CAPTURE_HASH: "#/accounts/zhap-account-2", COPYTRADING_CAPTURE_SCRIPT: `(async () => { await new Promise((r) => setTimeout(r, 600)); [...document.querySelectorAll("button")].find((b) => b.textContent.trim() === "See all activity").click(); await new Promise((r) => setTimeout(r, 1500)) })()` }],
      [`catch-up-account-${size}`, { ...since, COPYTRADING_CAPTURE_HASH: "#/accounts/zhap-account-2" }],
      [`catch-up-account-dismissed-${size}`, { ...since, COPYTRADING_CAPTURE_HASH: "#/accounts/zhap-account-2", COPYTRADING_CAPTURE_SCRIPT: dismiss }],
    ]
  }),
  ["activity-post-1280x860", { ...fixtures, COPYTRADING_CAPTURE_SIZE: "1280x860", COPYTRADING_CAPTURE_HASH: "#/activity/5" }],
  ["activity-post-980x860", { ...fixtures, COPYTRADING_CAPTURE_SIZE: "980x860", COPYTRADING_CAPTURE_HASH: "#/activity/5" }],
  ["guru-sheet-1280x860", { ...fixtures, COPYTRADING_CAPTURE_SIZE: "1280x860", COPYTRADING_CAPTURE_HASH: `#/gurus/${zhao}`, COPYTRADING_CAPTURE_CLICK: 'button[data-sequence="5"]' }],
  ["guru-sheet-980x860", { ...fixtures, COPYTRADING_CAPTURE_SIZE: "980x860", COPYTRADING_CAPTURE_HASH: `#/gurus/${zhao}`, COPYTRADING_CAPTURE_CLICK: 'button[data-sequence="5"]' }],
  // The Gurus list for two or more gurus (the fixtures have two), in each size and state it has. "performance" serves distinct figures per guru.
  ...["1280x860", "980x860"].flatMap((size) => [
    [`gurus-${size}`, { ...fixtures, COPYTRADING_FIXTURE_SCENE: "performance", COPYTRADING_CAPTURE_SIZE: size, COPYTRADING_CAPTURE_HASH: "#/gurus" }],
    [`gurus-error-${size}`, { ...fixtures, COPYTRADING_FIXTURE_SCENE: "performance", COPYTRADING_FIXTURE_STATE: "figures-error", COPYTRADING_CAPTURE_SIZE: size, COPYTRADING_CAPTURE_HASH: "#/gurus" }],
    [`gurus-loading-${size}`, { ...fixtures, COPYTRADING_FIXTURE_SCENE: "performance", COPYTRADING_FIXTURE_STATE: "figures-loading", COPYTRADING_CAPTURE_SIZE: size, COPYTRADING_CAPTURE_HASH: "#/gurus" }],
  ]),
  // Every empty list: no holdings, nothing waiting, no posts (the account page and Activity), and a setup with no gurus.
  ...["1280x860", "980x860", "1280x1500"].flatMap((size) => [
    [`empty-account-${size}`, { ...fixtures, COPYTRADING_FIXTURE_SCENE: "empty", COPYTRADING_CAPTURE_SIZE: size, COPYTRADING_CAPTURE_HASH: "#/accounts/zhap-account-2" }],
    [`empty-activity-${size}`, { ...fixtures, COPYTRADING_FIXTURE_SCENE: "empty", COPYTRADING_CAPTURE_SIZE: size, COPYTRADING_CAPTURE_HASH: "#/activity" }],
    [`empty-gurus-${size}`, { ...fixtures, COPYTRADING_FIXTURE_SETUP: "none", COPYTRADING_CAPTURE_SIZE: size, COPYTRADING_CAPTURE_HASH: "#/gurus" }],
  ]),
  ["guru-page", { ...fixtures, COPYTRADING_CAPTURE_HASH: `#/gurus/${zhao}` }],
  ["guru-post-sheet-filled", { ...fixtures, COPYTRADING_CAPTURE_HASH: `#/gurus/${zhao}`, COPYTRADING_CAPTURE_CLICK: 'button[data-sequence="8"]' }],
  ["guru-post-sheet-waiting", { ...fixtures, COPYTRADING_CAPTURE_HASH: `#/gurus/${zhao}`, COPYTRADING_CAPTURE_CLICK: 'button[data-sequence="9"]' }],
  // Settings and tools
  ["settings-general", settings("general")],
  ["settings-general-timezone-open", settings("general", { COPYTRADING_CAPTURE_SCRIPT: openTimeZones })],
  ["settings-general-fills-off", settings("general", { COPYTRADING_CAPTURE_SCRIPT: `(async () => { document.querySelector('[role="switch"]').click(); await new Promise((r) => setTimeout(r, 600)) })()` })],
  ["settings-agents", settings("agents")],
  ["settings-agents-off", settings("agents", { COPYTRADING_CAPTURE_SCRIPT: click("button", "Nothing") })],
  ["settings-agents-problem", settings("agents", { COPYTRADING_FIXTURE_STATE: "agents-problem" })],
  ["settings-backups", settings("backups")],
  ["settings-backups-preview", settings("backups", { COPYTRADING_CAPTURE_SCRIPT: click("button", "Choose") })],
  ["settings-backups-pending-restore", settings("backups", { COPYTRADING_FIXTURE_STATE: "pending-restore" })],
  ["settings-logs", settings("logs")],
  // The records the setup no longer has (the "records" scene adds them), each with Open and Delete.
  ["settings-old-records", settings("old-records", { COPYTRADING_FIXTURE_SCENE: "records" })],
  // The old Connections route lands on its new path with the sheet open.
  ["settings-connections-old-route", settings("", { COPYTRADING_CAPTURE_HASH: "#/connections/discord" })],
  // Every Settings page at 1280×860 and at the 980-wide minimum, then with every read failing and every read waiting.
  ...["connections", "general", "agents", "backups", "logs", "old-records"].flatMap((page) =>
    ["", "reads-error", "reads-loading"].flatMap((state) =>
      ["1280x860", "980x860"].map((size) => [`settings-${page}-${state || "ready"}-${size}`, settings(page, { COPYTRADING_CAPTURE_SIZE: size, ...(state && { COPYTRADING_FIXTURE_STATE: state }) })]),
    ),
  ),
  // The app frame and the Assistant at 1280×860 and the 980-wide minimum. "records" adds the leftover account records.
  ...["1280x860", "980x860"].flatMap((size) => {
    const win = { ...fixtures, COPYTRADING_CAPTURE_SIZE: size }
    const account = { ...win, COPYTRADING_FIXTURE_SCENE: "records", COPYTRADING_CAPTURE_HASH: "#/accounts/zhap-account-2" }
    const open = { COPYTRADING_CAPTURE_SCRIPT: click("button", "Assistant") }
    return [
      [`frame-${size}`, account],
      [`frame-paused-${size}`, { ...account, COPYTRADING_FIXTURE_TRADING: "paused" }],
      [`frame-accounts-error-${size}`, { ...account, COPYTRADING_FIXTURE_STATE: "accounts-error" }],
      [`frame-accounts-loading-${size}`, { ...account, COPYTRADING_FIXTURE_STATE: "accounts-loading" }],
      [`assistant-empty-${size}`, { ...account, ...open }],
      [`assistant-answer-${size}`, { ...account, COPYTRADING_CAPTURE_SCRIPT: askAssistant }],
      [`assistant-error-${size}`, { ...account, COPYTRADING_FIXTURE_STATE: "assistant-error", COPYTRADING_CAPTURE_SCRIPT: askAssistant }],
      [`assistant-nomodel-${size}`, { ...account, COPYTRADING_FIXTURE_SETUP: "none", ...open }],
      // The rail of a first run (Getting Started listed above Settings), folded to icons, and ⌘K (empty, then with a query).
      [`frame-first-run-${size}`, { ...account, COPYTRADING_FIXTURE_SETUP: "none" }],
      [`frame-collapsed-${size}`, { ...account, COPYTRADING_CAPTURE_SCRIPT: `(async () => { document.querySelector('button[aria-label="Collapse sidebar"]').click(); await new Promise((r) => setTimeout(r, 600)) })()` }],
      // Three fills arriving together stack as notices; the pointer is not over them, so they rest tucked.
      [`fills-${size}`, { ...account, COPYTRADING_CAPTURE_FILLS: "3", COPYTRADING_CAPTURE_SCRIPT: "new Promise((r) => setTimeout(r, 300))" }],
      [`search-${size}`, { ...account, COPYTRADING_CAPTURE_SCRIPT: `(async () => { ${pressSearch} })()` }],
      [`search-query-${size}`, { ...account, COPYTRADING_CAPTURE_SCRIPT: `(async () => { ${pressSearch}; const input = document.querySelector('input[role="combobox"]'); Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value").set.call(input, "cifr"); input.dispatchEvent(new Event("input", { bubbles: true })); await new Promise((r) => setTimeout(r, 600)) })()` }],
    ]
  }),
  ["assistant-empty", { ...fixtures, COPYTRADING_CAPTURE_SCRIPT: click("button", "Assistant") }],
  ["assistant-answer", { ...fixtures, COPYTRADING_CAPTURE_SCRIPT: askAssistant }],
  // Agent access: requests waiting (one the app can approve, one it can only show), the recent log open, nothing waiting, and an
  // approval the app could not finish (the fixtures do not carry approvals, so Approve ends in its error).
  ...["1280x860", "980x860"].flatMap((size) => {
    const win = { COPYTRADING_CAPTURE_SIZE: size }
    return [
      [`agents-requests-${size}`, settings("agents", win)],
      [`agents-log-${size}`, settings("agents", { ...win, COPYTRADING_CAPTURE_SCRIPT: click("button", "Recent requests") })],
      [`agents-empty-${size}`, settings("agents", { ...win, COPYTRADING_FIXTURE_STATE: "agents-empty" })],
      [`agents-approve-error-${size}`, settings("agents", { ...win, COPYTRADING_CAPTURE_SCRIPT: click("button", "Approve", 1200) })],
    ]
  }),
  // Connect in each editor sheet: the check running, failed with the service's reason, and answered. Then the same from a row on the page.
  ...["1280x860", "980x860"].flatMap((size) => {
    const sheet = (kind, state, press = "Connect") => ({
      ...fixtures,
      COPYTRADING_CAPTURE_HASH: `#/settings/connections/${kind}`,
      COPYTRADING_FIXTURE_SETUP: "saved",
      COPYTRADING_FIXTURE_TRADING: "paused",
      COPYTRADING_FIXTURE_STATE: state,
      COPYTRADING_CAPTURE_SIZE: size,
      COPYTRADING_CAPTURE_SCRIPT: click('[role="dialog"] button', press, 1200),
    })
    return [
      [`connect-discord-running-${size}`, sheet("discord", "check-running")],
      [`connect-discord-failed-${size}`, sheet("discord", "check-failed")],
      [`connect-discord-connected-${size}`, sheet("discord", "check-ready")],
      [`connect-interpreter-failed-${size}`, sheet("interpreter", "check-failed")],
      [`connect-account-connected-${size}`, sheet("account:0", "check-ready")],
      [`connect-row-failed-${size}`, { ...fixtures, COPYTRADING_FIXTURE_SETUP: "saved", COPYTRADING_FIXTURE_TRADING: "paused", COPYTRADING_FIXTURE_STATE: "check-failed", COPYTRADING_CAPTURE_SIZE: size, COPYTRADING_CAPTURE_HASH: "#/settings/connections", COPYTRADING_CAPTURE_SCRIPT: `(async () => { document.querySelector('button[aria-label="Connect Discord"]').click(); await new Promise((r) => setTimeout(r, 1200)) })()` }],
    ]
  }),
  // The rail's highlight and labels: the highlight gliding from Accounts to Settings (frames while it moves), the folded rail with the
  // pointer over its Settings icon (its tip), and the rail while it folds.
  ...["1280x860", "980x860"].flatMap((size) => {
    const win = { ...fixtures, COPYTRADING_CAPTURE_SIZE: size, COPYTRADING_CAPTURE_HASH: "#/accounts/zhap-account-2" }
    const collapse = `document.querySelector('button[aria-label="Collapse sidebar"]').click()`
    return [
      [`rail-glide-${size}`, { ...win, COPYTRADING_CAPTURE_FRAMES: "4", COPYTRADING_CAPTURE_GAP: "70", COPYTRADING_CAPTURE_SCRIPT: `(async () => { await ${click("a", "Settings", 0)} })()` }],
      [`rail-collapsed-tip-${size}`, { ...win, COPYTRADING_CAPTURE_HOVER: "32,783@2", COPYTRADING_CAPTURE_FRAMES: "4", COPYTRADING_CAPTURE_GAP: "300", COPYTRADING_CAPTURE_SCRIPT: `(async () => { ${collapse}; await new Promise((r) => setTimeout(r, 600)) })()` }],
      [`rail-folding-${size}`, { ...win, COPYTRADING_CAPTURE_FRAMES: "4", COPYTRADING_CAPTURE_GAP: "60", COPYTRADING_CAPTURE_SCRIPT: `(async () => { ${collapse} })()` }],
    ]
  }),
  // Getting Started and Connections
  ...setupCaptures(),
  ["live", {}],
  ["live-activity", { COPYTRADING_CAPTURE_HASH: "#/activity" }],
  ["live-gurus", { COPYTRADING_CAPTURE_HASH: "#/gurus" }],
  ["live-settings-logs", { COPYTRADING_CAPTURE_HASH: "#/settings/logs" }],
  // The real engine on a throwaway installation folder: access starts off, with no socket.
  ["live-settings-agents", { COPYTRADING_CAPTURE_HASH: "#/settings/agents" }],
]) {
  const only = process.argv.slice(2)
  if (only.length && !only.some((word) => name.includes(word))) continue
  // Each run gets its own storage: a call skipped in one capture must not stay skipped in the next.
  const userData = mkdtempSync(join(tmpdir(), "copytrading-capture-"))
  const run = spawnSync(electron, [".", `--user-data-dir=${userData}`], {
    stdio: "inherit",
    env: { ...process.env, ...env, COPYTRADING_CAPTURE_DIR: out, COPYTRADING_CAPTURE_NAME: name },
  })
  rmSync(userData, { recursive: true, force: true })
  if (run.status !== 0) process.exit(run.status ?? 1)
}
console.log(`Saved PNGs to ${out}`)
