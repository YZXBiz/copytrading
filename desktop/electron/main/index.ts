import { join } from "node:path"
import { BrowserWindow, app, ipcMain, session } from "electron"
import { CHANNELS } from "../../shared/contract"
import { type EngineApi, engineApi } from "./api"
import { launchEngine } from "./engine/launch"
import { captureWindow } from "./capture"
import { fixtureApi } from "./fixtures"

// COPYTRADING_CAPTURE_DIR + COPYTRADING_CAPTURE_NAME: save PNGs of the window and quit (npm run capture).
const captureDir = process.env.COPYTRADING_CAPTURE_DIR
// COPYTRADING_FIXTURES=1 serves the captured account instead of starting an engine.
const fixtures = process.env.COPYTRADING_FIXTURES === "1"
const devServer = process.env.ELECTRON_RENDERER_URL

let stopEngine = () => {}
let api: EngineApi

function startApi(): EngineApi {
  if (fixtures) return fixtureApi
  const engine = launchEngine()
  stopEngine = engine.stop
  return engineApi(engine.bridge)
}

function registerIpc(): void {
  ipcMain.handle(CHANNELS.getStatus, () => api.getStatus())
  ipcMain.handle(CHANNELS.getAccounts, () => api.getAccounts())
  ipcMain.handle(CHANNELS.getEquityHistory, (_event, accountId: unknown, range: unknown) => {
    const ranges = ["day", "week", "month", "three_months", "year"] as const
    if (typeof accountId !== "string" || !ranges.some((r) => r === range)) {
      return { ok: false, error: "The request was not valid." }
    }
    return api.getEquityHistory(accountId, range as (typeof ranges)[number])
  })
  ipcMain.handle(CHANNELS.getSourceActivity, () => api.getSourceActivity())
  ipcMain.handle(CHANNELS.getLimits, (_event, accountId: unknown) =>
    typeof accountId === "string" ? api.getLimits(accountId) : { ok: false, error: "The request was not valid." },
  )
}

function createWindow(): BrowserWindow {
  const window = new BrowserWindow({
    width: 1280,
    height: captureDir ? 1700 : 860,
    show: !captureDir,
    title: "CopyTrading",
    webPreferences: {
      preload: join(__dirname, "../preload/index.js"),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
      backgroundThrottling: !captureDir,
      offscreen: Boolean(captureDir),
    },
  })
  // The window only ever shows the app itself: no popups, no navigating away.
  window.webContents.setWindowOpenHandler(() => ({ action: "deny" }))
  window.webContents.on("will-navigate", (event) => event.preventDefault())
  // Fixture mode pins the page's clock to when the data was captured: posts expire with their trading day.
  const query = fixtures ? { now: "2026-11-03T21:00:00Z" } : undefined
  if (devServer) void window.loadURL(query ? `${devServer}?now=${query.now}` : devServer)
  else void window.loadFile(join(__dirname, "../renderer/index.html"), { query })
  if (captureDir) captureWindow(window, captureDir, process.env.COPYTRADING_CAPTURE_NAME ?? "window")
  return window
}

app.whenReady().then(() => {
  session.defaultSession.setPermissionRequestHandler((_wc, _permission, deny) => deny(false))
  api = startApi()
  registerIpc()
  createWindow()
})
app.on("window-all-closed", () => app.quit())
app.on("before-quit", () => stopEngine())
