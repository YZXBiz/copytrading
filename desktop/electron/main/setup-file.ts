import { randomUUID } from "node:crypto"
import { closeSync, fsyncSync, lstatSync, mkdirSync, openSync, readFileSync, renameSync, rmSync, writeSync } from "node:fs"
import { join } from "node:path"
import { isDeepStrictEqual } from "node:util"
import type { SetupView, TradingConfiguration } from "../../shared/contract"

// The file the SwiftUI app writes (TradingConfigurationStore.swift), read and written unchanged:
// {version: 1, configuration, revision, secretRevision, pendingActivation?}. The envelope's keys are
// camelCase and `configuration`'s are the engine's snake_case. `configuration` passes through as parsed
// data, so a saved `repeat_window_minutes: null` or an absent `base_url` survives a save untouched.

export const SETUP_FILE = "trading-configuration.json"
const MAX_BYTES = 1_048_576
const CONFIGURATION_VERSION = 10

interface Revision {
  configuration: TradingConfiguration
  revision: string
  secretRevision: string
}

interface Envelope extends Revision {
  version: 1
  pendingActivation?: { activationID: string; candidateRevision: string; previous?: Revision }
}

export class SetupFileError extends Error {}

const isRevision = (value: unknown): value is string => typeof value === "string" && /^[0-9a-f]{64}$/.test(value)

export class SetupFile {
  readonly path: string
  /**
   * The setup the engine last confirmed, held from the first `save` after it until a start finalizes or rolls back:
   * `undefined` when the file is what the owner last confirmed, `null` when there was no file. Saving and starting are
   * separate calls, so this is what a start that does not take, or a Cancel, puts back.
   */
  private confirmed: Revision | null | undefined

  constructor(private readonly dataDir: string) {
    this.path = join(dataDir, SETUP_FILE)
  }

