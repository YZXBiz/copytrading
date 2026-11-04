import { join } from "node:path"
import { afterEach, describe, expect, it } from "vitest"
import { EngineProcess } from "../electron/main/engine/launch"
import { superviseEngine } from "../electron/main/engine/supervise"

const FAKE = join(__dirname, "fake-engine.cjs")
const target = (mode: string) => ({ command: process.execPath, args: [FAKE, mode], env: {}, cwd: __dirname })
const engines: EngineProcess[] = []
afterEach(() => Promise.all(engines.splice(0).map((e) => e.stop())))

async function rig(modes: string[], over: { busy?: () => boolean; wasCopying?: boolean } = {}) {
  const engine = new EngineProcess({ stopAskMs: 400, terminateGraceMs: 300 })
  engines.push(engine)
  await engine.start(target("serve"))
  const log = { restarts: 0, restarted: [] as boolean[], gaveUp: [] as string[] }
  const outcome = new Promise<void>((done) => {
    superviseEngine(engine, {
      delayMs: 20,
      busy: over.busy ?? (() => false),
      wasCopying: () => over.wasCopying ?? false,
      restart: async () => {
        const mode = modes[Math.min(log.restarts, modes.length - 1)]!
        log.restarts += 1
        await engine.start(target(mode))
        if (engine.state.state !== "running") throw new Error(engine.state.state === "stopped" ? engine.state.reason : "no")
      },
      onRestarted: (copying) => {
        log.restarted.push(copying)
        done()
      },
      onGaveUp: (reason) => {
        log.gaveUp.push(reason)
        done()
      },
    })
  })
  return { engine, log, outcome, die: () => engine.request("die").catch(() => {}) }
}

describe("superviseEngine", () => {
  it("starts an engine that exits unexpectedly again, saying whether copying was on", async () => {
    const r = await rig(["serve"], { wasCopying: true })
    await r.die()
    await r.outcome
    expect(r.log).toMatchObject({ restarts: 1, restarted: [true], gaveUp: [] })
    expect(r.engine.state).toEqual({ state: "running" })
    await expect(r.engine.request("get_status")).resolves.toMatchObject({ type: "status" })
  })

  it("tries three times, then stays stopped with the engine's own words", async () => {
    const r = await rig(["crash"])
    await r.die()
    await r.outcome
    expect(r.log.restarts).toBe(3)
    expect(r.log.gaveUp).toEqual(["boom: the engine could not open its database"])
    expect(r.engine.state).toEqual({ state: "stopped", reason: "boom: the engine could not open its database" })
  })

  it("gives up after fewer tries when a later one works, and keeps the count for the next crash", async () => {
    const r = await rig(["crash", "serve"])
    await r.die()
    await r.outcome
    expect(r.log).toMatchObject({ restarts: 2, restarted: [false], gaveUp: [] })
  })

  it("does not start an engine the app asked to stop", async () => {
    const r = await rig(["serve"])
    await r.engine.stop()
    await new Promise((done) => setTimeout(done, 150))
    expect(r.log.restarts).toBe(0)
  })

  it("leaves the engine alone while something else owns it, even if it was told to wait", async () => {
    let busy = true
    const r = await rig(["serve"], { busy: () => busy })
    await r.die()
    await new Promise((done) => setTimeout(done, 150))
    expect(r.log.restarts).toBe(0)
    busy = false
  })

  it("does not start the engine if the app began quitting during the wait", async () => {
    let busy = false
    const r = await rig(["serve"], { busy: () => busy })
    const dying = r.die()
    busy = true
    await dying
    await new Promise((done) => setTimeout(done, 150))
    expect(r.log.restarts).toBe(0)
  })
})
