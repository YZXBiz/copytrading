import { mkdtempSync, rmSync } from "node:fs"
import { homedir, tmpdir } from "node:os"
import { join } from "node:path"
import { describe, expect, it } from "vitest"
import { assertThrowaway, makeThrowawayRoot } from "../electron/main/engine/safety"

describe("assertThrowaway", () => {
  it("accepts a folder under the temp directory", () => {
    const dir = mkdtempSync(join(tmpdir(), "safety-"))
    expect(assertThrowaway(dir)).toContain("safety-")
    rmSync(dir, { recursive: true })
  })

  it("refuses the owner's live data folder, without needing it to exist", () => {
    const owner = join(homedir(), "Library", "Application Support", "CopyTrading")
    expect(() => assertThrowaway(owner)).toThrow(/throwaway/)
  })

  it("refuses a folder outside the temp directory", () => {
    expect(() => assertThrowaway(homedir())).toThrow(/throwaway/)
  })

  it("hands an engine three separate throwaway folders", () => {
    const dirs = makeThrowawayRoot()
    rmSync(dirs.root, { recursive: true })
    expect(new Set([dirs.data, dirs.owner, dirs.logs]).size).toBe(3)
    for (const dir of [dirs.data, dirs.owner, dirs.logs]) expect(dir.startsWith(dirs.root)).toBe(true)
  })
})
