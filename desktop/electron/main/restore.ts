import type { PendingRestoreCandidate, RestorePreflight, RestorePreflightAccount, RestoreResult, TradingEnvironment } from "../../shared/contract"
import type { Drain } from "./engine/launch"
import type { RuntimePaths } from "./engine/paths"
import type { Secrets } from "./secrets"

/** RestoreActivationError: each message is what the SwiftUI app tells the owner for the same failure. */
const MESSAGES = {
  candidateUnavailable: "CopyTrading couldn't find the restore it was preparing. Open the backup again.",
  candidateConflict: "Another restore is half-finished. Resume it or roll it back first.",
  candidateInvalid: "The restored data didn't pass its checks, so nothing was restored.",
  candidateStartFailed: "CopyTrading couldn't start on the restored data, so nothing was restored.",
  credentialsUnavailable: "The account keys this backup needs aren't on this Mac. Enter them again, then restore.",
  previousGenerationChanged: "Your data changed while restoring, so nothing was restored. Try again.",
  previousEngineDrainUnconfirmed: "Trading didn't stop cleanly, so nothing was restored. Try again in a moment.",
  completionUnconfirmed: "CopyTrading couldn't confirm the restore finished. Quit and reopen it to check.",
  rollbackIncomplete: "The restore stopped partway and couldn't be undone by itself. Quit and reopen CopyTrading to resume it or roll it back.",
  busy: "A restore is already running.",
} as const

export class RestoreError extends Error {
  constructor(
    readonly code: keyof typeof MESSAGES | "preflightBlocked",
    readonly blockers: string[] = [],
  ) {
    super(code === "preflightBlocked" ? "The broker's records don't match the backup, so nothing was restored." : MESSAGES[code])
  }
}

export interface RestoreDeps {
  paths: RuntimePaths
  /** The engine as it is now; after `startRuntime` it is the one on the new generation. */
  request: (operation: string, params?: Record<string, unknown>) => Promise<unknown>
  /** What the key store holds: restore needs keys for the candidate's accounts under the revision its setup names. */
  secrets: () => { revision: string | null; secrets: Secrets }
  stopRuntime: () => Promise<Drain>
  /** Starts the engine on whichever generation is active; throws if it does not come up. */
  startRuntime: () => Promise<void>
}

type Body = Record<string, unknown>

/** The accounts a candidate holds, with each one's environment from the candidate and its keys from the key store. */
export function preflightAccounts(candidate: PendingRestoreCandidate, installationId: string, held: { revision: string | null; secrets: Secrets }): RestorePreflightAccount[] {
  if (!candidate.candidate_valid || candidate.installation_id !== installationId) throw new RestoreError("candidateInvalid")
  const environments = new Map<string, TradingEnvironment>()
  for (const entry of candidate.environment_ids) {
    const split = entry.indexOf(":")
    const environment = entry.slice(0, split)
    if (split < 0 || (environment !== "paper" && environment !== "live")) throw new RestoreError("candidateInvalid")
    environments.set(entry.slice(split + 1), environment)
  }
  const ids = new Set(candidate.account_ids)
  if (environments.size !== candidate.environment_ids.length || environments.size !== ids.size || [...ids].some((id) => !environments.has(id))) {
    throw new RestoreError("candidateInvalid")
  }
  if (ids.size === 0) {
    if (candidate.credential_references.length) throw new RestoreError("credentialsUnavailable")
    return []
  }
  // Keys are tied to one setup revision; the backup's setup must name the one this store holds.
  const [reference, ...others] = candidate.credential_references
  if (!reference || others.length || held.revision?.toLowerCase() !== reference.toLowerCase()) throw new RestoreError("credentialsUnavailable")
  return [...ids].map((account_id) => {
    const keys = held.secrets.brokers.find((b) => b.account_id === account_id)
    if (!keys?.key || !keys.secret) throw new RestoreError("credentialsUnavailable")
    return { account_id, environment: environments.get(account_id)!, key: keys.key, secret: keys.secret }
  })
}

