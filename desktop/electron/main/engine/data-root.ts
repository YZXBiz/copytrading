import { existsSync, rmSync } from "node:fs"
import { homedir } from "node:os"
import { join } from "node:path"
import { privateDirectory } from "./paths"
import { assertThrowaway, makeThrowawayRoot } from "./safety"

/** Where one engine installation keeps its data. `owner` holds the installation id, the generation pointer and the logs; `paths.ts` reads them. */
export interface EngineRoots {
  owner: string
  logs: string
  /** The app's own state (the key store, the resume marker); null leaves Electron's default. */
  userData: string | null
  /** Removes what the roots created; a no-op for the owner's real folder. */
  cleanup: () => void
}

export interface RootsInput {
  /** True only in the built app (`app.isPackaged`). Dev and tests never set it. */
  packaged: boolean
  /** `COPYTRADING_STATE_ROOT`: an existing throwaway folder to use instead of the owner's. */
  stateRoot?: string
  home?: string
}

/**
 * Which folder an engine runs on. Only the packaged app may use the owner's real folder
 * (`~/Library/Application Support/CopyTrading`, generation pointer included); `COPYTRADING_STATE_ROOT`
 * points it at a throwaway one instead. Everywhere else a fresh folder under the temp directory,
 * and `assertThrowaway` refuses the owner's.
 */
export function resolveRoots({ packaged, stateRoot, home = homedir() }: RootsInput): EngineRoots {
  if (!packaged) {
    const root = makeThrowawayRoot()
    return { owner: root, logs: join(root, "logs"), userData: null, cleanup: () => rmSync(root, { recursive: true, force: true }) }
  }
  if (stateRoot !== undefined && !existsSync(stateRoot)) throw new Error(`COPYTRADING_STATE_ROOT ${stateRoot} does not exist; create a folder under the temp directory first.`)
  const owner = stateRoot === undefined ? join(home, "Library", "Application Support", "CopyTrading") : assertThrowaway(stateRoot)
  privateDirectory(owner)
  const logs = join(owner, "logs")
  privateDirectory(logs)
  return { owner, logs, userData: join(owner, "desktop"), cleanup: () => {} }
}
