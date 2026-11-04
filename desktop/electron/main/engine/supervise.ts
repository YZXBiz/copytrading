import type { EngineProcess } from "./launch"

// ProcessSupervisor.swift: maximumRestarts 3, restartDelay 1 s. The count is for the life of the app, as there.
const MAX_RESTARTS = 3
const RESTART_DELAY_MS = 1_000

export interface SuperviseOptions {
  /** Starts the engine again; throws if it does not come up. */
  restart: () => Promise<void>
  /** Something else owns the engine for now (a restore stops and starts it itself). */
  busy: () => boolean
  /** Copying was on when the engine died: read at the crash, before anything can change it. */
  wasCopying: () => boolean
  onRestarted: (wasCopying: boolean) => void
  /** Every restart failed: the engine stays stopped, with this reason. */
  onGaveUp: (reason: string) => void
  maxRestarts?: number
  delayMs?: number
}

/** Starts a crashed engine again, up to the limit, one second apart. Returns the way to stop watching. */
export function superviseEngine(engine: EngineProcess, options: SuperviseOptions): () => void {
  const { maxRestarts = MAX_RESTARTS, delayMs = RESTART_DELAY_MS } = options
  let used = 0
  let recovering = false
  return engine.onCrash(async (crash) => {
    // An attempt's own failed start is already being counted; a restore is its own owner.
    if (recovering || options.busy()) return
    recovering = true
    const copying = options.wasCopying()
    let reason = crash
    try {
      while (used < maxRestarts) {
        used += 1
        await new Promise((done) => setTimeout(done, delayMs))
        // The app began quitting, or a restore took the engine, while this waited.
        if (options.busy()) return
        try {
          await options.restart()
          return options.onRestarted(copying)
        } catch (error) {
          reason = error instanceof Error ? error.message : String(error)
        }
      }
      options.onGaveUp(reason)
    } finally {
      recovering = false
    }
  })
}
