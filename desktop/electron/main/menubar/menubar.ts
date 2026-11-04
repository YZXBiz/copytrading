import { Menu, type NativeImage, Tray, nativeImage } from "electron"
import type { Tone } from "../../../shared/copying-state"
import type { EngineState, MenuBarMode, Result, SourceActivity, AccountOverviewPage, TradingStatus } from "../../../shared/contract"
import type { Api } from "../api"
import { drawMark } from "./mark"
import { type Item, type MenuAction, view } from "./words"

/** The menu bar item re-reads this often while it shows: the window's own cadence for status and accounts. */
export const POLL_MS = 10_000
/** 18 pt tall at 2×: the menu bar's size. */
const SIZE = 36

export interface MenuBarDeps {
  api: Api
  engine: () => EngineState
  mode: () => MenuBarMode
  /** Skipped calls as the window last said; null until it has. */
  skipped: () => ReadonlySet<string> | null
  /** Text shown to the owner passes through here first, so a key can never appear in the menu. */
  redact: (text: string) => string
  /** Brings the window forward, at `route` if one is named. */
  open: (route?: string) => void
  /** Pause or start, through the same native confirmation the window's buttons use. */
  pause: () => Promise<void>
  start: () => Promise<void>
  quit: () => void
}

const read = async <T>(api: Api, name: string): Promise<T | null> => {
  try {
    const result = (await api.read(name, undefined)) as Result<T>
    return result.ok ? result.value : null
  } catch {
    return null
  }
}

/** The macOS menu bar item: a coloured state dot, the balance beside it, and a short menu. Does nothing while the mode is Off. */
export class MenuBar {
  private tray: Tray | null = null
  private timer: NodeJS.Timeout | null = null
  private running = false
  private image: { tone: Tone; icon: NativeImage } | null = null
  private route: string | null = null

  constructor(private readonly deps: MenuBarDeps) {}

  /** Starts or stops to match the saved mode; call again whenever it changes. */
  apply(): void {
    if (this.deps.mode() === "off") return this.remove()
    if (!this.timer) {
      this.timer = setInterval(() => void this.refresh(), POLL_MS)
    }
    void this.refresh()
  }

  remove(): void {
    if (this.timer) clearInterval(this.timer)
    this.timer = null
    this.tray?.destroy()
    this.tray = null
  }

  private async refresh(): Promise<void> {
    if (this.running) return
    this.running = true
    try {
      const engine = this.deps.engine()
      const [status, accounts, posts] = await Promise.all([
        engine.state === "running" ? read<TradingStatus>(this.deps.api, "getStatus") : null,
        engine.state === "running" ? read<AccountOverviewPage>(this.deps.api, "getAccounts") : null,
        engine.state === "running" ? read<{ items: SourceActivity[] }>(this.deps.api, "getSourceActivity") : null,
      ])
      // The mode may have been turned off while the reads were out.
      const mode = this.deps.mode()
      if (mode === "off" || !this.timer) return
      const shown = view({ engine, status, accounts: accounts?.items ?? [], posts: posts?.items ?? [], skipped: this.deps.skipped(), now: new Date() }, mode)
      this.route = shown.waitingRoute
      const tray = (this.tray ??= new Tray(this.icon(shown.tone)))
      tray.setImage(this.icon(shown.tone))
      tray.setTitle(this.deps.redact(shown.title), { fontType: "monospacedDigit" })
      tray.setToolTip("CopyTrading")
      tray.setContextMenu(Menu.buildFromTemplate(shown.items.map((item) => this.menuItem(item))))
    } finally {
      this.running = false
    }
  }

  /** One image per tone, kept until the tone changes. */
  private icon(tone: Tone): NativeImage {
    if (this.image?.tone !== tone) this.image = { tone, icon: nativeImage.createFromBitmap(drawMark(SIZE, tone), { width: SIZE, height: SIZE, scaleFactor: 2 }) }
    return this.image.icon
  }

  private menuItem(item: Item): Electron.MenuItemConstructorOptions {
    if ("type" in item) return { type: "separator" }
    return { label: this.deps.redact(item.label), enabled: item.enabled ?? item.action !== undefined, click: item.action ? () => void this.run(item.action!) : undefined }
  }

  private async run(action: MenuAction): Promise<void> {
    if (action === "quit") return this.deps.quit()
    if (action === "waiting") return this.deps.open(this.route ?? "#/accounts")
    if (action === "open") return this.deps.open()
    // A confirmation is a sheet on the window, so the window comes forward first.
    this.deps.open()
    await (action === "pause" ? this.deps.pause() : this.deps.start())
    void this.refresh()
  }
}
