import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs"
import { homedir, tmpdir } from "node:os"
import { join } from "node:path"
import { afterEach, describe, expect, it } from "vitest"
import { activeGeneration, installationId, resolveRoots } from "../electron/main/engine/data-root"

const made: string[] = []
const temp = (name = "data-root-") => {
  const dir = mkdtempSync(join(tmpdir(), name))
  made.push(dir)
  return dir
}
afterEach(() => made.splice(0).forEach((dir) => rmSync(dir, { recursive: true, force: true })))

const OWNER = join(homedir(), "Library", "Application Support", "CopyTrading")

describe("resolveRoots", () => {
  it("never gives the owner's folder to dev or tests: a fresh throwaway one under the temp directory", () => {
    const roots = resolveRoots({ packaged: false })
    expect(roots.owner.startsWith(OWNER)).toBe(false)
    expect(roots.data.startsWith(OWNER)).toBe(false)
    expect(roots.data.startsWith(tmpdir()) || roots.data.startsWith(join("/private", tmpdir()))).toBe(true)
    roots.cleanup()
    expect(existsSync(roots.data)).toBe(false)
  })

  it("ignores a state root when not packaged, so a test cannot be pointed at the owner's folder", () => {
    const roots = resolveRoots({ packaged: false, stateRoot: OWNER })
    expect(roots.owner.startsWith(OWNER)).toBe(false)
    roots.cleanup()
  })

  it("gives the packaged app the owner's folder, with its generation, logs and app state inside", () => {
    const home = temp("home-")
    const roots = resolveRoots({ packaged: true, home })
    const owner = join(home, "Library", "Application Support", "CopyTrading")
    expect(roots.owner).toBe(owner)
    expect(roots.logs).toBe(join(owner, "logs"))
    expect(roots.userData).toBe(join(owner, "desktop"))
    const id = readFileSync(join(owner, "active-generation"), "utf8").trim()
    expect(roots.data).toBe(join(owner, "generations", id))
    roots.cleanup()
    expect(existsSync(roots.data)).toBe(true) // the owner's data is never removed
  })

  it("runs the packaged app on a throwaway state root when one is named", () => {
    const stateRoot = temp("state-")
    const roots = resolveRoots({ packaged: true, stateRoot, home: temp("home-") })
    expect(roots.owner).toContain("state-")
    expect(roots.data.startsWith(roots.owner)).toBe(true)
  })

  it("refuses a state root that is the owner's folder or outside the temp directory", () => {
    // Whether or not the owner's folder exists on this Mac, it is refused before anything is created.
    expect(() => resolveRoots({ packaged: true, stateRoot: OWNER, home: temp("home-") })).toThrow()
    expect(() => resolveRoots({ packaged: true, stateRoot: homedir(), home: temp("home-") })).toThrow(/throwaway/)
    expect(() => resolveRoots({ packaged: true, stateRoot: join(tmpdir(), "no-such-folder-xyz"), home: temp("home-") })).toThrow(/does not exist/)
  })
})

describe("activeGeneration", () => {
  it("keeps the generation the pointer names, across launches", () => {
    const owner = temp()
    const first = activeGeneration(owner)
    expect(activeGeneration(owner)).toBe(first)
    expect(readdirSync(join(owner, "generations"))).toHaveLength(1)
  })

  it("follows a pointer the Swift app wrote", () => {
    const owner = temp()
    const id = "0d3b6f0e-9a1c-4f5e-8a77-2c1d9e0b4a11"
    mkdirSync(join(owner, "generations", id), { recursive: true, mode: 0o700 })
    writeFileSync(join(owner, "active-generation"), `${id}\n`, { mode: 0o600 })
    expect(activeGeneration(owner)).toBe(join(owner, "generations", id))
  })

  it("refuses a pointer that is not a canonical id, a missing generation, a shared one, and orphan generations", () => {
    const owner = temp()
    writeFileSync(join(owner, "active-generation"), "../../etc\n")
    expect(() => activeGeneration(owner)).toThrow(/invalid/)
    const id = "0d3b6f0e-9a1c-4f5e-8a77-2c1d9e0b4a11"
    writeFileSync(join(owner, "active-generation"), `${id}\n`)
    expect(() => activeGeneration(owner)).toThrow(/missing/)
    mkdirSync(join(owner, "generations", id), { mode: 0o755 })
    chmodSync(join(owner, "generations", id), 0o755)
    expect(() => activeGeneration(owner)).toThrow(/not private/)
    const stray = temp()
    mkdirSync(join(stray, "generations", id), { recursive: true, mode: 0o700 })
    expect(() => activeGeneration(stray)).toThrow(/no active pointer/)
  })
})

describe("installationId", () => {
  it("creates one id, then returns the same, so the database keeps matching its installation", () => {
    const owner = temp()
    const id = installationId(owner)
    expect(id).toMatch(/^[0-9a-f-]{36}$/)
    expect(installationId(owner)).toBe(id)
  })

  it("accepts the id the Swift app saved, even in capitals", () => {
    const owner = temp()
    writeFileSync(join(owner, "installation-id"), "0D3B6F0E-9A1C-4F5E-8A77-2C1D9E0B4A11\n")
    expect(installationId(owner)).toBe("0d3b6f0e-9a1c-4f5e-8a77-2c1d9e0b4a11")
  })

  it("refuses an id that is not a UUID", () => {
    const owner = temp()
    writeFileSync(join(owner, "installation-id"), "hello")
    expect(() => installationId(owner)).toThrow(/invalid/)
  })
})
