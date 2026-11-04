import { execFile } from "node:child_process"
import { chmodSync, existsSync, mkdirSync, mkdtempSync, realpathSync, rmSync, statSync, symlinkSync, writeFileSync } from "node:fs"
import { createConnection } from "node:net"
import { tmpdir } from "node:os"
import { join, resolve } from "node:path"
import { promisify } from "node:util"
import { afterEach, describe, expect, it } from "vitest"
import { AgentAccessStore } from "../electron/main/agents/access"
import { AgentAccessController } from "../electron/main/agents/controller"
import { AgentRelay, type AgentContext, MAX_LINE_BYTES, errorLine } from "../electron/main/agents/relay"

const run = promisify(execFile)
const roots: string[] = []
const relays: AgentRelay[] = []
afterEach(async () => {
  await Promise.all(relays.splice(0).map((r) => r.stop()))
  roots.splice(0).forEach((root) => rmSync(root, { recursive: true, force: true }))
})

/** A short real path: a socket path may not pass 103 bytes, and /var is a link to /private/var. */
const root = () => {
  const dir = realpathSync(mkdtempSync(join(tmpdir(), "rl-")))
  roots.push(dir)
  return dir
}
const socketOf = (dir: string) => join(dir, "control", "cli.sock")

/** One line out, everything the relay says back. */
function ask(path: string, line: string | Buffer, { end = true } = {}): Promise<string> {
  return new Promise((done, fail) => {
    const socket = createConnection(path)
    let reply = ""
    socket.setEncoding("utf8")
    socket.on("data", (chunk: string) => (reply += chunk))
    socket.on("close", () => done(reply))
    socket.on("error", fail)
    socket.write(line)
    if (end) socket.end()
  })
}

async function relay(send: (line: string, context: AgentContext) => Promise<string>, access: "read_pause" | "propose" = "propose") {
  const dir = root()
  const r = new AgentRelay(socketOf(dir), access, send)
  relays.push(r)
  await r.start()
  return { dir, path: socketOf(dir), relay: r }
}

