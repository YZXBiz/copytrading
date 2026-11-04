import { existsSync, mkdtempSync, rmSync, statSync } from "node:fs"
import { homedir, tmpdir } from "node:os"
import { join } from "node:path"
import { afterEach, describe, expect, it } from "vitest"
import { resolveRoots } from "../electron/main/engine/data-root"

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
    expect(roots.owner.startsWith(tmpdir()) || roots.owner.startsWith(join("/private", tmpdir()))).toBe(true)
    roots.cleanup()
    expect(existsSync(roots.owner)).toBe(false)
  })

  it("ignores a state root when not packaged, so a test cannot be pointed at the owner's folder", () => {
    const roots = resolveRoots({ packaged: false, stateRoot: OWNER })
    expect(roots.owner.startsWith(OWNER)).toBe(false)
    roots.cleanup()
  })

  it("gives the packaged app the owner's folder, with its logs and app state inside", () => {
    const home = temp("home-")
    const roots = resolveRoots({ packaged: true, home })
    const owner = join(home, "Library", "Application Support", "CopyTrading")
    expect(roots.owner).toBe(owner)
    expect(roots.logs).toBe(join(owner, "logs"))
    expect(roots.userData).toBe(join(owner, "desktop"))
    expect(statSync(owner).mode & 0o777).toBe(0o700)
    roots.cleanup()
    expect(existsSync(owner)).toBe(true) // the owner's data is never removed
  })

  it("runs the packaged app on a throwaway state root when one is named", () => {
    const stateRoot = temp("state-")
    const roots = resolveRoots({ packaged: true, stateRoot, home: temp("home-") })
    expect(roots.owner).toContain("state-")
    expect(roots.logs.startsWith(roots.owner)).toBe(true)
  })

  it("refuses a state root that is the owner's folder or outside the temp directory", () => {
    // Whether or not the owner's folder exists on this Mac, it is refused before anything is created.
    expect(() => resolveRoots({ packaged: true, stateRoot: OWNER, home: temp("home-") })).toThrow()
    expect(() => resolveRoots({ packaged: true, stateRoot: homedir(), home: temp("home-") })).toThrow(/throwaway/)
    expect(() => resolveRoots({ packaged: true, stateRoot: join(tmpdir(), "no-such-folder-xyz"), home: temp("home-") })).toThrow(/does not exist/)
  })
})
