export const RELEASES_URL = "https://github.com/YZXBiz/copytrading/releases/latest"
/** Sparkle's SUScheduledCheckInterval was a day; the owner leaves the app open for days, so check more often. */
export const CHECK_EVERY_MS = 6 * 60 * 60 * 1000

/** The slice of electron-updater's AppUpdater this uses, so a test can stand in for it. */
export interface UpdaterLike {
  checkForUpdates(): Promise<{ isUpdateAvailable: boolean; updateInfo: { version: string } } | null>
  downloadUpdate(): Promise<unknown>
  quitAndInstall(): void
}

export interface UpdateUi {
  /** The native question: install this version now? `copyingNote` says what it does to copying, or is null. */
  offer(version: string, copyingNote: string | null): Promise<boolean>
  tell(message: string): void
}

/** AppModel+Update.updateCopyingNote: what installing does to copying that is running. */
export const copyingNote = (copying: boolean) => (copying ? "Copying pauses while it installs and starts again when CopyTrading reopens." : null)

/**
 * Looks for a new release on GitHub, asks the owner, downloads it, and relaunches into it. Copying that
 * runs now is remembered first (`remember`), so the next launch starts it again.
 */
export class Updates {
  private readonly declined = new Set<string>()
  private busy = false

  constructor(
    private readonly updater: UpdaterLike,
    private readonly ui: UpdateUi,
    private readonly copying: () => Promise<boolean>,
    private readonly remember: (on: boolean) => void,
  ) {}

  /** `manual` also says when there is nothing new, and offers a version the owner declined earlier. */
  async check(manual = false): Promise<void> {
    if (this.busy) return
    this.busy = true
    let version = ""
    try {
      const found = await this.updater.checkForUpdates()
      if (!found?.isUpdateAvailable) {
        if (manual) this.ui.tell("CopyTrading is up to date.")
        return
      }
      version = found.updateInfo.version
      if (!manual && this.declined.has(version)) return
      const copying = await this.copying()
      if (!(await this.ui.offer(version, copyingNote(copying)))) {
        this.declined.add(version)
        return
      }
      await this.updater.downloadUpdate()
      this.remember(copying)
      this.updater.quitAndInstall()
    } catch (error) {
      this.remember(false)
      const reason = error instanceof Error ? error.message : String(error)
      // An update that cannot install (macOS refuses a build signed by another identity) leaves the app running as it was.
      if (version) this.ui.tell(`CopyTrading ${version} could not be installed: ${reason}\n\nDownload it from ${RELEASES_URL}`)
      else if (manual) this.ui.tell(`CopyTrading could not check for updates: ${reason}`)
    } finally {
      this.busy = false
    }
  }
}
