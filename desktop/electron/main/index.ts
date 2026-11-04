import { join } from "node:path"
import { BrowserWindow, Menu, Notification, app, dialog, ipcMain, protocol, safeStorage, session } from "electron"
import { autoUpdater } from "electron-updater"
import { CHANNELS, type EngineState } from "../../shared/contract"
import { AgentAccessStore } from "./agents/access"
import { AgentAccessController } from "./agents/controller"
import { AlertMonitor } from "./alerts/monitor"
import { CopyingMemory } from "./alerts/watch"
import type { Note } from "./alerts/words"
import { type Api, type Deps, createApi } from "./api"
import { captureWindow } from "./capture"
import { type EngineRoots, resolveRoots } from "./engine/data-root"
import { EngineProcess, engineTarget } from "./engine/launch"
import { superviseEngine } from "./engine/supervise"
import { RuntimePaths } from "./engine/paths"
import { fixtureApi, seedFixturePictures } from "./fixtures"
import { moveKeychainSecrets, securityReader } from "./keychain-move"
import { PICTURE_SCHEME, PictureIndex } from "./pictures"
import { Prefs } from "./prefs"
import { RestoreCoordinator } from "./restore"
import { ResumeMarker, resumeCopying } from "./resume"
import { SecretStore, redact, redactState } from "./secrets"
import { SetupFile } from "./setup-file"
import { CHECK_EVERY_MS, Updates } from "./update"

// COPYTRADING_CAPTURE_DIR + COPYTRADING_CAPTURE_NAME: save PNGs of the window and quit (npm run capture).
// COPYTRADING_CAPTURE_HASH opens a screen, for example #/gurus.
const captureDir = process.env.COPYTRADING_CAPTURE_DIR
// COPYTRADING_FIXTURES=1 serves the captured account instead of starting an engine.
const fixtures = process.env.COPYTRADING_FIXTURES === "1"
const devServer = process.env.ELECTRON_RENDERER_URL

// The built app runs on the owner's data folder (generation pointer included); COPYTRADING_STATE_ROOT, an
// existing folder under the temp directory, runs it on a throwaway one instead. Dev and tests never get the owner's.
// COPYTRADING_SMOKE=1 (with a state root) quits with 0 once the engine answers and the page loads, 1 otherwise.
const packaged = app.isPackaged && !fixtures
const stateRoot = process.env.COPYTRADING_STATE_ROOT
const smoke = packaged && process.env.COPYTRADING_SMOKE === "1" && stateRoot !== undefined

let roots: EngineRoots | null = null
let rootsError: string | null = null
if (!fixtures) {
  try {
    roots = resolveRoots({ packaged, stateRoot })
    if (roots.userData) app.setPath("userData", roots.userData)
  } catch (error) {
    rootsError = error instanceof Error ? error.message : String(error)
  }
}
// A second copy would fight the first over the engine's data: it quits at once, and the first one comes forward,
// with a new window if the owner had closed it (closing the window leaves the app running).
if (packaged && !app.requestSingleInstanceLock()) app.exit(0)
app.on("second-instance", () => app.isReady() && openWindow())

const engine = new EngineProcess()
let api: Api
let secrets: SecretStore | null = null
// What the api was built from, for the one caller that answers every confirmation itself (copying resumed after an update).
let services: Deps | null = null
// `<active generation>/attachments`: the only place ct-picture:// reads from. It follows a restore's switch of generation.
let attachments: (() => string) | null = null
let agents: AgentAccessController | null = null
let monitor: AlertMonitor | null = null
let restore: Pick<RestoreCoordinator, "activate" | "rollback" | "isRunning"> | null = null
const pictures = new PictureIndex()
protocol.registerSchemesAsPrivileged([{ scheme: PICTURE_SCHEME, privileges: { standard: true, secure: true } }])

/** The engine's state as the renderer may see it: a stopped engine's reason is the engine's own stderr. */
const publicState = (): EngineState => redactState(fixtures ? { state: "running" } : engine.state, secrets?.values() ?? [])

const windows = () => BrowserWindow.getAllWindows()

/** Shows the window (opening one if the owner closed it), at `route` if one is named. */
function openWindow(route?: string): void {
  const window = windows()[0] ?? createWindow()
  if (window.isMinimized()) window.restore()
  window.show()
  window.focus()
  // The route is built by main from ids, and quoted as a string, so it can only ever set the hash.
  if (route) void window.webContents.executeJavaScript(`location.hash = ${JSON.stringify(route)}`)
}

