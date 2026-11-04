import { type ChildProcess, spawn } from "node:child_process"
import { join } from "node:path"
import { afterEach, describe, expect, it } from "vitest"
import { EngineBridge, EngineError } from "../electron/main/engine/bridge"

const FAKE = join(__dirname, "fake-engine.cjs")
const children: ChildProcess[] = []

function start(mode: string, timeoutMs = 10_000) {
  const child = spawn(process.execPath, [FAKE, mode], { stdio: ["pipe", "pipe", "inherit"] })
  children.push(child)
  const bridge = new EngineBridge(child.stdin!, child.stdout!, timeoutMs)
  child.on("exit", () => bridge.failAll(new EngineError("disconnected", "The engine stopped.")))
  return { child, bridge }
}

afterEach(() => children.splice(0).forEach((child) => child.kill()))

describe("EngineBridge against a fake engine process", () => {
  it("matches each response to its request, even out of order", async () => {
    const { bridge } = start("echo-reversed")
    const [first, second] = await Promise.all([bridge.request("get_status"), bridge.request("get_accounts")])
    expect(first).toEqual({ type: "echo", operation: "get_status" })
    expect(second).toEqual({ type: "echo", operation: "get_accounts" })
  })

  it("rejects an engine error with its code", async () => {
    const { bridge } = start("error")
    await expect(bridge.request("get_equity_history")).rejects.toMatchObject({ code: "engine", message: "not_found" })
  })

  it("times out a request the engine never answers", async () => {
    const { bridge } = start("silent", 150)
    await expect(bridge.request("get_status")).rejects.toMatchObject({ code: "timed_out" })
  })

  it("fails a waiting request when the engine exits", async () => {
    const { bridge } = start("exit-on-request")
    await expect(bridge.request("get_status")).rejects.toMatchObject({ code: "disconnected" })
    await expect(bridge.request("get_status")).rejects.toMatchObject({ code: "disconnected" })
  })
})
