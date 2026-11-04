import { randomUUID } from "node:crypto"
import { existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { afterEach, describe, expect, it } from "vitest"
import { RuntimePaths, isGenerationId } from "../electron/main/engine/paths"

const roots: string[] = []
afterEach(() => roots.splice(0).forEach((root) => rmSync(root, { recursive: true, force: true })))
const fresh = () => {
  const root = mkdtempSync(join(tmpdir(), "paths-"))
  roots.push(root)
  return new RuntimePaths(root)
}
/** A staged generation, as the engine leaves one for a restore. */
const stage = (paths: RuntimePaths) => {
  const id = randomUUID()
  mkdirSync(join(paths.owner, "generations", id), { mode: 0o700 })
  return id
}

describe("RuntimePaths", () => {
  it("makes the first generation on first launch and keeps it", () => {
    const paths = fresh()
    const first = paths.activeGeneration()
    expect(isGenerationId(first.id)).toBe(true)
    expect(first.dir).toBe(join(paths.owner, "generations", first.id))
    expect(statSync(first.dir).mode & 0o777).toBe(0o700)
    expect(readFileSync(join(paths.owner, "active-generation"), "utf8")).toBe(`${first.id}\n`)
    expect(paths.activeGeneration()).toEqual(first)
    expect(readdirSync(join(paths.owner, "generations"))).toEqual([first.id])
  })

  it("keeps one installation identity, so a backup stays restorable here", () => {
    const paths = fresh()
    const identity = paths.installationIdentity()
    expect(isGenerationId(identity)).toBe(true)
    expect(new RuntimePaths(paths.owner).installationIdentity()).toBe(identity)
  })

  it("refuses an identity file that is not an id", () => {
    const paths = fresh()
    writeFileSync(join(paths.owner, "installation-id"), "not an id")
    expect(() => paths.installationIdentity()).toThrow(/invalid/)
  })

  it("switches to a staged generation and returns the one it left", () => {
    const paths = fresh()
    const before = paths.activeGeneration().id
    const candidate = stage(paths)
    expect(paths.switchActiveGeneration(candidate, before)).toBe(before)
    expect(paths.activeGeneration().id).toBe(candidate)
    // No temporary pointer is left behind.
    expect(readdirSync(paths.owner).filter((name) => name.startsWith(".active-generation-"))).toEqual([])
  })

  it("applies no switch when the active generation is not the one expected", () => {
    const paths = fresh()
    const before = paths.activeGeneration().id
    const candidate = stage(paths)
    expect(() => paths.switchActiveGeneration(candidate, randomUUID())).toThrow(/changed during recovery/)
    expect(paths.activeGeneration().id).toBe(before)
  })

  it("refuses to switch to a generation that is not staged, or whose id is not canonical", () => {
    const paths = fresh()
    const before = paths.activeGeneration().id
    expect(() => paths.switchActiveGeneration(randomUUID(), before)).toThrow(/invalid or incomplete/)
    expect(() => paths.switchActiveGeneration("../escape", before)).toThrow(/invalid or incomplete/)
    expect(() => paths.switchActiveGeneration(before.toUpperCase(), before)).toThrow(/invalid or incomplete/)
    expect(paths.activeGeneration().id).toBe(before)
  })

  it("refuses a staged generation that others can open", () => {
    const paths = fresh()
    const before = paths.activeGeneration().id
    const open = randomUUID()
    mkdirSync(join(paths.owner, "generations", open), { mode: 0o755 })
    expect(() => paths.switchActiveGeneration(open, before)).toThrow(/invalid or incomplete/)
  })

  it("will not guess a generation when folders exist but no pointer names one", () => {
    const paths = fresh()
    paths.activeGeneration()
    rmSync(join(paths.owner, "active-generation"))
    stage(paths)
    expect(() => paths.activeGeneration()).toThrow(/invalid or incomplete/)
  })

  it("reads the restore gate", () => {
    const paths = fresh()
    paths.installationIdentity()
    expect(paths.restoreGateIsPresent()).toBe(false)
    writeFileSync(join(paths.owner, ".restore-manual-disabled"), "")
    expect(paths.restoreGateIsPresent()).toBe(true)
    expect(existsSync(paths.logs)).toBe(false)
  })
})