const shown = new Set<Notification>()
/** A macOS notification with the system sound. Clicking it opens CopyTrading where the news is. */
function notify(note: Note): void {
  if (!Notification.isSupported()) return
  const notification = new Notification({ title: note.title, body: note.body })
  shown.add(notification)
  notification.on("click", () => openWindow(note.route))
  notification.on("close", () => shown.delete(notification))
  notification.show()
}

/** A native yes/no that the page cannot reach, skip, or reword. Cancel is the default button. */
async function confirm(text: string): Promise<boolean> {
  // macOS shows `message` in bold and `detail` below it.
  const [message = "", ...rest] = text.split("\n\n")
  const options: Electron.MessageBoxOptions = {
    type: "question",
    buttons: ["Cancel", "Confirm"],
    defaultId: 0,
    cancelId: 0,
    noLink: true,
    message,
    detail: rest.join("\n\n") || undefined,
  }
  const parent = BrowserWindow.getFocusedWindow() ?? windows()[0]
  const { response } = parent ? await dialog.showMessageBox(parent, options) : await dialog.showMessageBox(options)
  return response === 1
}

/** Where to save a backup, or which one to open: a native dialog the page cannot reach. null for Cancel. */
async function pick(kind: "backup-destination" | "restore-archive"): Promise<string | null> {
  const parent = BrowserWindow.getFocusedWindow() ?? windows()[0]
  const filters = [{ name: "Backup", extensions: ["zip"] }]
  if (kind === "backup-destination") {
    const options = { filters, defaultPath: "CopyTrading-Backup.zip" }
    const { canceled, filePath } = await (parent ? dialog.showSaveDialog(parent, options) : dialog.showSaveDialog(options))
    return canceled || !filePath ? null : filePath
  }
  const options = { filters, properties: ["openFile" as const] }
  const { canceled, filePaths } = await (parent ? dialog.showOpenDialog(parent, options) : dialog.showOpenDialog(options))
  return canceled || !filePaths[0] ? null : filePaths[0]
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

async function startServices(): Promise<Api> {
  if (fixtures) {
    const seeded = seedFixturePictures()
    attachments = () => seeded
    return fixtureApi
  }
  try {
    if (!roots) throw new Error(rootsError ?? "The engine's data folder could not be chosen.")
    const paths = new RuntimePaths(roots.owner)
    const generation = () => paths.activeGeneration().dir
    attachments = () => join(generation(), "attachments")
    secrets = new SecretStore(join(app.getPath("userData"), "secrets.bin"), cipher)
    const setup = new SetupFile(generation)
    // The SwiftUI app's keys come across once, so the owner never types them again. macOS may ask to allow it.
    await moveKeychainSecrets({ setup, secrets, installationId: paths.installationIdentity(), read: securityReader }).catch(() => "unreadable")
    const prefs = new Prefs(paths.owner)
    const store = secrets
    const startRuntime = async () => {
      await engine.start(engineTarget(paths, packaged ? process.resourcesPath : null))
      if (engine.state.state !== "running") throw new Error(engine.state.state === "stopped" ? engine.state.reason : "The engine did not start.")
    }
    const request = (operation: string, params?: Record<string, unknown>) => engine.request(operation, params)
    const coordinator = new RestoreCoordinator({ paths, request, secrets: () => ({ revision: store.revision, secrets: store.secrets }), stopRuntime: () => engine.stop(), startRuntime })
    // The engine goes down and comes back during a restore, and a gated candidate may report a failure on the way: nothing is
    // watched meanwhile, as AppModel cancels its status tasks, and watching resumes after (unless the app is quitting).
    const unwatched = async <T>(run: () => Promise<T>): Promise<T> => {
      monitor?.stop()
      try {
        return await run()
      } finally {
        if (!stopped) monitor?.start()
      }
    }
    restore = {
      activate: (input) => unwatched(() => coordinator.activate(input)),
      rollback: (candidateId) => unwatched(() => coordinator.rollback(candidateId)),
      get isRunning() {
        return coordinator.isRunning
      },
    }
    agents = new AgentAccessController(new AgentAccessStore(paths.owner), paths.controlSocket, request)
    const memory = new CopyingMemory(prefs.get("copying_was_on"), (on) => prefs.set("copying_was_on", on))
    monitor = new AlertMonitor({
      request,
      notify,
      fillsOn: () => prefs.get("fill_alerts"),
      guruName: (id) => setup.load()?.configuration.profiles.find((p) => p.guru_id === id)?.display_name ?? null,
      hasSetup: () => setup.load() !== null,
      memory,
    })
    // An engine that dies while the app runs is started again, as ProcessSupervisor does; copying resumes if it was on.
    superviseEngine(engine, {
      restart: startRuntime,
      busy: () => stopped || restore?.isRunning === true,
      wasCopying: () => memory.wasOn,
      onRestarted: (copying) => {
        if (!copying) return
        void resumeSaved().then((why) => why && notify({ id: "copying-not-resumed", thread: "copying-stopped", title: "Copying is paused", body: `The engine restarted after a problem, but copying did not resume: ${why}` }))
      },
      onGaveUp: (reason) => notify({ id: "engine-stopped", thread: "engine", title: "The engine stopped", body: `${redact(reason, store.values())}\n\nCopying is paused. Quit and reopen CopyTrading to try again.` }),
    })
    // Agents and notifications start with the engine, and the engine starts in the background so the window is not kept waiting.
    void startRuntime()
      .then(() => agents?.start())
      .then(() => monitor?.start())
      .catch((error: unknown) => engine.fail(error instanceof Error ? error.message : String(error)))
    services = { engine, setup, secrets, confirm, diagnosticsDir: paths.logs, pick, agents, restore, prefs }
    return createApi(services)
  } catch (error) {
    const reason = error instanceof Error ? error.message : String(error)
    engine.fail(reason)
    return unavailableApi(reason)
  }
}

function registerIpc(): void {
  ipcMain.handle(CHANNELS.read, async (_event, name: unknown, params: unknown) => {
    const result = await api.read(name, params)
    if (result.ok) pictures.learn(result.value)
    return result
  })
  ipcMain.handle(CHANNELS.act, (_event, name: unknown, params: unknown) => api.act(name, params))
  ipcMain.handle(CHANNELS.state, publicState)
  engine.onState(() => windows().forEach((w) => w.webContents.send(CHANNELS.stateChanged, publicState())))
}

function createWindow(): BrowserWindow {
  const window = new BrowserWindow({
    width: 1280,
    height: captureDir ? 1700 : 860,
    show: !captureDir && !smoke,
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
  if (captureDir) captureWindow(window, captureDir, process.env.COPYTRADING_CAPTURE_NAME ?? "window", process.env.COPYTRADING_CAPTURE_CLICK)
  return window
}

/** Copying is on now: the engine says running or degraded. */
async function copyingNow(): Promise<boolean> {
  try {
    const { trading } = (await engine.request("get_trading_status")) as { trading: { state: string } }
    return trading.state === "running" || trading.state === "degraded"
  } catch {
    return false
  }
}

/** Looks for updates on GitHub Releases (app-update.yml in the bundle), as Sparkle did; offers them in a native dialog. */
function startUpdates(marker: ResumeMarker): void {
  autoUpdater.autoDownload = false
  autoUpdater.autoInstallOnAppQuit = false
  // Every release is a developer preview, and GitHub marks those as prereleases.
  autoUpdater.allowPrerelease = true
  const updates = new Updates(
    autoUpdater,
    {
      offer: async (version, note) => {
        const options: Electron.MessageBoxOptions = { type: "question", buttons: ["Later", "Install and Restart"], defaultId: 1, cancelId: 0, noLink: true, message: `CopyTrading ${version} is available.`, detail: note ?? undefined }
        const parent = BrowserWindow.getFocusedWindow() ?? windows()[0]
        const { response } = parent ? await dialog.showMessageBox(parent, options) : await dialog.showMessageBox(options)
        return response === 1
      },
      tell: (message) => void dialog.showMessageBox({ type: "info", message }),
    },
    copyingNow,
    (on) => (on ? marker.set() : void marker.take()),
  )
  Menu.setApplicationMenu(
    Menu.buildFromTemplate([
      { label: app.name, submenu: [{ role: "about" }, { label: "Check for Updates…", click: () => void updates.check(true) }, { type: "separator" }, { role: "hide" }, { role: "hideOthers" }, { role: "unhide" }, { type: "separator" }, { role: "quit" }] },
      { role: "editMenu" },
      { role: "viewMenu" },
      { role: "windowMenu" },
    ]),
  )
  setTimeout(() => void updates.check(), 30_000)
  setInterval(() => void updates.check(), CHECK_EVERY_MS)
}

/** Starts the saved setup with the Start button's checks, every confirmation answered yes (the owner agreed to an update, or copying was on). Resolves with why it did not, or null. */
async function resumeSaved(): Promise<string | null> {
  if (!services) return "There is nothing to resume."
  const setup = services.setup
  const autoConfirmed = createApi({ ...services, confirm: async () => true })
  return resumeCopying(autoConfirmed, () => setup.load(), (ms) => new Promise((done) => setTimeout(done, ms)))
}

/** After an update relaunch, starts copying again once the engine answers (update.resumesCopying). */
function resumeAfterUpdate(marker: ResumeMarker): void {
  const resume = () => {
    if (!marker.take()) return
    void resumeSaved().then((why) => why && console.error(`Copying did not resume after the update: ${why}`))
  }
  if (engine.state.state === "running") return resume()
  const stop = engine.onState((state) => {
    if (state.state === "starting") return
    stop()
    if (state.state === "running") resume()
  })
}

/** COPYTRADING_SMOKE: the page loaded, its bridge is there, and the engine answered; says so and quits. */
function runSmoke(window: BrowserWindow): void {
  const finish = (code: number, line: string) => {
    ;(code ? console.error : console.log)(line)
    process.exitCode = code
    app.quit()
  }
  const loaded = new Promise<void>((done) => window.webContents.once("did-finish-load", () => done()))
  const answered = new Promise<string | null>((done) => {
    const check = (state: EngineState) => (state.state === "running" ? done(null) : state.state === "stopped" ? done(state.reason) : undefined)
    check(engine.state)
    engine.onState(check)
  })
  void Promise.all([loaded, answered]).then(async ([, reason]) => {
    if (reason) return finish(1, `smoke failed: the engine stopped: ${reason}`)
    const bridge = await window.webContents.executeJavaScript("typeof window.copytrading?.read?.getStatus")
    if (bridge !== "function") return finish(1, "smoke failed: the page has no engine bridge")
    finish(0, `smoke ok: version ${app.getVersion()}, engine running on ${roots?.owner}`)
  })
}

app.whenReady().then(async () => {
  session.defaultSession.setPermissionRequestHandler((_wc, _permission, deny) => deny(false))
  api = await startServices()
  protocol.handle(PICTURE_SCHEME, (request) => (attachments ? pictures.respond(attachments(), request.url) : new Response(null, { status: 404 })))
  registerIpc()
  const window = createWindow()
  if (smoke) return runSmoke(window)
  if (!packaged) return
  const marker = new ResumeMarker(join(app.getPath("userData"), "resume-copying"))
  resumeAfterUpdate(marker)
  // A throwaway folder is a test run: it never offers an update.
  if (!stateRoot) startUpdates(marker)
})
// Closing the window leaves copying, the agent socket and the notifications running, as the SwiftUI app does; quitting stops them.
app.on("window-all-closed", () => {
  if (captureDir) app.quit()
})
app.on("activate", () => {
  if (api && !windows().length) createWindow()
})

const RESTORE_WAIT_MS = 120_000

/** Waits for a restore that is under way, since the engine stops and restarts inside it. */
async function restoreSettled(): Promise<void> {
  const deadline = Date.now() + RESTORE_WAIT_MS
  while (restore?.isRunning && Date.now() < deadline) await new Promise((done) => setTimeout(done, 100))
}

// Quitting stops the agent socket first (nothing new reaches the engine), then waits for the engine to exit as
// ProcessSupervisor.stop does: it may cancel working orders, so the app does not go until it has.
let stopped = false
app.on("before-quit", (event) => {
  if (stopped) return
  event.preventDefault()
  stopped = true
  monitor?.stop()
  void (async () => {
    await agents?.stop()
    await restoreSettled()
    await engine.stop()
    roots?.cleanup()
  })().finally(() => app.quit())
})
