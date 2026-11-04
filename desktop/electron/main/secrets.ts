import { existsSync, readFileSync, renameSync, writeFileSync } from "node:fs"
import type { EngineState, SecretStatus, SecretUpdate } from "../../shared/contract"

/** The engine's TradingSecrets, as `validate_trading` and `start_trading` take them. */
export interface Secrets {
  discord_token: string
  provider_api_key: string
  brokers: { account_id: string; key: string; secret: string }[]
  notification_token?: string
}

/** Production passes Electron's safeStorage; tests pass a reversible stand-in. */
export interface Cipher {
  encrypt: (text: string) => Buffer
  decrypt: (data: Buffer) => string
}

// A stored key shorter than this could match ordinary words, so it is not looked for in text.
const MIN_CHECKED_LENGTH = 6

/** `text` with every stored key (as is, and as JSON would escape it) replaced. The check on everything sent to the renderer. */
export function redact(text: string, values: string[]): string {
  return values
    .filter((v) => v.length >= MIN_CHECKED_LENGTH)
    .flatMap((v) => [v, JSON.stringify(v).slice(1, -1)])
    .reduce((out, v) => out.split(v).join("•••"), text)
}

export const redactState = (state: EngineState, values: string[]): EngineState =>
  state.state === "stopped" ? { ...state, reason: redact(state.reason, values) } : state

interface Saved {
  /** The `secretRevision` of the setup file these keys belong to. */
  revision: string | null
  /** The provider `secrets.provider_api_key` was typed for; null for a key saved before this was recorded. */
  provider?: string | null
  secrets: Secrets
}

/** What is on disk: the keys, and while a start is pending the keys before it, which a rollback puts back. */
interface OnDisk extends Saved {
  previous?: Saved
}

const empty = (): Saved => ({ revision: null, secrets: { discord_token: "", provider_api_key: "", brokers: [] } })
const copy = (saved: Saved): Saved => structuredClone(saved)

/**
 * The owner's keys, encrypted at rest. Values leave this class only inside engine requests.
 *
 * What the engine is sent (`secrets`, `revision`, `status`) is the working set. Keys the owner types go into the working
 * set only, in memory: a failed check, a cancelled dialog or a start that does not take leaves the file exactly as it was.
 * `stage` writes the working set to disk, with the keys before it, when a start is journaled; `settle` drops the old
 * keys once the engine commits it; `rollback` puts them back. A crash between the two leaves both on disk.
 */
export class SecretStore {
  private disk: OnDisk
  private working: Saved

  constructor(
    private readonly path: string,
    private readonly cipher: Cipher,
  ) {
    this.disk = existsSync(path) ? (JSON.parse(cipher.decrypt(readFileSync(path))) as OnDisk) : empty()
    this.working = copy(this.disk)
    delete (this.working as OnDisk).previous
  }

  get secrets(): Secrets {
    return this.working.secrets
  }

  get revision(): string | null {
    return this.working.revision
  }

  /** Every value held, working or on disk, for the check that none reaches the renderer. */
  values(): string[] {
    return [this.working, this.disk, this.disk.previous]
      .flatMap((saved) => (saved ? [saved.secrets] : []))
      .flatMap((secrets) => [
        secrets.discord_token,
        secrets.provider_api_key,
        secrets.notification_token ?? "",
        ...secrets.brokers.flatMap((b) => [b.key, b.secret]),
      ])
      .filter(Boolean)
  }

  status(): SecretStatus {
    const { secrets } = this.working
    return {
      discord_token: Boolean(secrets.discord_token),
      provider_api_key: Boolean(secrets.provider_api_key),
      notification_token: Boolean(secrets.notification_token),
      brokers: Object.fromEntries(secrets.brokers.map((b) => [b.account_id, Boolean(b.key && b.secret)])),
    }
  }

  /** The model key for `provider`, or "" when the saved key was typed for another one: one service's key never goes to another's. `setupProvider` covers a key saved before its provider was recorded. */
  providerKey(provider: string, setupProvider: string | undefined): string {
    return (this.working.provider ?? setupProvider) === provider ? this.working.secrets.provider_api_key : ""
  }

  /** Holds keys the owner typed, in memory only, until a start is staged. */
  merge(update: SecretUpdate): void {
    const next = { ...this.working.secrets, brokers: [...this.working.secrets.brokers] }
    let provider = this.working.provider
    if (update.discord_token !== undefined) next.discord_token = update.discord_token
    if (update.provider_api_key !== undefined) {
      next.provider_api_key = update.provider_api_key
      provider = update.provider_name ?? null
    }
    if (update.notification_token !== undefined) next.notification_token = update.notification_token
    for (const broker of update.brokers ?? []) {
      next.brokers = [...next.brokers.filter((b) => b.account_id !== broker.account_id), broker]
    }
    this.working = { ...this.working, provider, secrets: next }
  }

  /** Forgets an account's keys for good: in memory and on disk. */
  forgetBroker(accountId: string): void {
    const without = (saved: Saved): Saved => ({ ...saved, secrets: { ...saved.secrets, brokers: saved.secrets.brokers.filter((b) => b.account_id !== accountId) } })
    this.working = without(this.working)
    this.write({ ...without(this.disk), ...(this.disk.previous ? { previous: without(this.disk.previous) } : {}) })
  }

  /** Ties the keys to the setup file that was just saved. In memory until the start is staged. */
  setRevision(revision: string | null): void {
    this.working = { ...this.working, revision }
  }

  /** A start is being journaled: the working keys go to disk, with the keys that were there kept for a rollback. */
  stage(): void {
    const { previous: _pending, ...before } = this.disk
    this.write({ ...copy(this.working), previous: before })
  }

  /** The engine committed the start: the old keys can go. */
  settle(): void {
    if (this.disk.previous) this.write(copy(this.working))
  }

  /** The start did not take: the keys before it are on disk and in use again. */
  rollback(): void {
    const previous = this.disk.previous ?? empty()
    this.working = copy(previous)
    this.write(copy(previous))
  }

  /** Drops keys that were typed and never staged: the disk is what the owner had. */
  discard(): void {
    const { previous: _pending, ...saved } = this.disk
    this.working = copy(saved)
  }

  private write(next: OnDisk): void {
    // Write beside, then rename, so a crash never leaves half a file where the keys were.
    const temporary = `${this.path}.tmp`
    writeFileSync(temporary, this.cipher.encrypt(JSON.stringify(next)), { mode: 0o600 })
    renameSync(temporary, this.path)
    this.disk = next
  }
}
