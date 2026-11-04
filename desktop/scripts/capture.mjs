// Opens the built app offscreen once per screen and saves light and dark PNGs of each to dist/capture:
// the account page and the screens on fixtures, then live runs on a throwaway data dir (empty states).
// Add a screen: add a [name, env] pair with COPYTRADING_CAPTURE_HASH set to its route, and
// COPYTRADING_CAPTURE_CLICK to a selector to press first (a sheet). Never shows a window or takes focus.
import { spawnSync } from "node:child_process"
import { createRequire } from "node:module"
import { resolve } from "node:path"

const electron = createRequire(import.meta.url)("electron")
const out = resolve("dist/capture")
const fixtures = { COPYTRADING_FIXTURES: "1" }
const zhao = encodeURIComponent("赵哥")

// Posts in the fixtures, oldest first: 3 a skipped sell, 5 a buy that timed out, 6 a picture, 8 a fill, 9 a post waiting for the owner.
for (const [name, env] of [
  ["fixture", fixtures],
  ["placeholder-settings", { ...fixtures, COPYTRADING_CAPTURE_HASH: "#/settings" }],
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
  ["live", {}],
  ["live-activity", { COPYTRADING_CAPTURE_HASH: "#/activity" }],
  ["live-gurus", { COPYTRADING_CAPTURE_HASH: "#/gurus" }],
]) {
  const run = spawnSync(electron, ["."], {
    stdio: "inherit",
    env: { ...process.env, ...env, COPYTRADING_CAPTURE_DIR: out, COPYTRADING_CAPTURE_NAME: name },
  })
  if (run.status !== 0) process.exit(run.status ?? 1)
}
console.log(`Saved PNGs to ${out}`)
