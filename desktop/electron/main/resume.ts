import { randomUUID } from "node:crypto"
import { existsSync, rmSync, writeFileSync } from "node:fs"
import type { Result, TradingConfiguration } from "../../shared/contract"

/** A file beside the key store that says copying was on when an update relaunched the app (`update.resumesCopying`). */
export class ResumeMarker {
  constructor(private readonly path: string) {}

  set(): void {
    writeFileSync(this.path, "")
  }

  /** True once if the marker was there, and removes it, so a failed resume never repeats on the next launch. */
  take(): boolean {
    const present = existsSync(this.path)
    rmSync(this.path, { force: true })
    return present
  }
}

type Api = { read: (name: string, params?: unknown) => Promise<Result<unknown>>; act: (name: string, params?: unknown) => Promise<Result<unknown>> }

/** AppModel.canStartCopyingOnLaunch: only a paper-only setup resumes by itself; a live account waits for the owner. */
export const resumable = (configuration: TradingConfiguration) => configuration.accounts.every((a) => a.environment === "paper")

/** Seconds to wait before each try: a check that fails right after launch is often the network waking up. */
export const RETRY_DELAYS_MS = [0, 10_000, 30_000, 60_000]

/**
 * Starts the saved setup after an update relaunch, with the same checks as the Start button: validate,
 * then start. `api` is an api whose confirmations are answered yes, because the owner agreed in the
 * update dialog. Resolves with why it did not start, or null once copying runs.
 */
export async function resumeCopying(api: Api, load: () => { configuration: TradingConfiguration } | null, wait: (ms: number) => Promise<void>, delays = RETRY_DELAYS_MS): Promise<string | null> {
  let reason = "Copying did not start."
  for (const delay of delays) {
    await wait(delay)
    const saved = load()
    if (!saved) return "There is no saved setup to resume."
    if (!resumable(saved.configuration)) return "The setup has a live account, so copying waits for you to start it."
    const status = await api.read("getStatus")
    if (!status.ok) {
      reason = status.error
      continue
    }
    if ((status.value as { state: string }).state !== "paused") return null
    const checked = await api.act("validateTrading", { configuration: saved.configuration })
    if (!checked.ok) {
      reason = checked.error
      continue
    }
    const { activation_token, report } = checked.value as { activation_token: string | null; report: { activatable: boolean } }
    if (!report.activatable || !activation_token) {
      reason = "The setup check did not pass. Connections shows what to fix."
      continue
    }
    const started = await api.act("startTrading", { activation_id: randomUUID(), validation_token: activation_token })
    if (started.ok) return null
    reason = started.error
  }
  return reason
}
