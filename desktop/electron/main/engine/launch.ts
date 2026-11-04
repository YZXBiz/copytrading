import { type ChildProcess, spawn } from "node:child_process"
import { existsSync } from "node:fs"
import { join, resolve } from "node:path"
import type { EngineState } from "../../../shared/contract"
import { EngineBridge, EngineError } from "./bridge"
import { appendEngineLog } from "./engine-log"
import type { RuntimePaths } from "./paths"

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

// ProcessSupervisor.swift: ask the engine to stop, then terminate it, then kill it.
const STARTUP_TIMEOUT_MS = 40_000
const STOP_ASK_MS = 5_000
const TERMINATE_GRACE_MS = 3_000

export interface SpawnTarget {
  command: string
  args: string[]
  env: Record<string, string>
  cwd: string
  /** Where the engine's stderr is kept (rotating); none in tests that do not look at it. */
  logFile?: string
}

/** Whether the engine took the request to stop (it has finished its work), or never heard it (ProcessSupervisorStopReport). */
export type Drain = "acknowledged" | "unconfirmed" | "no_live_engine"

/** The engine process: starting, running, or stopped with the reason. It can be started again after a stop, as a restore does. */
export class EngineProcess {
  private current: EngineState = { state: "starting" }
  private readonly listeners = new Set<(state: EngineState) => void>()
  private readonly crashListeners = new Set<(reason: string) => void>()
  private child: ChildProcess | null = null
  private bridge: EngineBridge | null = null
  /** The stop under way or finished for the current process; a second `stop` shares it. */
  private stopped: Promise<Drain> | null = null
  private exited: Promise<void> = Promise.resolve()

  constructor(private readonly timing = { stopAskMs: STOP_ASK_MS, terminateGraceMs: TERMINATE_GRACE_MS }) {}

  get state(): EngineState {
    return this.current
  }

  /** Called with the engine's own words when it exits without having been asked to stop. */
  onCrash(listener: (reason: string) => void): () => void {
    this.crashListeners.add(listener)
    return () => this.crashListeners.delete(listener)
  }

  onState(listener: (state: EngineState) => void): () => void {
    this.listeners.add(listener)
    return () => this.listeners.delete(listener)
  }

  /** Sends one operation; while the engine is down it fails at once with the reason. */
  request(operation: string, params: Record<string, unknown> = {}): Promise<unknown> {
    if (!this.bridge) {
      const reason = this.current.state === "stopped" ? this.current.reason : "The engine is starting."
      return Promise.reject(new EngineError("disconnected", reason))
    }
    return this.bridge.request(operation, params)
  }

  /** Spawns the engine and resolves once it answers, or fails with the reason. */
  async start(target: SpawnTarget): Promise<void> {
    if (this.child) throw new Error("The engine is already running.")
    this.stopped = null
    if (this.current.state !== "starting") this.set({ state: "starting" })
    const child = spawn(target.command, target.args, { cwd: target.cwd, env: target.env, stdio: ["pipe", "pipe", "pipe"] })
    const bridge = new EngineBridge(child.stdin!, child.stdout!)
    this.child = child
    this.bridge = bridge
    let stderr = ""
    if (target.logFile) appendEngineLog(target.logFile, `--- engine started ${new Date().toISOString()} ---\n`)
    child.stderr!.on("data", (chunk: Buffer) => {
      stderr = (stderr + chunk).slice(-2000)
      if (target.logFile) appendEngineLog(target.logFile, chunk)
    })
    // Each handler acts only for the process that started it, so a late exit never touches a restarted engine.
    const ended = (reason: string) => {
      bridge.failAll(new EngineError("disconnected", reason))
      if (this.child !== child) return
      this.child = null
      this.bridge = null
      if (this.current.state !== "stopped") this.set({ state: "stopped", reason: this.stopped ? "Stopped." : reason })
      // Nobody asked it to stop: a crash.
      if (!this.stopped) this.crashListeners.forEach((listener) => listener(reason))
    }
    this.exited = new Promise((done) => {
      child.on("close", (code) => {
        ended(stderr.trim() || `The engine exited (code ${code}).`)
        done()
      })
      child.on("error", (error) => {
        ended(error.message)
        done()
      })
    })
    const deadline = Date.now() + STARTUP_TIMEOUT_MS
    while (this.current.state === "starting" && this.child === child) {
      try {
        await bridge.request("get_status")
        this.set({ state: "running" })
      } catch {
        if (Date.now() > deadline) {
          this.set({ state: "stopped", reason: "The engine did not answer in time." })
          void this.stop()
        } else await new Promise((done) => setTimeout(done, 250))
      }
    }
  }

  /** Asks the engine to stop, then terminates and kills it if it has not, and waits for it to be gone. */
  stop(): Promise<Drain> {
    const child = this.child
    if (!child) return Promise.resolve("no_live_engine")
    this.stopped ??= this.halt(child)
    return this.stopped
  }

  private async halt(child: ChildProcess): Promise<Drain> {
    const exited = this.exited
    const gone = (ms: number) => Promise.race([exited.then(() => true), new Promise<boolean>((done) => setTimeout(() => done(false), ms))])
    const drain: Drain = (await this.bridge?.request("stop").then(
      () => true,
      () => false,
    ))
      ? "acknowledged"
      : "unconfirmed"
    if (!(await gone(this.timing.stopAskMs))) {
      child.kill("SIGTERM")
      if (!(await gone(this.timing.terminateGraceMs))) child.kill("SIGKILL")
    }
    await exited
    return drain
  }

  /** The engine could not be started at all (no runtime, a refused folder): say why in the footer. */
  fail(reason: string): void {
    this.set({ state: "stopped", reason })
  }

  private set(next: EngineState): void {
    this.current = next
    for (const listener of this.listeners) listener(next)
  }
}

/**
 * The command that runs the engine as AppModel.swift does: -u -m copytrading_engine, JSON lines on stdio,
 * on whichever generation is active now, with the installation's own id. Call it again after a restore switches generations.
 * `resourcesPath` is the built app's Contents/Resources, which holds Runtime/ and Engine/src; without
 * it (dev, tests) the repo's engine runs on a runtime found on this Mac.
 */
export function engineTarget(paths: RuntimePaths, resourcesPath: string | null): SpawnTarget {
  const runtime = resourcesPath ? join(resourcesPath, "Runtime") : findPython()
  const python = resourcesPath ? join(runtime!, PYTHON) : (process.env.COPYTRADING_PYTHON ?? (runtime && join(runtime, PYTHON)))
  if (!python || !existsSync(python)) throw new Error("No Python runtime with the engine's dependencies found.")
  const { dir } = paths.activeGeneration()
  return {
    command: python,
    args: ["-u", "-m", "copytrading_engine", "--data-dir", dir, "--instance-id", paths.installationIdentity()],
    cwd: dir,
    logFile: join(paths.logs, "engine.log"),
    env: {
      PATH: "/usr/bin:/bin",
      PYTHONPATH: join(resourcesPath ? join(resourcesPath, "Engine") : join(REPO, "engine"), "src"),
      PYTHONUNBUFFERED: "1",
      PYTHONDONTWRITEBYTECODE: "1",
      COPYTRADING_DESKTOP_DIAGNOSTICS_STATE_DIR: paths.logs,
      COPYTRADING_DESKTOP_OWNER_SUPPORT_DIR: paths.owner,
    },
  }
}
