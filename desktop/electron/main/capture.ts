import { mkdirSync, writeFileSync } from "node:fs"
import { join } from "node:path"
import { type BrowserWindow, app, nativeTheme } from "electron"
import { CHANNELS } from "../../shared/contract"

const SETTLE_MS = 2500
const FRAME_GAP_MS = Number(process.env.COPYTRADING_CAPTURE_GAP) || 120

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
    // COPYTRADING_CAPTURE_FILLS=<n>: n fills arrive together, as copied orders filling would send them.
    // COPYTRADING_CAPTURE_HOVER=<x,y>@<frame>: the pointer moves there at that frame, for what opens under it.
    const fills = Number(process.env.COPYTRADING_CAPTURE_FILLS)
    for (let i = 1; i <= fills; i++) window.webContents.send(CHANNELS.fill, { title: `Order filled ${i}`, body: `Bought ${i}.5 shares of SOXL at $4${i}.20`, route: "#/accounts/zhap-account-2" })
    const [at, hoverFrame = "1"] = (process.env.COPYTRADING_CAPTURE_HOVER ?? "").split("@")
    const hover = at ? at.split(",").map(Number) : null
    // COPYTRADING_CAPTURE_SCRIPT: page script to run first, for a panel that needs more than one press; its effects get a moment to show.
    const script = process.env.COPYTRADING_CAPTURE_SCRIPT
    if (script) {
      // A script that throws still gets its screenshot, and says why, instead of leaving the app open.
      await window.webContents.executeJavaScript(script).catch((error: unknown) => console.error("capture script failed:", error))
    }
    // COPYTRADING_CAPTURE_FRAMES=<n>: save n back-to-back frames right after the script and fills (light only), for a motion that has not finished.
    const frames = Number(process.env.COPYTRADING_CAPTURE_FRAMES)
    if ((script || fills) && frames > 0) {
      for (let i = 1; i <= frames; i++) {
        if (hover && i === Number(hoverFrame)) window.webContents.sendInputEvent({ type: "mouseMove", x: hover[0]!, y: hover[1]! })
        writeFileSync(join(dir, `${name}-frame-${String(i).padStart(2, "0")}.png`), (await window.webContents.capturePage()).toPNG())
        await wait(FRAME_GAP_MS)
      }
      return app.quit()
    }
    if (script) await wait(SETTLE_MS)
    for (const theme of ["light", "dark"] as const) {
      nativeTheme.themeSource = theme
      await new Promise((done) => setTimeout(done, 400))
      const image = await window.webContents.capturePage()
      writeFileSync(join(dir, `${name}-${theme}.png`), image.toPNG())
    }
    app.quit()
  })
}
