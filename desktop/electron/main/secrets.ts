import { existsSync, readFileSync, renameSync, writeFileSync } from "node:fs"
import type { SecretStatus, SecretUpdate } from "../../shared/contract"

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

interface Saved {
  /** The `secretRevision` of the setup file these keys belong to. */
  revision: string | null
  secrets: Secrets
}

const EMPTY: Saved = { revision: null, secrets: { discord_token: "", provider_api_key: "", brokers: [] } }

/** The owner's keys, encrypted at rest. Values leave this class only inside engine requests. */
export class SecretStore {
  private saved: Saved

  constructor(
    private readonly path: string,
    private readonly cipher: Cipher,
  ) {
    this.saved = existsSync(path) ? (JSON.parse(cipher.decrypt(readFileSync(path))) as Saved) : EMPTY
  }

  get secrets(): Secrets {
    return this.saved.secrets
  }

  get revision(): string | null {
    return this.saved.revision
  }

  /** Every stored value, for the check that none reaches the renderer. */
  values(): string[] {
    const { secrets } = this.saved
    return [
      secrets.discord_token,
      secrets.provider_api_key,
      secrets.notification_token ?? "",
      ...secrets.brokers.flatMap((b) => [b.key, b.secret]),
    ].filter(Boolean)
  }

  status(): SecretStatus {
    const { secrets } = this.saved
    return {
      discord_token: Boolean(secrets.discord_token),
      provider_api_key: Boolean(secrets.provider_api_key),
      notification_token: Boolean(secrets.notification_token),
      brokers: Object.fromEntries(secrets.brokers.map((b) => [b.account_id, Boolean(b.key && b.secret)])),
    }
  }

  merge(update: SecretUpdate): void {
    const next = { ...this.saved.secrets, brokers: [...this.saved.secrets.brokers] }
    if (update.discord_token !== undefined) next.discord_token = update.discord_token
    if (update.provider_api_key !== undefined) next.provider_api_key = update.provider_api_key
    if (update.notification_token !== undefined) next.notification_token = update.notification_token
    for (const broker of update.brokers ?? []) {
      next.brokers = [...next.brokers.filter((b) => b.account_id !== broker.account_id), broker]
    }
    this.write({ ...this.saved, secrets: next })
  }

  forgetBroker(accountId: string): void {
    const brokers = this.saved.secrets.brokers.filter((b) => b.account_id !== accountId)
    this.write({ ...this.saved, secrets: { ...this.saved.secrets, brokers } })
  }

  /** Ties the keys to the setup file that was just saved. */
  setRevision(revision: string | null): void {
    this.write({ ...this.saved, revision })
  }

  private write(next: Saved): void {
    // Write beside, then rename, so a crash never leaves half a file where the keys were.
    const temporary = `${this.path}.tmp`
    writeFileSync(temporary, this.cipher.encrypt(JSON.stringify(next)), { mode: 0o600 })
    renameSync(temporary, this.path)
    this.saved = next
  }
}
