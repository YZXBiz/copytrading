import { join } from "node:path"
import { afterEach, describe, expect, it } from "vitest"
import type { EngineState } from "../shared/contract"
import { EngineProcess } from "../electron/main/engine/launch"

const FAKE = join(__dirname, "fake-engine.cjs")
const engines: EngineProcess[] = []
const target = (mode: string) => ({ command: process.execPath, args: [FAKE, mode], env: {}, cwd: __dirname })

function engineFor(mode: string) {
  const engine = new EngineProcess({ stopAskMs: 400, terminateGraceMs: 300 })
  const states: EngineState[] = []
  engine.onState((s) => states.push(s))
  engines.push(engine)
  return { engine, states, started: engine.start(target(mode)) }
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

  it("stops by asking, and waits for the exit, saying the engine took the request", async () => {
    const { engine, started } = engineFor("serve")
    await started
    await expect(engine.stop()).resolves.toBe("acknowledged")
    expect(engine.state).toEqual({ state: "stopped", reason: "Stopped." })
  })

  it("says the drain is unconfirmed when the engine exits without answering the request to stop", async () => {
    const { engine, started } = engineFor("exit-on-stop")
    await started
    await expect(engine.stop()).resolves.toBe("unconfirmed")
  })

  it("has nothing to drain when there is no engine", async () => {
    await expect(new EngineProcess().stop()).resolves.toBe("no_live_engine")
  })

  it("starts again after a stop, as a restore does, with a state of its own", async () => {
    const { engine, started } = engineFor("serve")
    await started
    await engine.stop()
    const states: EngineState[] = []
    engine.onState((s) => states.push(s))
    await engine.start(target("serve"))
    expect(states).toEqual([{ state: "starting" }, { state: "running" }])
    await expect(engine.request("get_status")).resolves.toMatchObject({ type: "status" })
    await expect(engine.stop()).resolves.toBe("acknowledged")
    expect(engine.state).toEqual({ state: "stopped", reason: "Stopped." })
  })

  it("refuses to start a second engine on top of a running one", async () => {
    const { engine, started } = engineFor("serve")
    await started
    await expect(engine.start(target("serve"))).rejects.toThrow(/already running/)
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
