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
    for (const theme of ["light", "dark"] as const) {
      nativeTheme.themeSource = theme
      await new Promise((done) => setTimeout(done, 400))
      const image = await window.webContents.capturePage()
      writeFileSync(join(dir, `${name}-${theme}.png`), image.toPNG())
    }
    app.quit()
  })
}
