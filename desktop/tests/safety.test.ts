import { mkdtempSync, realpathSync, rmSync } from "node:fs"
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

  it("makes an installation root under the temp directory, short enough for the agent socket inside it", () => {
    const root = makeThrowawayRoot()
    rmSync(root, { recursive: true })
    expect(root.startsWith(realpathSync(tmpdir()))).toBe(true)
    expect(Buffer.byteLength(join(root, "control", "cli.sock"))).toBeLessThanOrEqual(103)
  })
})
