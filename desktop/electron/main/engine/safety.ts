import { mkdirSync, mkdtempSync, realpathSync } from "node:fs"
import { homedir, tmpdir } from "node:os"
import { join, resolve, sep } from "node:path"

const inside = (path: string, root: string) => path === root || path.startsWith(root + sep)

/**
 * Hard rule: an engine this app starts never touches the owner's real data. The owner's app runs
 * its own engine on ~/Library/Application Support/CopyTrading, and a second engine there would
 * conflict. Every directory handed to an engine must be a real path under the temp folder.
 */
export function assertThrowaway(path: string): string {
  const resolved = resolve(path)
  const owner = join(homedir(), "Library", "Application Support", "CopyTrading")
  const refuse = () =>
    new Error(`Refusing to start an engine on ${path}: it must be a throwaway folder under the temp directory.`)
  if (inside(resolved, owner)) throw refuse()
  const real = realpathSync(resolved)
  if (inside(real, owner) || !inside(real, realpathSync(tmpdir()))) throw refuse()
  return real
}

/** A fresh throwaway state root with the three directories the engine needs. */
export function makeThrowawayRoot(): { root: string; data: string; owner: string; logs: string } {
  const root = assertThrowaway(mkdtempSync(join(tmpdir(), "copytrading-dev-")))
  const dirs = { root, data: join(root, "data"), owner: join(root, "owner"), logs: join(root, "logs") }
  for (const dir of [dirs.data, dirs.owner, dirs.logs]) mkdirSync(dir, { mode: 0o700 })
  return dirs
}
