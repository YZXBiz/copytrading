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

// Getting Started and Connections: a first run, a saved setup that is paused, one that is copying, and each editor sheet
// (#/connections/<discord|interpreter|account:N|guru:N> opens it).
function setupCaptures() {
  const fixture = (hash, setup, trading) => ({
    ...fixtures,
    COPYTRADING_CAPTURE_HASH: hash,
    COPYTRADING_FIXTURE_SETUP: setup,
    COPYTRADING_FIXTURE_TRADING: trading,
  })
  return [
    ["getting-started-first-run", fixture("#/getting-started", "none", "paused")],
    ["getting-started-saved", fixture("#/getting-started", "saved", "paused")],
    ["connections-first-run", fixture("#/connections", "none", "paused")],
    ["connections-saved", fixture("#/connections", "saved", "paused")],
    ["connections-copying", fixture("#/connections", "saved", "running")],
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
  ["account-review", { ...fixtures, COPYTRADING_CAPTURE_HASH: "#/accounts/zhap-account-2?open=review" }],
  ["account-sale", { ...fixtures, COPYTRADING_CAPTURE_HASH: "#/accounts/zhap-account-2?open=sale" }],
  ["account-limits", { ...fixtures, COPYTRADING_CAPTURE_HASH: "#/accounts/zhap-account-2?open=limits" }],
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
  ["settings-agents", settings("agents")],
  ["settings-backups", settings("backups")],
  ["settings-backups-preview", settings("backups", { COPYTRADING_CAPTURE_SCRIPT: click("button", "Choose") })],
  ["settings-backups-pending-restore", settings("backups", { COPYTRADING_FIXTURE_STATE: "pending-restore" })],
  ["settings-logs", settings("logs")],
  ["assistant-empty", { ...fixtures, COPYTRADING_CAPTURE_SCRIPT: click("button", "Assistant") }],
  ["assistant-answer", { ...fixtures, COPYTRADING_CAPTURE_SCRIPT: askAssistant }],
  // Getting Started and Connections
  ...setupCaptures(),
  ["live", {}],
  ["live-activity", { COPYTRADING_CAPTURE_HASH: "#/activity" }],
  ["live-gurus", { COPYTRADING_CAPTURE_HASH: "#/gurus" }],
  ["live-settings-logs", { COPYTRADING_CAPTURE_HASH: "#/settings/logs" }],
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
