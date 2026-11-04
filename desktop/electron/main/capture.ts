import { mkdirSync, writeFileSync } from "node:fs"
import { join } from "node:path"
import { type BrowserWindow, app, nativeTheme } from "electron"

const SETTLE_MS = 2500

/**
 * Saves the loaded window as light and dark PNGs with webContents.capturePage(), then quits.
 * The window is never shown, so nothing takes focus. Run it through `npm run capture`.
 * `click` is a CSS selector to click first, for a sheet or menu that opens on a press.
 */
export function captureWindow(window: BrowserWindow, dir: string, name: string, click?: string): void {
  window.webContents.once("did-finish-load", async () => {
    mkdirSync(dir, { recursive: true })
    await new Promise((done) => setTimeout(done, SETTLE_MS))
    if (click) {
      await window.webContents.executeJavaScript(`document.querySelector(${JSON.stringify(click)})?.click()`)
      await new Promise((done) => setTimeout(done, 800))
    }
    // COPYTRADING_CAPTURE_SCRIPT: page script to run first, for a panel that needs more than one press; its effects get a moment to show.
    if (process.env.COPYTRADING_CAPTURE_SCRIPT) {
      // A script that throws still gets its screenshot, and says why, instead of leaving the app open.
      await window.webContents.executeJavaScript(process.env.COPYTRADING_CAPTURE_SCRIPT).catch((error: unknown) => console.error("capture script failed:", error))
      await new Promise((done) => setTimeout(done, SETTLE_MS))
    }
    for (const theme of ["light", "dark"] as const) {
      nativeTheme.themeSource = theme
      await new Promise((done) => setTimeout(done, 400))
      const image = await window.webContents.capturePage()
      writeFileSync(join(dir, `${name}-${theme}.png`), image.toPNG())
    }
    app.quit()
  })
}