  private read(): Envelope | null {
    let stat
    try {
      stat = lstatSync(this.path)
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code === "ENOENT") return null
      throw new SetupFileError("The saved setup could not be read.")
    }
    if (!stat.isFile() || stat.size > MAX_BYTES) throw new SetupFileError("The saved setup is not a valid file.")
    let saved: Envelope
    try {
      saved = JSON.parse(readFileSync(this.path, "utf8")) as Envelope
    } catch {
      throw new SetupFileError("The saved setup is not a valid file.")
    }
    const version = saved?.configuration?.version
    // An earlier version is upgraded by a later step, never read in its old shape here.
    if (typeof version === "number" && version < CONFIGURATION_VERSION) {
      throw new SetupFileError(`The saved setup is from an earlier version (${version}) and has not been upgraded.`)
    }
    const pending = saved.pendingActivation
    if (
      saved.version !== 1 ||
      version !== CONFIGURATION_VERSION ||
      !isRevision(saved.revision) ||
      typeof saved.secretRevision !== "string" ||
      (pending && pending.candidateRevision !== saved.revision)
    ) {
      throw new SetupFileError("The saved setup is not a valid file.")
    }
    return saved
  }

  /** The setup copying uses: with a start still unconfirmed, the last one the engine confirmed. */
  load(): (SetupView & { secretRevision: string }) | null {
    const saved = this.read()
    if (!saved) return null
    const pending = saved.pendingActivation
    const stable = pending ? pending.previous : saved
    if (!stable) return null
    return {
      configuration: stable.configuration,
      revision: stable.revision,
      // The keys in the store are the candidate's while a start is pending: it is the one that was saved with them.
      secretRevision: saved.secretRevision,
      keys_present: false,
      pending_activation: pending ? { activation_id: pending.activationID, candidate_revision: pending.candidateRevision } : null,
    }
  }

  /** The setup as last saved, the candidate included: what a start starts. Null when there is no file. */
  current(): Revision | null {
    const saved = this.read()
    return saved && { configuration: saved.configuration, revision: saved.revision, secretRevision: saved.secretRevision }
  }

  /** Journals a start before it is sent (`stageValidatedActivation`): the candidate, and the setup to put back if it does not take. */
  stage(activationId: string): void {
    const saved = this.read()
    if (!saved) throw new SetupFileError("There is no saved setup yet.")
    if (saved.pendingActivation) throw new SetupFileError("A start is waiting for the engine to confirm it.")
    if (!/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/.test(activationId)) throw new SetupFileError("The start has no valid id.")
    const { configuration, revision, secretRevision } = saved
    const previous = this.confirmed === undefined ? { configuration, revision, secretRevision } : this.confirmed
    this.write({ ...saved, pendingActivation: { activationID: activationId, candidateRevision: revision, ...(previous ? { previous } : {}) } })
  }

  /** The engine committed this start: the candidate is the saved setup. */
  finalize(activationId: string): void {
    const saved = this.read()
    if (saved?.pendingActivation?.activationID !== activationId) throw new SetupFileError("The start in the saved setup is not this one.")
    const { pendingActivation: _pending, ...settled } = saved
    this.write(settled)
    this.confirmed = undefined
  }

  /** The start did not take: the setup before it is saved again. Returns that setup's key revision, null when there was none. */
  rollback(activationId: string): string | null {
    const saved = this.read()
    if (saved?.pendingActivation?.activationID !== activationId) throw new SetupFileError("The start in the saved setup is not this one.")
    return this.restore(saved.pendingActivation.previous)
  }

  /** A save the owner then declined to start: the setup before it is saved again. Returns its key revision, null when there was none. */
  discardUnstarted(): string | null | undefined {
    if (this.confirmed === undefined || this.read()?.pendingActivation) return undefined
    return this.restore(this.confirmed)
  }

  private restore(previous: Revision | undefined | null): string | null {
    if (previous) this.write({ version: 1, ...previous })
    else rmSync(this.path, { force: true })
    this.confirmed = undefined
    return previous?.secretRevision ?? null
  }

  /** The start the engine has not confirmed, if any. */
  pending(): { activation_id: string; candidate_revision: string } | null {
    const pending = this.read()?.pendingActivation
    return pending ? { activation_id: pending.activationID, candidate_revision: pending.candidateRevision } : null
  }

  /** Saves a validated setup under the revision the engine reported for it, with a new key revision. */
  save(configuration: TradingConfiguration, revision: string): string {
    if (configuration.version !== CONFIGURATION_VERSION || !isRevision(revision)) {
      throw new SetupFileError("The setup is invalid.")
    }
    const existing = this.read()
    if (existing?.pendingActivation) throw new SetupFileError("A start is waiting for the engine to confirm it.")
    if (this.confirmed === undefined) {
      this.confirmed = existing && { configuration: existing.configuration, revision: existing.revision, secretRevision: existing.secretRevision }
    }
    // Swift's UUID().uuidString is uppercase; the same spelling keeps the file readable by both apps.
    const secretRevision = randomUUID().toUpperCase()
    this.write({ version: 1, configuration, revision, secretRevision })
    return secretRevision
  }

  /** Saves changed account limits only; the keys stay as they are. */
  saveLimits(configuration: TradingConfiguration, revision: string): void {
    const saved = this.read()
    if (!saved) throw new SetupFileError("There is no saved setup yet.")
    if (saved.pendingActivation) throw new SetupFileError("A start is waiting for the engine to confirm it.")
    if (!isRevision(revision)) throw new SetupFileError("The setup is invalid.")
    this.assertLimitsOnly(configuration)
    this.write({ ...saved, configuration, revision })
  }

  /** Throws unless `configuration` differs from the saved setup only in account limits. */
  assertLimitsOnly(configuration: TradingConfiguration): void {
    const saved = this.read()
    if (!saved) throw new SetupFileError("There is no saved setup yet.")
    if (saved.pendingActivation) throw new SetupFileError("A start is waiting for the engine to confirm it.")
    if (configuration.version !== CONFIGURATION_VERSION) throw new SetupFileError("The setup is invalid.")
    if (!isDeepStrictEqual(withPoliciesOf(configuration, saved.configuration), saved.configuration)) {
      throw new SetupFileError("Only account limits can change while copying.")
    }
  }

  /** Same steps as AtomicTradingConfigurationWriter: temp file, fsync, rename, fsync the folder. */
  private write(envelope: Envelope): void {
    const data = JSON.stringify(envelope)
    if (Buffer.byteLength(data) > MAX_BYTES) throw new SetupFileError("The setup is too large.")
    mkdirSync(this.dataDir, { recursive: true, mode: 0o700 })
    const temporary = join(this.dataDir, `.trading-${randomUUID()}.tmp`)
    const dir = openSync(this.dataDir, "r")
    try {
      const file = openSync(temporary, "wx", 0o600)
      try {
        writeSync(file, data)
        fsyncSync(file)
      } finally {
        closeSync(file)
      }
      renameSync(temporary, this.path)
      fsyncSync(dir)
    } catch (error) {
      rmSync(temporary, { force: true })
      throw new SetupFileError(`The setup could not be saved: ${error instanceof Error ? error.message : String(error)}`)
    } finally {
      closeSync(dir)
    }
  }
}

/** `next` with every account's policy taken from `saved`, to see whether only limits differ. */
function withPoliciesOf(next: TradingConfiguration, saved: TradingConfiguration): TradingConfiguration {
  return {
    ...next,
    accounts: next.accounts.map((account) => {
      const policy = saved.accounts.find((a) => a.id === account.id)?.policy
      return policy ? { ...account, policy } : account
    }),
  }
}
