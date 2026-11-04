import { execFile } from "node:child_process"
import type { Secrets, SecretStore } from "./secrets"
import type { SetupFile } from "./setup-file"

/** Reads one Keychain item's text, or null when there is none. Production: `security`; tests pass a stand-in. */
export type KeychainReader = (service: string, account: string) => Promise<string | null>

export type KeychainMove = "moved" | "already" | "nothing" | "unreadable"

const NOT_FOUND = 44 // `security`'s exit status for errSecItemNotFound.
// macOS may ask the owner once to let this app read the item; the prompt waits for them.
const PROMPT_WAIT_MS = 5 * 60_000

/** The SwiftUI app's Keychain, through `/usr/bin/security`: no shell, and the key is never in an argument or a message. */
export const securityReader: KeychainReader = (service, account) =>
  new Promise((resolve, reject) => {
    execFile("/usr/bin/security", ["find-generic-password", "-s", service, "-a", account, "-w"], { timeout: PROMPT_WAIT_MS }, (error, stdout) => {
      if (!error) return resolve(stdout.replace(/\n$/, ""))
      if ((error as { code?: unknown }).code === NOT_FOUND) return resolve(null)
      reject(new Error("The Keychain did not give up the saved keys."))
    })
  })

const isText = (value: unknown): value is string => typeof value === "string"

/** The saved shape, or null: TradingKeychainStore saves `TradingSecrets` as JSON under this account. */
function parse(text: string): Secrets | null {
  let value: Record<string, unknown>
  try {
    value = JSON.parse(text)
  } catch {
    return null
  }
  const { discord_token, provider_api_key, brokers, notification_token } = value
  if (!isText(discord_token) || !isText(provider_api_key) || !Array.isArray(brokers)) return null
  const rows = brokers.map((b: Record<string, unknown>) => (isText(b?.account_id) && isText(b.key) && isText(b.secret) ? { account_id: b.account_id, key: b.key, secret: b.secret } : null))
  if (rows.some((row) => row === null)) return null
  return {
    discord_token,
    provider_api_key,
    brokers: rows as Secrets["brokers"],
    ...(isText(notification_token) && notification_token ? { notification_token } : {}),
  }
}

/**
 * First launch after the SwiftUI app: copies the keys the saved setup points at from its Keychain item into the
 * key store, once. It is one-way and keeps no second path: after it, keys live only in the store, and a setup whose
 * revision the store already holds is left alone. The Keychain item is not touched, so the SwiftUI app still works.
 */
export async function moveKeychainSecrets(parts: { setup: SetupFile; secrets: SecretStore; installationId: string; read: KeychainReader }): Promise<KeychainMove> {
  const saved = parts.setup.load()
  if (!saved) return "nothing"
  if (parts.secrets.revision?.toLowerCase() === saved.secretRevision.toLowerCase()) return "already"
  const text = await parts.read(`dev.copytrading.app.trading.${parts.installationId.toLowerCase()}`, `trading.${saved.secretRevision.toLowerCase()}`)
  if (text === null) return "nothing"
  const found = parse(text)
  if (!found) return "unreadable"
  parts.secrets.replace(saved.secretRevision, found)
  return "moved"
}
