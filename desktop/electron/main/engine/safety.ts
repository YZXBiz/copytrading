import { mkdtempSync, realpathSync } from "node:fs"
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

/** A fresh throwaway installation root. The short prefix keeps its agent socket path under the 104 bytes macOS allows. */
export function makeThrowawayRoot(): string {
  return assertThrowaway(mkdtempSync(join(tmpdir(), "ct-")))
}
