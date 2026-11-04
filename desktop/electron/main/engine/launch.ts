import { type ChildProcess, spawn } from "node:child_process"
import { randomUUID } from "node:crypto"
import { existsSync, rmSync } from "node:fs"
import { join, resolve } from "node:path"
import { EngineBridge } from "./bridge"
import { assertThrowaway, makeThrowawayRoot } from "./safety"

const REPO = resolve(__dirname, "../../..")
const PYTHON = "cpython/python/bin/python3.14"
const SITE_PACKAGES = "cpython/python/lib/python3.14/site-packages"
// A runtime counts only with the engine's dependencies installed. The prepared one is bare CPython;
// the installed app's runtime has them and is only ever read from here.
const RUNTIMES = [
  join(REPO, "dist/desktop-runtime/prepared"),
  "/Applications/CopyTrading.app/Contents/Resources/Runtime",
]
const findPython = () =>
  RUNTIMES.find((root) => existsSync(join(root, PYTHON)) && existsSync(join(root, SITE_PACKAGES, "pydantic")))

export interface RunningEngine {
  bridge: EngineBridge
  stop: () => void
}

/** Spawns the engine as AppModel.swift does: -u -m copytrading_engine, JSON lines on stdio. */
export function launchEngine(): RunningEngine {
  const runtime = findPython()
  const python = process.env.COPYTRADING_PYTHON ?? (runtime && join(runtime, PYTHON))
  if (!python) throw new Error("No Python runtime with the engine's dependencies found.")
  const dirs = makeThrowawayRoot()

  const child: ChildProcess = spawn(
    python,
    ["-u", "-m", "copytrading_engine", "--data-dir", dirs.data, "--instance-id", randomUUID()],
    {
      cwd: dirs.data,
      stdio: ["pipe", "pipe", "pipe"],
      env: {
        PATH: "/usr/bin:/bin",
        PYTHONPATH: join(REPO, "engine/src"),
        PYTHONUNBUFFERED: "1",
        PYTHONDONTWRITEBYTECODE: "1",
        COPYTRADING_DESKTOP_DIAGNOSTICS_STATE_DIR: dirs.logs,
        COPYTRADING_DESKTOP_OWNER_SUPPORT_DIR: dirs.owner,
      },
    },
  )
  const bridge = new EngineBridge(child.stdin!, child.stdout!)
  let stderr = ""
  child.stderr!.on("data", (chunk: Buffer) => (stderr = (stderr + chunk).slice(-2000)))
  child.on("close", (code) => bridge.failAll(new Error(stderr.trim() || `The engine exited (code ${code}).`)))
  return {
    bridge,
    stop: () => {
      child.kill()
      rmSync(dirs.root, { recursive: true, force: true })
    },
  }
}