/** Restore and rollback, one at a time. The engine stops and restarts under it, so nothing else may run a transition meanwhile. */
export class RestoreCoordinator {
  private running = false

  constructor(private readonly deps: RestoreDeps) {}

  get isRunning(): boolean {
    return this.running
  }

  /** Restores a previewed backup, or finishes the candidate a half-done restore left; a failure puts the data back. */
  async activate(input: { stagingId: string; matchesInstallation: boolean } | { candidateId: string }): Promise<RestoreResult> {
    return this.exclusively(async () => {
      const { paths } = this.deps
      const expectedPrevious = "stagingId" in input ? paths.activeGeneration().id : null
      const pending = await this.prepare(input, expectedPrevious)
      try {
        await this.operate(pending, expectedPrevious)
        return { status: "restored" } as const
      } catch (error) {
        let gateCleared = false
        try {
          gateCleared = !paths.restoreGateIsPresent()
          await (gateCleared ? this.rollbackAfterGateClear(pending) : this.rollbackGated(pending))
        } catch {
          throw new RestoreError("rollbackIncomplete")
        }
        if (error instanceof RestoreError && error.code === "preflightBlocked") return { status: "blocked", blockers: error.blockers }
        throw error
      }
    })
  }

  /** Undoes a half-finished restore. If the engine is down it is started first, to find the candidate. */
  async rollback(candidateId: string): Promise<void> {
    return this.exclusively(async () => {
      let pending: PendingRestoreCandidate | null
      try {
        pending = await this.status()
      } catch {
        // No engine to ask (a restore that stopped partway left it down): start one on the active generation, gated if the gate holds.
        await this.deps.startRuntime()
        pending = await this.status()
      }
      if (!pending || pending.candidate_id !== candidateId) throw new RestoreError("candidateUnavailable")
      try {
        await this.rollbackGated(pending)
      } catch {
        throw new RestoreError("rollbackIncomplete")
      }
    })
  }

  private async exclusively<T>(run: () => Promise<T>): Promise<T> {
    if (this.running) throw new RestoreError("busy")
    this.running = true
    try {
      return await run()
    } finally {
      this.running = false
    }
  }

  private async status(): Promise<PendingRestoreCandidate | null> {
    return ((await this.deps.request("restore_candidate_status")) as Body).candidate as PendingRestoreCandidate | null
  }

  /** The candidate to activate: the one already waiting (only if the page named it), or one prepared from the staged backup. */
  private async prepare(input: { stagingId: string; matchesInstallation: boolean } | { candidateId: string }, expectedPrevious: string | null): Promise<PendingRestoreCandidate> {
    const existing = await this.status()
    if (existing) {
      if (!("candidateId" in input) || input.candidateId !== existing.candidate_id) throw new RestoreError("candidateConflict")
      return existing
    }
    if (!("stagingId" in input) || !input.matchesInstallation || !expectedPrevious) throw new RestoreError("candidateUnavailable")
    let requested: string | null = null
    try {
      requested = ((await this.deps.request("prepare_restore_candidate", { staging_id: input.stagingId })) as Body).candidate_id as string
      const pending = await this.status()
      if (!pending || pending.candidate_id !== requested || pending.previous_generation !== expectedPrevious) throw new RestoreError("candidateUnavailable")
      return pending
    } catch (error) {
      // Preparing may have saved its marker before the reply was lost.
      const recovered = await this.status().catch(() => null)
      if (recovered && (requested === null || recovered.candidate_id === requested) && recovered.previous_generation === expectedPrevious) return recovered
      throw error
    }
  }

