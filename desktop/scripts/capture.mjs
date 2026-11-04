// Opens the built app offscreen twice (fixtures, then a live engine on a throwaway data dir)
// and saves light and dark PNGs of each to dist/capture. Never shows a window or takes focus.
import { spawnSync } from "node:child_process"
import { createRequire } from "node:module"
import { resolve } from "node:path"

const electron = createRequire(import.meta.url)("electron")
const out = resolve("dist/capture")

for (const [name, env] of [
  ["fixture", { COPYTRADING_FIXTURES: "1" }],
  ["live", {}],
]) {
  const run = spawnSync(electron, ["."], {
    stdio: "inherit",
    env: { ...process.env, ...env, COPYTRADING_CAPTURE_DIR: out, COPYTRADING_CAPTURE_NAME: name },
  })
  if (run.status !== 0) process.exit(run.status ?? 1)
}
console.log(`Saved PNGs to ${out}`)