describe("AgentRelay", () => {
  it("opens a socket only its owner can use, in a folder only its owner can enter", async () => {
    const { dir, path } = await relay(async () => "{}")
    expect(statSync(path).mode & 0o777).toBe(0o600)
    expect(statSync(join(dir, "control")).mode & 0o777).toBe(0o700)
    expect(statSync(path).isSocket()).toBe(true)
  })

  it("passes a line to the engine with the owner's access level and answers with the engine's reply unchanged", async () => {
    const seen: { line: string; context: AgentContext }[] = []
    const { path } = await relay(async (line, context) => (seen.push({ line, context }), '{"schema_version":1,"request_id":"r","ok":{"type":"status"},"error":null}'), "read_pause")
    expect(await ask(path, '{"operation":"get_status","request_id":"r"}\n')).toBe('{"schema_version":1,"request_id":"r","ok":{"type":"status"},"error":null}\n')
    expect(seen).toEqual([
      {
        line: '{"operation":"get_status","request_id":"r"}',
        context: { access_level: "read_pause", unlocked: true, caller_pid: null, caller_path: null, app_actions: true, setup_changes: false },
      },
    ])
  })

  it("answers a request the engine cannot be reached for in the contract's own shape", async () => {
    const { path } = await relay(async () => {
      throw new Error("The engine is starting.")
    })
    expect(JSON.parse(await ask(path, '{"operation":"get_status"}\n'))).toEqual({
      schema_version: 1,
      request_id: "",
      ok: null,
      error: { code: "unavailable", message: "The CopyTrading engine is not available." },
    })
  })

  it("answers the setup operations itself, since their lines carry keys that never go to the engine", async () => {
    const seen: string[] = []
    const { path } = await relay(async (line) => (seen.push(line), "{}"))
    for (const operation of ["get_setup", "edit_setup_discord", "edit_setup_model", "edit_setup_account", "edit_setup_guru", "edit_setup_alerts", "import_setup", "apply_setup", "discard_setup"]) {
      const reply = JSON.parse(await ask(path, `${JSON.stringify({ operation, key: "SENTINEL" })}\n`))
      expect(reply.error).toEqual({ code: "unavailable", message: "This CopyTrading cannot change its setup from here." })
    }
    expect(seen).toEqual([])
  })

  it("refuses a line that is not valid UTF-8, and a request that ends without a line", async () => {
    const { path } = await relay(async () => "{}")
    expect(JSON.parse(await ask(path, Buffer.from([0xff, 0xfe, 10])))).toMatchObject({ error: { code: "invalid_request", message: "The request is not valid." } })
    expect(JSON.parse(await ask(path, '{"operation":"get_status"}'))).toMatchObject({ error: { code: "invalid_request" } })
  })

  it("answers an oversized request, rather than dropping it, and never sends it on", async () => {
    const seen: string[] = []
    const { path } = await relay(async (line) => (seen.push(line), "{}"))
    const reply = JSON.parse(await ask(path, `${"x".repeat(MAX_LINE_BYTES + 10)}\n`))
    expect(reply.error).toEqual({ code: "invalid_request", message: "The request is too large: CopyTrading takes at most 64 KB in one request." })
    expect(seen).toEqual([])
  })

  it("takes a request of exactly the limit", async () => {
    const seen: number[] = []
    const { path } = await relay(async (line) => (seen.push(line.length), "{}"))
    await ask(path, `${"x".repeat(MAX_LINE_BYTES)}\n`)
    expect(seen).toEqual([MAX_LINE_BYTES])
  })

  it("serves four at once and tells a fifth to wait", async () => {
    const release: (() => void)[] = []
    let holding = true
    const { path } = await relay(() => (holding ? new Promise<string>((done) => release.push(() => done('{"ok":true}'))) : Promise.resolve('{"ok":true}')))
    const first = [1, 2, 3, 4].map(() => ask(path, '{"operation":"get_status"}\n'))
    await new Promise((done) => setTimeout(done, 100))
    expect(release).toHaveLength(4)
    expect(JSON.parse(await ask(path, '{"operation":"get_status"}\n'))).toMatchObject({ error: { code: "busy", message: "Too many requests; wait a few seconds." } })
    holding = false
    release.forEach((done) => done())
    expect(await Promise.all(first)).toEqual(Array(4).fill('{"ok":true}\n'))
    // A slot is free again.
    expect(await ask(path, '{"operation":"get_status"}\n')).toBe('{"ok":true}\n')
  })

  it("replaces a stale socket of its own, and removes its socket when it stops", async () => {
    const dir = root()
    const first = new AgentRelay(socketOf(dir), "propose", async () => "{}")
    await first.start()
    // The app crashed: the file is left behind with nothing listening on it.
    const second = new AgentRelay(socketOf(dir), "propose", async () => '{"again":true}')
    relays.push(second)
    await first.stop()
    expect(existsSync(socketOf(dir))).toBe(false)
    await second.start()
    expect(await ask(socketOf(dir), "{}\n")).toBe('{"again":true}\n')
    await second.stop()
    expect(existsSync(socketOf(dir))).toBe(false)
  })

  it("refuses to open on something that is not its own socket", async () => {
    const dir = root()
    mkdirSync(join(dir, "control"), { mode: 0o700 })
    writeFileSync(socketOf(dir), "a regular file")
    await expect(new AgentRelay(socketOf(dir), "propose", async () => "{}").start()).rejects.toThrow(/not a private folder/)
    expect(existsSync(socketOf(dir))).toBe(true)
  })

  it("closes up a folder others could enter, and refuses one that is a link", async () => {
    const dir = root()
    mkdirSync(join(dir, "control"), { mode: 0o755 })
    const open = new AgentRelay(socketOf(dir), "propose", async () => "{}")
    relays.push(open)
    await open.start()
    expect(statSync(join(dir, "control")).mode & 0o777).toBe(0o700)

    const other = root()
    const elsewhere = root()
    symlinkSync(elsewhere, join(other, "control"))
    await expect(new AgentRelay(socketOf(other), "propose", async () => "{}").start()).rejects.toThrow(/not a private folder/)
    chmodSync(elsewhere, 0o700)
  })

  it("refuses a socket path too long for a Unix socket", async () => {
    const dir = root()
    await expect(new AgentRelay(join(dir, "x".repeat(120), "cli.sock"), "propose", async () => "{}").start()).rejects.toThrow(/too long/)
  })

  it("words a refusal as the contract does", () => {
    expect(JSON.parse(errorLine("busy", "wait"))).toEqual({ schema_version: 1, request_id: "", ok: null, error: { code: "busy", message: "wait" } })
  })
})

