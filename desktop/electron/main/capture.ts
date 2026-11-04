import { mkdirSync, writeFileSync } from "node:fs"
import { join } from "node:path"
import { type BrowserWindow, app, nativeTheme } from "electron"

const SETTLE_MS = 2500
const FRAME_GAP_MS = 120

/**
 * Saves the loaded window as light and dark PNGs with webContents.capturePage(), then quits.
 * The window is never shown, so nothing takes focus. Run it through `npm run capture`.
 * `click` is a CSS selector to click first, for a sheet or menu that opens on a press.
 */
export function captureWindow(window: BrowserWindow, dir: string, name: string, click?: string): void {
  window.webContents.once("did-finish-load", async () => {
    mkdirSync(dir, { recursive: true })
    const wait = (ms: number) => new Promise((done) => setTimeout(done, ms))
    await wait(SETTLE_MS)
    // A slow start must not be saved as a skeleton: wait (up to 15 s) until no region is still loading.
    // A capture of the loading state (COPYTRADING_FIXTURE_STATE=reads-loading) keeps its skeletons, so it does not wait for them to go.
    const loading = process.env.COPYTRADING_FIXTURE_STATE === "reads-loading"
    for (let i = 0; !loading && i < 60 && (await window.webContents.executeJavaScript(`document.querySelector('[role="status"]') !== null`)); i++) await wait(250)
    if (click) {
      await window.webContents.executeJavaScript(`document.querySelector(${JSON.stringify(click)})?.click()`)
      await wait(800)
    }
    // COPYTRADING_CAPTURE_SCRIPT: page script to run first, for a panel that needs more than one press; its effects get a moment to show.
    if (process.env.COPYTRADING_CAPTURE_SCRIPT) {
      // A script that throws still gets its screenshot, and says why, instead of leaving the app open.
      await window.webContents.executeJavaScript(process.env.COPYTRADING_CAPTURE_SCRIPT).catch((error: unknown) => console.error("capture script failed:", error))
      // COPYTRADING_CAPTURE_FRAMES=<n>: save n back-to-back frames right after the script (light only), for a motion that has not finished.
      const frames = Number(process.env.COPYTRADING_CAPTURE_FRAMES)
      if (frames > 0) {
        for (let i = 1; i <= frames; i++) {
          writeFileSync(join(dir, `${name}-frame-${i}.png`), (await window.webContents.capturePage()).toPNG())
          await wait(FRAME_GAP_MS)
        }
        return app.quit()
      }
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
