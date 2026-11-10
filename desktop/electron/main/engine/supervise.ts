import type { EngineProcess } from "./launch"

// At most 3 restarts in any 10 minutes, 1 s apart: a crash loop stops and says so, but a crash days after the last one
// is still restarted (a count for the life of the app left copying off for good after a third crash in a week).
const MAX_RESTARTS = 3
const RESTART_DELAY_MS = 1_000
const RESTART_WINDOW_MS = 10 * 60_000

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
  windowMs?: number
  now?: () => number
}

/** Starts a crashed engine again, up to the limit in the window, one second apart. Returns the way to stop watching. */
export function superviseEngine(engine: EngineProcess, options: SuperviseOptions): () => void {
  const { maxRestarts = MAX_RESTARTS, delayMs = RESTART_DELAY_MS, windowMs = RESTART_WINDOW_MS, now = Date.now } = options
  let attempts: number[] = []
  let recovering = false
  return engine.onCrash(async (crash) => {
    // An attempt's own failed start is already being counted; a restore is its own owner.
    if (recovering || options.busy()) return
    recovering = true
    const copying = options.wasCopying()
    let reason = crash
    try {
      for (;;) {
        attempts = attempts.filter((at) => now() - at < windowMs)
        if (attempts.length >= maxRestarts) break
        attempts.push(now())
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
