import type { SecretStore } from "./secrets"
import type { SetupFile } from "./setup-file"

/**
 * Hands the engine each saved account's keys so it can read the account while copying is paused or has not started
 * (AppModel.attachAccountReaders): the balance, its history, and the trade sheet's live price. The engine keeps them in
 * memory only; they travel from here to the engine and never to the page.
 */
export class AccountReaders {
  /** What the engine holds now, so an unchanged setup does not make it drop its cached reads. */
  private sent: string | null = null

  constructor(
    private readonly request: (operation: string, params: Record<string, unknown>) => Promise<unknown>,
    private readonly setup: SetupFile,
    private readonly secrets: SecretStore,
  ) {}

  /** Sends the keys; `fresh` after the engine started, because a new engine holds none. Never throws: reading is best effort. */
  async attach(fresh = false): Promise<void> {
    if (fresh) this.sent = null
    let accounts: { account_id: string; environment: string; key: string; secret: string }[]
    try {
      const keys = new Map(this.secrets.saved.brokers.map((b) => [b.account_id, b]))
      accounts = (this.setup.current()?.configuration.accounts ?? []).flatMap(({ id, environment }) => {
        const broker = keys.get(id)
        return broker?.key && broker.secret ? [{ account_id: id, environment, key: broker.key, secret: broker.secret }] : []
      })
    } catch {
      return // an unreadable setup file is reported where it is read; there is nothing to attach
    }
    const next = JSON.stringify(accounts)
    if (next === this.sent) return
    try {
      await this.request("attach_account_readers", { accounts })
      this.sent = next
    } catch {
      this.sent = null // the engine did not take them: the next change or restart sends again
    }
  }
}
