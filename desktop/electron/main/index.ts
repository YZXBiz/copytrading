import { join } from "node:path"
import { BrowserWindow, app, dialog, ipcMain, safeStorage, session } from "electron"
import { CHANNELS, type EngineState } from "../../shared/contract"
import { type Api, createApi } from "./api"
import { captureWindow } from "./capture"
import { EngineProcess, engineTarget } from "./engine/launch"
import { fixtureApi } from "./fixtures"
import { SecretStore } from "./secrets"
import { SetupFile } from "./setup-file"

// COPYTRADING_CAPTURE_DIR + COPYTRADING_CAPTURE_NAME: save PNGs of the window and quit (npm run capture).
// COPYTRADING_CAPTURE_HASH opens a screen, for example #/gurus.
const captureDir = process.env.COPYTRADING_CAPTURE_DIR
// COPYTRADING_FIXTURES=1 serves the captured account instead of starting an engine.
const fixtures = process.env.COPYTRADING_FIXTURES === "1"
const devServer = process.env.ELECTRON_RENDERER_URL

const engine = new EngineProcess()
let api: Api

const windows = () => BrowserWindow.getAllWindows()

/** A native yes/no that the page cannot reach, skip, or reword. Cancel is the default button. */
async function confirm(text: string): Promise<boolean> {
  const options: Electron.MessageBoxOptions = { type: "question", buttons: ["Cancel", "Confirm"], defaultId: 0, cancelId: 0, noLink: true, message: text }
  const parent = BrowserWindow.getFocusedWindow() ?? windows()[0]
  const { response } = parent ? await dialog.showMessageBox(parent, options) : await dialog.showMessageBox(options)
  return response === 1
}

const cipher = {
  encrypt: (text: string) => {
    if (!safeStorage.isEncryptionAvailable()) throw new Error("This Mac's secure storage is not available, so keys cannot be saved.")
    return safeStorage.encryptString(text)
  },
  decrypt: (data: Buffer) => safeStorage.decryptString(data),
}

/** Every request answers with the reason the engine is not there. */
const unavailableApi = (reason: string): Api => ({
  read: async () => ({ ok: false, error: reason }),
  act: async () => ({ ok: false, error: reason }),
})

function startServices(): Api {
  if (fixtures) return fixtureApi
  try {
    const target = engineTarget()
    const secrets = new SecretStore(join(app.getPath("userData"), "secrets.bin"), cipher)
    void engine.start(target).catch((error: unknown) => engine.fail(error instanceof Error ? error.message : String(error)))
    return createApi({ engine, setup: new SetupFile(target.dataDir), secrets, confirm })
  } catch (error) {
    const reason = error instanceof Error ? error.message : String(error)
    engine.fail(reason)
    return unavailableApi(reason)
  }
}

function registerIpc(): void {
  ipcMain.handle(CHANNELS.read, (_event, name: unknown, params: unknown) => api.read(name, params))
  ipcMain.handle(CHANNELS.act, (_event, name: unknown, params: unknown) => api.act(name, params))
  ipcMain.handle(CHANNELS.state, (): EngineState => (fixtures ? { state: "running" } : engine.state))
  engine.onState((state) => windows().forEach((w) => w.webContents.send(CHANNELS.stateChanged, state)))
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
  const now = fixtures ? "2026-11-03T21:00:00Z" : undefined
  const hash = process.env.COPYTRADING_CAPTURE_HASH ?? ""
  if (devServer) void window.loadURL(`${devServer}${now ? `?now=${now}` : ""}${hash}`)
  else void window.loadFile(join(__dirname, "../renderer/index.html"), { query: now ? { now } : undefined, hash })
  if (captureDir) captureWindow(window, captureDir, process.env.COPYTRADING_CAPTURE_NAME ?? "window")
  return window
}

app.whenReady().then(() => {
  session.defaultSession.setPermissionRequestHandler((_wc, _permission, deny) => deny(false))
  api = startServices()
  registerIpc()
  createWindow()
})
app.on("window-all-closed", () => app.quit())

// Quitting waits for the engine to exit, as ProcessSupervisor.stop does, before the app goes.
let stopped = false
app.on("before-quit", (event) => {
  if (stopped) return
  event.preventDefault()
  stopped = true
  void engine.stop().finally(() => app.quit())
})
