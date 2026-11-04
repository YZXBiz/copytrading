import { join } from "node:path"
import { afterEach, describe, expect, it } from "vitest"
import type { EngineState } from "../shared/contract"
import { EngineProcess } from "../electron/main/engine/launch"

const FAKE = join(__dirname, "fake-engine.cjs")
const engines: EngineProcess[] = []
const target = (mode: string, cleanup?: () => void) => ({ command: process.execPath, args: [FAKE, mode], env: {}, cwd: __dirname, cleanup })

function engineFor(mode: string, cleanup?: () => void) {
  const engine = new EngineProcess({ stopAskMs: 400, terminateGraceMs: 300 })
  const states: EngineState[] = []
  engine.onState((s) => states.push(s))
  engines.push(engine)
  return { engine, states, started: engine.start(target(mode, cleanup)) }
}

afterEach(() => Promise.all(engines.splice(0).map((e) => e.stop())))

describe("EngineProcess", () => {
  it("is starting, then running once the engine answers", async () => {
    const { engine, states, started } = engineFor("serve")
    expect(engine.state).toEqual({ state: "starting" })
    await started
    expect(states).toEqual([{ state: "running" }])
    await expect(engine.request("get_status")).resolves.toMatchObject({ type: "status" })
  })

  it("stops by asking, waits for the exit, and cleans up", async () => {
    let cleaned = false
    const { engine, started } = engineFor("serve", () => (cleaned = true))
    await started
    await engine.stop()
    expect(engine.state).toEqual({ state: "stopped", reason: "Stopped." })
    expect(cleaned).toBe(true)
  })

  it("terminates an engine that ignores the request to stop", async () => {
    const { engine, started } = engineFor("ignore-stop")
    await started
    await engine.stop()
    expect(engine.state.state).toBe("stopped")
  })

  it("kills an engine that ignores terminate too", async () => {
    const { engine, started } = engineFor("stubborn")
    await started
    await engine.stop()
    expect(engine.state.state).toBe("stopped")
  })

  it("is stopped with what the engine printed when it dies on startup", async () => {
    const { engine, started } = engineFor("crash")
    await started
    expect(engine.state).toEqual({ state: "stopped", reason: "boom: the engine could not open its database" })
    await expect(engine.request("get_status")).rejects.toMatchObject({ code: "disconnected", message: expect.stringContaining("boom") })
  })

  it("says why when it could not be started at all", () => {
    const engine = new EngineProcess()
    engine.fail("No Python runtime with the engine's dependencies found.")
    expect(engine.state).toEqual({ state: "stopped", reason: "No Python runtime with the engine's dependencies found." })
  })
})
