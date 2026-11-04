import { existsSync, readFileSync, renameSync, writeFileSync } from "node:fs"
import { join } from "node:path"
import { MENU_BAR_MODES, type MenuBarMode, type Theme, THEMES } from "../../shared/contract"

interface Saved {
  /** Settings "Fills": a macOS notification for each order sent and filled. On unless the owner turns it off. */
  fill_alerts: boolean
  /** CopyingMemory: copying was on the last time the app looked. */
  copying_was_on: boolean
  /** Settings > General "Theme". The desk opens dark unless the owner chose otherwise. */
  theme: Theme
  /** Settings > General "Menu bar". Balance and dot unless the owner narrows or removes it. */
  menu_bar: MenuBarMode
}

/** The few choices the app itself remembers, in the installation root next to `agent-access.json`. */
export class Prefs {
  private saved: Saved
  private readonly path: string

  constructor(owner: string) {
    this.path = join(owner, "preferences.json")
    let read: Partial<Saved> = {}
    try {
      if (existsSync(this.path)) read = JSON.parse(readFileSync(this.path, "utf8"))
    } catch {
      // An unreadable file is the same as none: these are only alert choices, and the defaults are safe.
    }
    this.saved = { fill_alerts: read.fill_alerts ?? true, copying_was_on: read.copying_was_on ?? false, theme: THEMES.find((t) => t === read.theme) ?? "dark", menu_bar: MENU_BAR_MODES.find((m) => m === read.menu_bar) ?? "balance" }
  }

  get<K extends keyof Saved>(key: K): Saved[K] {
    return this.saved[key]
  }

  set<K extends keyof Saved>(key: K, value: Saved[K]): void {
    this.saved = { ...this.saved, [key]: value }
    const temporary = `${this.path}.tmp`
    writeFileSync(temporary, JSON.stringify(this.saved), { mode: 0o600 })
    renameSync(temporary, this.path)
  }
}