  private async operate(pending: PendingRestoreCandidate, expectedPrevious: string | null): Promise<void> {
    const { paths, request, stopRuntime, startRuntime } = this.deps
    if (pending.installation_id !== paths.installationIdentity() || (expectedPrevious !== null && expectedPrevious !== pending.previous_generation)) {
      throw new RestoreError("previousGenerationChanged")
    }
    // Nothing may be switched until the old engine has said it finished its work.
    const drain = await stopRuntime()
    if (drain === "unconfirmed") throw new RestoreError("previousEngineDrainUnconfirmed")
    const selected = paths.activeGeneration().id
    if (selected === pending.previous_generation) paths.switchActiveGeneration(pending.candidate_id, pending.previous_generation)
    else if (selected !== pending.candidate_id) throw new RestoreError("previousGenerationChanged")
    if (!pending.candidate_valid) throw new RestoreError("candidateInvalid")

    await startRuntime().catch(() => {
      throw new RestoreError("candidateStartFailed")
    })
    const running = await this.status()
    if (!running || running.candidate_id !== pending.candidate_id || running.active_generation !== pending.candidate_id || !running.candidate_valid) {
      throw new RestoreError("candidateStartFailed")
    }
    const accounts = preflightAccounts(running, paths.installationIdentity(), this.deps.secrets())
    const preflight = (await request("restore_preflight", { candidate_id: pending.candidate_id, accounts })) as RestorePreflight
    if (preflight.candidate_id !== pending.candidate_id) throw new RestoreError("candidateInvalid")
    if (!preflight.eligible || !preflight.completion_token) throw new RestoreError("preflightBlocked", preflight.blockers)

    try {
      await request("complete_restore_candidate", { candidate_id: pending.candidate_id, completion_token: preflight.completion_token })
    } catch {
      // Completing stops the gated engine. Look at what is on disk, then start it again to tell a lost reply from a live gate.
      await stopRuntime()
      if (!paths.restoreGateIsPresent()) {
        await startRuntime()
        if ((await this.status()) !== null) throw new RestoreError("completionUnconfirmed")
        return
      }
      await startRuntime()
      throw new RestoreError("completionUnconfirmed")
    }
    await stopRuntime()
    await startRuntime().catch(() => {
      throw new RestoreError("candidateStartFailed")
    })
    if ((await this.status()) !== null) throw new RestoreError("candidateStartFailed")
  }

  /** Back to the previous generation after the gate was cleared: nothing is left to abort. */
  private async rollbackAfterGateClear(pending: PendingRestoreCandidate): Promise<void> {
    await this.deps.stopRuntime()
    this.switchBack(pending)
    await this.deps.startRuntime()
    if ((await this.status()) !== null) throw new RestoreError("rollbackIncomplete")
  }

  /** Back to the previous generation while the gate holds: start there gated, abort the candidate, then start for real. */
  private async rollbackGated(pending: PendingRestoreCandidate): Promise<void> {
    const { paths, stopRuntime, startRuntime, request } = this.deps
    await stopRuntime()
    this.switchBack(pending)
    await startRuntime()
    const durable = await this.status()
    if (!durable || durable.candidate_id !== pending.candidate_id || durable.active_generation !== pending.previous_generation) {
      throw new RestoreError("candidateUnavailable")
    }
    try {
      await request("abort_restore_candidate", { candidate_id: pending.candidate_id })
    } catch {
      // The engine clears the candidate before it replies; a lost reply is an abort only if the gate and the pointer say so.
      if (paths.restoreGateIsPresent() || paths.activeGeneration().id !== pending.previous_generation) throw new RestoreError("rollbackIncomplete")
    }
    await stopRuntime()
    await startRuntime()
    if ((await this.status()) !== null) throw new RestoreError("rollbackIncomplete")
  }

  private switchBack(pending: PendingRestoreCandidate): void {
    const { paths } = this.deps
    const selected = paths.activeGeneration().id
    if (selected === pending.candidate_id) paths.switchActiveGeneration(pending.previous_generation, pending.candidate_id)
    else if (selected !== pending.previous_generation) throw new RestoreError("previousGenerationChanged")
  }
}
