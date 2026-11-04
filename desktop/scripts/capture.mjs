// Opens the built app offscreen three times (the account page on fixtures, a placeholder screen on
// fixtures, then a live engine on a throwaway data dir) and saves light and dark PNGs of each to
// dist/capture. Add a screen: add a [name, env] pair with COPYTRADING_CAPTURE_HASH set to its route.
// Never shows a window or takes focus.
import { spawnSync } from "node:child_process"
import { createRequire } from "node:module"
import { resolve } from "node:path"

const electron = createRequire(import.meta.url)("electron")
const out = resolve("dist/capture")

for (const [name, env] of [
  ["fixture", { COPYTRADING_FIXTURES: "1" }],
  ["placeholder-gurus", { COPYTRADING_FIXTURES: "1", COPYTRADING_CAPTURE_HASH: "#/gurus" }],
  ["live", {}],
]) {
  const run = spawnSync(electron, ["."], {
    stdio: "inherit",
    env: { ...process.env, ...env, COPYTRADING_CAPTURE_DIR: out, COPYTRADING_CAPTURE_NAME: name },
  })
  if (run.status !== 0) process.exit(run.status ?? 1)
}
console.log(`Saved PNGs to ${out}`)
