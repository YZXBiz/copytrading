// Opens the built app offscreen once per screen and saves light and dark PNGs of each to dist/capture:
// the account page, its sheets and the screens on fixtures, then live runs on a throwaway data dir (empty states).
// Add a screen: add a [name, env] pair with COPYTRADING_CAPTURE_HASH set to its route, and
// COPYTRADING_CAPTURE_CLICK to a selector to press first (a sheet), or COPYTRADING_CAPTURE_SCRIPT to a page script
// for a panel that needs more than one press. Never shows a window or takes focus.
// `node scripts/capture.mjs settings logs` captures only the entries whose name contains one of the words.
import { spawnSync } from "node:child_process"
import { createRequire } from "node:module"
import { resolve } from "node:path"

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

// ⌘K opens the search dialog; its posts need a moment to load.
const pressSearch = `window.dispatchEvent(new KeyboardEvent("keydown", { key: "k", metaKey: true, bubbles: true })); await new Promise((r) => setTimeout(r, 1500))`

// Getting Started and Connections: a first run, a saved setup that is paused, one that is copying, and each editor sheet
// (#/connections/<discord|interpreter|account:N|guru:N> opens it).
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
    ["connections", "#/connections", ["first-run:none:paused", "saved:saved:paused", "copying:saved:running"]],
  ]
  const sized = screens.flatMap(([screen, hash, states]) =>
    states.flatMap((state) => {
      const [label, setup, trading] = state.split(":")
      return ["1280x860", "980x860"].map((size) => [`${screen}-${label}-${size}`, { ...fixture(hash, setup, trading), COPYTRADING_CAPTURE_SIZE: size }])
    }),
  )
  const broken = ["getting-started", "connections"].flatMap((screen) =>
    ["error", "loading"].flatMap((state) =>
      ["1280x860", "980x860"].map((size) => [`${screen}-${state}-${size}`, { ...fixture(`#/${screen}`, "saved", "paused"), COPYTRADING_FIXTURE_STATE: `reads-${state}`, COPYTRADING_CAPTURE_SIZE: size }]),
    ),
  )
  return [
    ...sized,
    ...broken,
    ["sheet-discord", fixture("#/connections/discord", "saved", "paused")],
    ["sheet-interpreter", fixture("#/connections/interpreter", "saved", "paused")],
    ["sheet-account", fixture("#/connections/account:0", "saved", "paused")],
    ["sheet-account-copying", fixture("#/connections/account:0", "saved", "running")],
    ["sheet-guru", fixture("#/connections/guru:0", "saved", "paused")],
    // The real engine on a throwaway data folder: a first run reads its status and the (absent) setup.
    ["live-connections", { COPYTRADING_CAPTURE_HASH: "#/connections" }],
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
      COPYTRADING_CAPTURE_SCRIPT: `(async () => { const read = () => document.querySelector("main number-flow-react").shadowRoot.textContent; const before = read(); for (let i = 0; i < 300 && read() === before; i++) await new Promise((r) => setTimeout(r, 40)) })()`,
    },
  ],
  ["account-review", { ...fixtures, COPYTRADING_CAPTURE_HASH: "#/accounts/zhap-account-2?open=review" }],
  ["account-sale", { ...fixtures, COPYTRADING_CAPTURE_HASH: "#/accounts/zhap-account-2?open=sale" }],
  ["account-limits", { ...fixtures, COPYTRADING_CAPTURE_HASH: "#/accounts/zhap-account-2?open=limits" }],
  // The account page in a 1280×860 window, at the SwiftUI app's 980-wide minimum, and as one tall page ("full"):
  // no waiting calls, the two the captured account has, and six.
  ...["quiet", "", "calls"].flatMap((scene) => ["1280x860", "980x860", ""].map((size) => [scene, size])).map(([scene, size]) => [
    `account-${scene || "default"}-${size || "full"}`,
    { ...fixtures, COPYTRADING_FIXTURE_SCENE: scene, COPYTRADING_CAPTURE_SIZE: size, COPYTRADING_CAPTURE_HASH: "#/accounts/zhap-account-2" },
  ]),
  // Copying paused: the primary action is Resume Copying.
  ["account-paused", { ...fixtures, COPYTRADING_FIXTURE_TRADING: "paused", COPYTRADING_CAPTURE_SIZE: "1280x860", COPYTRADING_CAPTURE_HASH: "#/accounts/zhap-account-2" }],
  // Pressing a waiting call's row (not its buttons) opens the same review as Copy.
  ["account-row-review", { ...fixtures, COPYTRADING_CAPTURE_HASH: "#/accounts/zhap-account-2", COPYTRADING_CAPTURE_CLICK: '[data-slot="item"]' }],
  ["account-attention", { ...fixtures, COPYTRADING_FIXTURE_SCENE: "attention", COPYTRADING_CAPTURE_HASH: "#/accounts/zhap-account-2" }],
  ["activity-timed-out", { ...fixtures, COPYTRADING_CAPTURE_HASH: "#/activity/5" }],
  ["activity-picture", { ...fixtures, COPYTRADING_CAPTURE_HASH: "#/activity/6" }],
  ["activity-filled", { ...fixtures, COPYTRADING_CAPTURE_HASH: "#/activity/8" }],
  ["activity-waiting", { ...fixtures, COPYTRADING_CAPTURE_HASH: "#/activity/9" }],
  ["activity-skipped", { ...fixtures, COPYTRADING_CAPTURE_HASH: "#/activity/3" }],
  ["activity-needs-you", { ...fixtures, COPYTRADING_CAPTURE_HASH: "#/activity", COPYTRADING_CAPTURE_CLICK: '[data-slot="toggle-group-item"]:nth-child(2)' }],
  ["gurus", { ...fixtures, COPYTRADING_CAPTURE_HASH: "#/gurus" }],
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
  // Every Settings page at 1280×860 and at the 980-wide minimum, then with every read failing and every read waiting.
  ...["general", "agents", "backups", "logs"].flatMap((page) =>
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
      // The rail folded to icons, the old records opened, and ⌘K (empty, then with a query).
      [`frame-collapsed-${size}`, { ...account, COPYTRADING_CAPTURE_SCRIPT: `(async () => { document.querySelector('[data-slot="sidebar-trigger"]').click(); await new Promise((r) => setTimeout(r, 600)) })()` }],
      [`frame-records-open-${size}`, { ...account, COPYTRADING_CAPTURE_SCRIPT: click("button", "Old records", 600) }],
      [`search-${size}`, { ...account, COPYTRADING_CAPTURE_SCRIPT: `(async () => { ${pressSearch} })()` }],
      [`search-query-${size}`, { ...account, COPYTRADING_CAPTURE_SCRIPT: `(async () => { ${pressSearch}; const input = document.querySelector('[data-slot="command-input"]'); Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value").set.call(input, "cifr"); input.dispatchEvent(new Event("input", { bubbles: true })); await new Promise((r) => setTimeout(r, 600)) })()` }],
    ]
  }),
  ["assistant-empty", { ...fixtures, COPYTRADING_CAPTURE_SCRIPT: click("button", "Assistant") }],
  ["assistant-answer", { ...fixtures, COPYTRADING_CAPTURE_SCRIPT: askAssistant }],
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
  const run = spawnSync(electron, ["."], {
    stdio: "inherit",
    env: { ...process.env, ...env, COPYTRADING_CAPTURE_DIR: out, COPYTRADING_CAPTURE_NAME: name },
  })
  if (run.status !== 0) process.exit(run.status ?? 1)
}
console.log(`Saved PNGs to ${out}`)
