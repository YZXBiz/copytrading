import { randomUUID } from "node:crypto"
import { chmodSync, closeSync, existsSync, fsyncSync, lstatSync, mkdirSync, openSync, readFileSync, readdirSync, renameSync, rmSync, writeSync } from "node:fs"
import { homedir } from "node:os"
import { join } from "node:path"
import { assertThrowaway, makeThrowawayRoot } from "./safety"

/** Where one engine keeps its data. `owner` holds the installation id, the logs and the generation pointer. */
export interface EngineRoots {
  owner: string
  data: string
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

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/

/** RuntimePaths.swift: the owner's folder is a 0700 directory of this user's, never a link. */
function privateDirectory(path: string): void {
  mkdirSync(path, { recursive: true, mode: 0o700 })
  const info = lstatSync(path)
  if (!info.isDirectory() || info.uid !== process.getuid!()) throw new Error(`${path} is not a private folder of this user.`)
  chmodSync(path, 0o700)
}

/** RuntimePaths.readGenerationPointer: one canonical lowercase UUID in a plain file of this user's. */
function readPointer(path: string): string | null {
  let info
  try {
    info = lstatSync(path)
  } catch {
    return null
  }
  if (!info.isFile() || info.uid !== process.getuid!() || info.size < 1 || info.size > 64) throw new Error("The active data generation pointer is invalid.")
  const id = readFileSync(path, "utf8").replace(/\n$/, "")
  if (!UUID.test(id)) throw new Error("The active data generation pointer is invalid.")
  return id
}

function writePointer(owner: string, id: string): void {
  const temporary = join(owner, `.active-generation-${randomUUID()}.tmp`)
  const fd = openSync(temporary, "wx", 0o600)
  try {
    writeSync(fd, `${id}\n`)
    fsyncSync(fd)
  } finally {
    closeSync(fd)
  }
  renameSync(temporary, join(owner, "active-generation"))
}

/**
 * RuntimePaths.resolveActiveGeneration: the engine's data lives in generations/<id>, chosen by the
 * pointer file. A first launch makes one; anything odd refuses rather than guesses.
 */
export function activeGeneration(owner: string): string {
  privateDirectory(owner)
  const generations = join(owner, "generations")
  const pointer = join(owner, "active-generation")
  let id = readPointer(pointer)
  privateDirectory(generations)
  if (id === null) {
    if (readdirSync(generations).length > 0) throw new Error("The data generations have no active pointer.")
    id = randomUUID().toLowerCase()
    privateDirectory(join(generations, id))
    writePointer(owner, id)
  }
  const data = join(generations, id)
  const info = lstatSync(data, { throwIfNoEntry: false })
  if (!info?.isDirectory() || info.uid !== process.getuid!() || (info.mode & 0o077) !== 0) throw new Error("The active data generation is missing or not private.")
  return data
}

/** AppModel passes the engine this id; it must match the one the database was created under. */
export function installationId(owner: string): string {
  const path = join(owner, "installation-id")
  const info = lstatSync(path, { throwIfNoEntry: false })
  if (!info) {
    const id = randomUUID().toLowerCase()
    const fd = openSync(path, "wx", 0o600)
    try {
      writeSync(fd, id)
    } finally {
      closeSync(fd)
    }
    return id
  }
  const id = info.isFile() ? readFileSync(path, "utf8").trim() : ""
  if (!UUID.test(id.toLowerCase())) throw new Error("The installation identity is invalid.")
  return id.toLowerCase()
}

/**
 * Which folders an engine runs on. Only the packaged app may use the owner's real folder
 * (`~/Library/Application Support/CopyTrading`, generation pointer included); `COPYTRADING_STATE_ROOT`
 * points it at a throwaway one instead. Everywhere else a fresh folder under the temp directory,
 * and `assertThrowaway` refuses the owner's.
 */
export function resolveRoots({ packaged, stateRoot, home = homedir() }: RootsInput): EngineRoots {
  if (!packaged) {
    const dirs = makeThrowawayRoot()
    return { owner: dirs.owner, data: dirs.data, logs: dirs.logs, userData: null, cleanup: () => rmSync(dirs.root, { recursive: true, force: true }) }
  }
  if (stateRoot !== undefined && !existsSync(stateRoot)) throw new Error(`COPYTRADING_STATE_ROOT ${stateRoot} does not exist; create a folder under the temp directory first.`)
  const owner = stateRoot === undefined ? join(home, "Library", "Application Support", "CopyTrading") : assertThrowaway(stateRoot)
  const data = activeGeneration(owner)
  const logs = join(owner, "logs")
  privateDirectory(logs)
  return { owner, data, logs, userData: join(owner, "desktop"), cleanup: () => {} }
}
