import { existsSync, mkdtempSync, readFileSync, rmSync, statSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { afterEach, describe, expect, it } from "vitest"
import { EngineProcess } from "../electron/main/engine/launch"
import { appendEngineLog } from "../electron/main/engine/engine-log"

const dirs: string[] = []
const folder = () => {
  const dir = mkdtempSync(join(tmpdir(), "engine-log-"))
  dirs.push(dir)
  return dir
}
afterEach(() => dirs.splice(0).forEach((dir) => rmSync(dir, { recursive: true, force: true })))

describe("appendEngineLog", () => {
  it("creates the folder and appends, privately", () => {
    const file = join(folder(), "logs", "engine.log")
    appendEngineLog(file, "one\n")
    appendEngineLog(file, Buffer.from("two\n"))
    expect(readFileSync(file, "utf8")).toBe("one\ntwo\n")
    expect(statSync(file).mode & 0o077).toBe(0)
  })

  it("keeps two files, the newest and the one before, so it stays small", () => {
    const file = join(folder(), "engine.log")
    for (const line of ["aaaa\n", "bbbb\n", "cccc\n", "dddd\n", "eeee\n"]) appendEngineLog(file, line, 10)
    expect(readFileSync(file, "utf8")).toBe("eeee\n")
    expect(readFileSync(`${file}.1`, "utf8")).toBe("cccc\ndddd\n")
    expect(existsSync(`${file}.2`)).toBe(false)
  })

  it("never throws when the log cannot be written", () => {
    expect(() => appendEngineLog("/dev/null/engine.log", "x")).not.toThrow()
  })
})

describe("EngineProcess", () => {
  it("keeps everything the engine wrote to stderr in its log file", async () => {
    const logFile = join(folder(), "engine.log")
    const engine = new EngineProcess()
    await engine.start({ command: process.execPath, args: [join(__dirname, "fake-engine.cjs"), "crash"], env: {}, cwd: __dirname, logFile })
    for (let i = 0; i < 50 && engine.state.state !== "stopped"; i++) await new Promise((done) => setTimeout(done, 100))
    const log = readFileSync(logFile, "utf8")
    expect(log).toMatch(/^--- engine started \d{4}-/)
    expect(log).toContain("boom: the engine could not open its database")
  })
})