describe("AgentAccessController", () => {
  const engine = (calls: string[] = []) => async (operation: string, params?: Record<string, unknown>) => {
    calls.push(operation)
    if (operation === "control") return { type: "control", line: `reply:${(params as { line: string }).line}` }
    return {}
  }

  it("is off until the owner allows agents, with no socket", async () => {
    const dir = root()
    const agents = new AgentAccessController(new AgentAccessStore(dir), socketOf(dir), engine())
    await agents.start()
    expect(agents.state()).toEqual({ access: "off", listening: false, problem: null })
    expect(existsSync(socketOf(dir))).toBe(false)
  })

  it("opens the socket at the chosen level, sends lines to the engine's control operation, and remembers the choice", async () => {
    const dir = root()
    const calls: string[] = []
    const agents = new AgentAccessController(new AgentAccessStore(dir), socketOf(dir), engine(calls))
    await agents.start()
    expect(await agents.set("propose")).toEqual({ access: "propose", listening: true, problem: null })
    expect(await ask(socketOf(dir), "hello\n")).toBe("reply:hello\n")
    expect(calls).toEqual(["control"])
    await agents.stop()
    const next = new AgentAccessController(new AgentAccessStore(dir), socketOf(dir), engine())
    await next.start()
    expect(next.state().access).toBe("propose")
    expect(next.state().listening).toBe(true)
    await next.stop()
  })

  it("closes what agents had asked for when the choice changes, and closes the socket when turned off", async () => {
    const dir = root()
    const calls: string[] = []
    const agents = new AgentAccessController(new AgentAccessStore(dir), socketOf(dir), engine(calls))
    await agents.start()
    await agents.set("read_pause")
    expect(calls).toEqual([])
    await agents.set("propose")
    expect(calls).toEqual(["discard_proposals"])
    await agents.set("off")
    expect(calls).toEqual(["discard_proposals", "discard_proposals"])
    expect(existsSync(socketOf(dir))).toBe(false)
    expect(agents.state()).toEqual({ access: "off", listening: false, problem: null })
  })

  it("says why the socket did not open, and keeps the choice", async () => {
    const dir = root()
    const agents = new AgentAccessController(new AgentAccessStore(dir), join(dir, "x".repeat(120), "cli.sock"), engine())
    const state = await agents.set("propose")
    expect(state).toMatchObject({ access: "propose", listening: false, problem: expect.stringContaining("Agents cannot connect") })
  })

  it("shows the saved choice before the engine is up, not yet listening", async () => {
    const dir = root()
    new AgentAccessStore(dir).save("propose")
    const agents = new AgentAccessController(new AgentAccessStore(dir), socketOf(dir), engine())
    expect(agents.state()).toEqual({ access: "propose", listening: false, problem: null })
  })

  it("stays off, and says so, when the saved choice cannot be read", async () => {
    const dir = root()
    writeFileSync(join(dir, "agent-access.json"), '{"access":"everything"}')
    const agents = new AgentAccessController(new AgentAccessStore(dir), socketOf(dir), engine())
    await agents.start()
    expect(agents.state()).toMatchObject({ access: "off", listening: false, problem: expect.stringContaining("stays off until you choose again") })
  })
})

// The real `copytrading` command, as an agent runs it, against the relay. It needs a Python with the engine's wire models (pydantic).
const STATUS = (request_id: string) =>
  JSON.stringify({
    schema_version: 1,
    request_id,
    ok: {
      type: "status",
      engine_state: "running",
      processing: { state: "running", copying: "copying", copying_detail: null, source_connected: true, model_ready: true, pending_source: 2, pending_signals: 1, processed_signals: 9, error_code: null },
      accounts: [],
    },
    error: null,
  })

const ENGINE_SRC = resolve(__dirname, "../../engine/src")

async function cli(stateRoot: string, ...args: string[]) {
  const env = { PATH: process.env.PATH ?? "", HOME: process.env.HOME ?? "", PYTHONPATH: ENGINE_SRC, COPYTRADING_STATE_ROOT: stateRoot }
  return run("uv", ["run", "--no-project", "--python", "3.14", "--with", "pydantic", "python", "-m", "copytrading_engine.control", ...args], { cwd: stateRoot, env }).then(
    (done) => ({ code: 0, stdout: done.stdout, stderr: done.stderr }),
    (error: { code: number; stdout: string; stderr: string }) => ({ code: error.code, stdout: error.stdout, stderr: error.stderr }),
  )
}

describe("the copytrading command against the relay", () => {
  it("`status` reaches the engine through the relay and prints what it answered", { timeout: 120_000 }, async () => {
    const seen: { line: string; context: AgentContext }[] = []
    const { dir } = await relay(async (line, context) => {
      seen.push({ line, context })
      return STATUS((JSON.parse(line) as { request_id: string }).request_id)
    }, "read_pause")
    const result = await cli(dir, "status")
    expect(result.stderr).toBe("")
    expect(result.code).toBe(0)
    expect(result.stdout).toContain("Engine      running")
    expect(result.stdout).toContain("Queued      2 messages, 1 signals")
    expect(seen).toHaveLength(1)
    expect(JSON.parse(seen[0]!.line)).toMatchObject({ operation: "get_status", schema_version: 1 })
    expect(seen[0]!.context).toMatchObject({ access_level: "read_pause", unlocked: true, app_actions: true })
  })

  it("is told the app is not running, or agent access is off, when there is no socket", { timeout: 120_000 }, async () => {
    const dir = root()
    const agents = new AgentAccessController(new AgentAccessStore(dir), socketOf(dir), async () => ({}))
    await agents.start()
    const result = await cli(dir, "status")
    expect(result.code).not.toBe(0)
    expect(result.stderr).toContain("CopyTrading is not running, or agent access is turned off.")
  })

  it("is not served after the owner turns agent access off", { timeout: 120_000 }, async () => {
    const dir = root()
    const agents = new AgentAccessController(new AgentAccessStore(dir), socketOf(dir), async (op, params) => (op === "control" ? { type: "control", line: STATUS(JSON.parse((params as { line: string }).line).request_id) } : {}))
    await agents.set("read_pause")
    expect((await cli(dir, "status")).code).toBe(0)
    await agents.set("off")
    const result = await cli(dir, "status")
    expect(result.code).not.toBe(0)
    expect(result.stderr).toContain("agent access is turned off")
  })
})
