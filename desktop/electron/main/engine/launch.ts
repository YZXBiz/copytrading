import { type ChildProcess, spawn } from "node:child_process"
import { randomUUID } from "node:crypto"
import { existsSync, rmSync } from "node:fs"
import { join, resolve } from "node:path"
import type { EngineState } from "../../../shared/contract"
import { EngineBridge, EngineError } from "./bridge"
import { makeThrowawayRoot } from "./safety"

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
}

/** The engine process for the life of the app: starting, running, or stopped with the reason. */
export class EngineProcess {
  private current: EngineState = { state: "starting" }
  private readonly listeners = new Set<(state: EngineState) => void>()
  private child: ChildProcess | null = null
  private bridge: EngineBridge | null = null
  private cleanup: () => void = () => {}
  private stopping = false
  private exited: Promise<void> = Promise.resolve()

  constructor(private readonly timing = { stopAskMs: STOP_ASK_MS, terminateGraceMs: TERMINATE_GRACE_MS }) {}

  get state(): EngineState {
    return this.current
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

  /** Spawns the engine on a throwaway data folder and resolves once it answers, or fails with the reason. */
  async start(target: SpawnTarget & { cleanup?: () => void }): Promise<void> {
    this.cleanup = target.cleanup ?? (() => {})
    const child = spawn(target.command, target.args, { cwd: target.cwd, env: target.env, stdio: ["pipe", "pipe", "pipe"] })
    const bridge = new EngineBridge(child.stdin!, child.stdout!)
    this.child = child
    this.bridge = bridge
    let stderr = ""
    child.stderr!.on("data", (chunk: Buffer) => (stderr = (stderr + chunk).slice(-2000)))
    this.exited = new Promise((done) => {
      child.on("close", (code) => {
        const reason = stderr.trim() || `The engine exited (code ${code}).`
        bridge.failAll(new EngineError("disconnected", reason))
        this.bridge = null
        if (this.current.state !== "stopped") this.set({ state: "stopped", reason: this.stopping ? "Stopped." : reason })
        done()
      })
      child.on("error", (error) => {
        bridge.failAll(new EngineError("disconnected", error.message))
        this.bridge = null
        this.set({ state: "stopped", reason: error.message })
        done()
      })
    })
    const deadline = Date.now() + STARTUP_TIMEOUT_MS
    while (this.current.state === "starting") {
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
  async stop(): Promise<void> {
    const child = this.child
    if (!child || this.stopping) return this.exited
    this.stopping = true
    const gone = (ms: number) => Promise.race([this.exited.then(() => true), new Promise<boolean>((done) => setTimeout(() => done(false), ms))])
    await this.bridge?.request("stop").catch(() => {})
    if (!(await gone(this.timing.stopAskMs))) {
      child.kill("SIGTERM")
      if (!(await gone(this.timing.terminateGraceMs))) child.kill("SIGKILL")
    }
    await this.exited
    this.cleanup()
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

/** The command that runs the engine as AppModel.swift does: -u -m copytrading_engine, JSON lines on stdio. */
export function engineTarget(): SpawnTarget & { cleanup: () => void; dataDir: string; logsDir: string } {
  const runtime = findPython()
  const python = process.env.COPYTRADING_PYTHON ?? (runtime && join(runtime, PYTHON))
  if (!python) throw new Error("No Python runtime with the engine's dependencies found.")
  const dirs = makeThrowawayRoot()
  return {
    command: python,
    args: ["-u", "-m", "copytrading_engine", "--data-dir", dirs.data, "--instance-id", randomUUID()],
    cwd: dirs.data,
    env: {
      PATH: "/usr/bin:/bin",
      PYTHONPATH: join(REPO, "engine/src"),
      PYTHONUNBUFFERED: "1",
      PYTHONDONTWRITEBYTECODE: "1",
      COPYTRADING_DESKTOP_DIAGNOSTICS_STATE_DIR: dirs.logs,
      COPYTRADING_DESKTOP_OWNER_SUPPORT_DIR: dirs.owner,
    },
    cleanup: () => rmSync(dirs.root, { recursive: true, force: true }),
    dataDir: dirs.data,
    logsDir: dirs.logs,
  }
}
