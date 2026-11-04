import { randomUUID } from "node:crypto"
import {
  chmodSync,
  closeSync,
  existsSync,
  fsyncSync,
  lstatSync,
  mkdirSync,
  openSync,
  readFileSync,
  readdirSync,
  renameSync,
  rmSync,
  writeFileSync,
  writeSync,
} from "node:fs"
import { join } from "node:path"

/** RuntimePaths.swift: the installation root and the operational generation inside it. */
export class PathsError extends Error {}

const CANONICAL = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/
export const isGenerationId = (value: string) => CANONICAL.test(value)

const mine = (path: string, kind: "dir" | "file", allowGroupAccess = true) => {
  try {
    const stat = lstatSync(path)
    const right = kind === "dir" ? stat.isDirectory() : stat.isFile()
    return right && stat.uid === process.getuid!() && (allowGroupAccess || (stat.mode & 0o077) === 0)
  } catch {
    return false
  }
}

/** A dangling link: `existsSync` follows it and says no, but it is something, and is not trusted. */
const isLink = (path: string) => {
  try {
    return lstatSync(path).isSymbolicLink()
  } catch {
    return false
  }
}

function syncDirectory(path: string): void {
  const descriptor = openSync(path, "r")
  try {
    fsyncSync(descriptor)
  } finally {
    closeSync(descriptor)
  }
}

export function privateDirectory(path: string): void {
  mkdirSync(path, { recursive: true, mode: 0o700 })
  if (!mine(path, "dir")) throw new PathsError("CopyTrading could not access its private local storage.")
  chmodSync(path, 0o700)
}

/**
 * The stable installation root (`installation-id`, `active-generation`, `generations/<uuid>`, `logs`)
 * and the one generation the engine runs on, which a restore switches.
 */
export class RuntimePaths {
  constructor(readonly owner: string) {}

  get logs(): string {
    return join(this.owner, "logs")
  }
  get controlSocket(): string {
    return join(this.owner, "control", "cli.sock")
  }
  private get generations(): string {
    return join(this.owner, "generations")
  }
  private get pointer(): string {
    return join(this.owner, "active-generation")
  }
  private get identityFile(): string {
    return join(this.owner, "installation-id")
  }
  private get restoreGate(): string {
    return join(this.owner, ".restore-manual-disabled")
  }

  /** Created once and kept: a backup is only restorable into the installation that made it. */
  installationIdentity(): string {
    privateDirectory(this.owner)
    let saved: string | null = null
    try {
      saved = readFileSync(this.identityFile, "utf8").trim()
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw new PathsError("CopyTrading could not access its private local storage.")
    }
    if (saved !== null) {
      // The SwiftUI app writes it lowercase; the engine is always given it that way.
      if (!mine(this.identityFile, "file") || !isGenerationId(saved.toLowerCase())) throw new PathsError("The local installation identity is invalid.")
      return saved.toLowerCase()
    }
    const identity = randomUUID()
    writeFileSync(this.identityFile, identity, { mode: 0o600 })
    return identity
  }

  /** A present or unreadable marker keeps copying behind the restore gate. */
  restoreGateIsPresent(): boolean {
    try {
      lstatSync(this.restoreGate)
      return true
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code === "ENOENT") return false
      throw new PathsError("CopyTrading could not access its private local storage.")
    }
  }

  private readPointer(): string | null {
    if (!existsSync(this.pointer) && !isLink(this.pointer)) return null
    if (!mine(this.pointer, "file")) throw new PathsError("The selected operational generation is invalid or incomplete.")
    let raw: string
    try {
      raw = readFileSync(this.pointer, "utf8")
    } catch {
      throw new PathsError("The selected operational generation is invalid or incomplete.")
    }
    const id = raw.endsWith("\n") ? raw.slice(0, -1) : raw
    if (!isGenerationId(id)) throw new PathsError("The selected operational generation is invalid or incomplete.")
    return id
  }

  private generationDir(id: string): string {
    if (!isGenerationId(id) || !mine(this.generations, "dir")) throw new PathsError("The selected operational generation is invalid or incomplete.")
    const dir = join(this.generations, id)
    if (!mine(dir, "dir", false)) throw new PathsError("The selected operational generation is invalid or incomplete.")
    return dir
  }

  /** The generation the engine runs on; the first launch makes one. */
  activeGeneration(): { id: string; dir: string } {
    privateDirectory(this.owner)
    privateDirectory(this.generations)
    let id = this.readPointer()
    if (id === null) {
      if (readdirSync(this.generations).length > 0) throw new PathsError("The selected operational generation is invalid or incomplete.")
      id = randomUUID()
      privateDirectory(join(this.generations, id))
      this.writePointer(id)
    }
    return { id, dir: this.generationDir(id) }
  }

  /** Selects an already staged generation and returns the one it replaced, which a rollback goes back to. */
  switchActiveGeneration(candidate: string, expectedCurrent: string): string {
    if (!isGenerationId(candidate)) throw new PathsError("The selected operational generation is invalid or incomplete.")
    const current = this.readPointer()
    if (current !== expectedCurrent) throw new PathsError("The active operational generation changed during recovery; no switch was applied.")
    this.generationDir(candidate)
    this.writePointer(candidate)
    return current
  }

  /** Write beside, flush, rename, flush the folder: a crash leaves the old pointer or the new one, never half of one. */
  private writePointer(id: string): void {
    const temporary = join(this.owner, `.active-generation-${randomUUID()}.tmp`)
    const descriptor = openSync(temporary, "wx", 0o600)
    try {
      writeSync(descriptor, `${id}\n`)
      fsyncSync(descriptor)
    } catch (error) {
      closeSync(descriptor)
      rmSync(temporary, { force: true })
      throw error
    }
    closeSync(descriptor)
    renameSync(temporary, this.pointer)
    syncDirectory(this.owner)
  }
}
