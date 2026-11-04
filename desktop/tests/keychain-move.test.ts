import { copyFileSync, mkdtempSync, readFileSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { afterEach, describe, expect, it } from "vitest"
import { type KeychainReader, moveKeychainSecrets } from "../electron/main/keychain-move"
import { SecretStore } from "../electron/main/secrets"
import { SETUP_FILE, SetupFile } from "../electron/main/setup-file"

const dirs: string[] = []
afterEach(() => dirs.splice(0).forEach((dir) => rmSync(dir, { recursive: true, force: true })))
const cipher = { encrypt: (text: string) => Buffer.from(text).reverse(), decrypt: (data: Buffer) => Buffer.from(data).reverse().toString() }

const FIXTURE = join(__dirname, "fixtures", SETUP_FILE)
const secretRevision: string = JSON.parse(readFileSync(FIXTURE, "utf8")).secretRevision
const INSTALLATION = "5D3C1B7A-90E2-4C1F-8A77-2F6C0E9B1D44"

// What TradingKeychainStore saves: TradingSecrets as JSON.
const KEYCHAIN_DISCORD = "SENTINEL-keychain-discord-1"
const KEYCHAIN_SECRET = "SENTINEL-keychain-secret-2"
const saved = {
  discord_token: KEYCHAIN_DISCORD,
  provider_api_key: "SENTINEL-keychain-model-3",
  brokers: [{ account_id: "zhap-account-2", key: "SENTINEL-keychain-key-4", secret: KEYCHAIN_SECRET }],
  notification_token: "SENTINEL-keychain-alert-5",
}

function rig(read: KeychainReader, withSetup = true) {
  const dir = mkdtempSync(join(tmpdir(), "kc-"))
  dirs.push(dir)
  if (withSetup) copyFileSync(FIXTURE, join(dir, SETUP_FILE))
  const secrets = new SecretStore(join(dir, "secrets.bin"), cipher)
  return { dir, secrets, move: () => moveKeychainSecrets({ setup: new SetupFile(dir), secrets, installationId: INSTALLATION, read }) }
}

describe("moveKeychainSecrets", () => {
  it("reads the item named by the installation and the saved setup's key revision, both lowercased as the SwiftUI app saves them", async () => {
    const asked: [string, string][] = []
    const r = rig(async (service, account) => (asked.push([service, account]), JSON.stringify(saved)))
    expect(await r.move()).toBe("moved")
    expect(asked).toEqual([[`dev.copytrading.app.trading.${INSTALLATION.toLowerCase()}`, `trading.${secretRevision.toLowerCase()}`]])
  })

  it("brings every key across and ties them to the setup, so the owner does not type them again", async () => {
    const r = rig(async () => JSON.stringify(saved))
    await r.move()
    expect(r.secrets.revision).toBe(secretRevision)
    expect(r.secrets.secrets).toEqual(saved)
    expect(r.secrets.status()).toMatchObject({ discord_token: true, provider_api_key: true, notification_token: true, brokers: { "zhap-account-2": true } })
    // A new run of the app finds them on disk.
    const again = new SecretStore(join(r.dir, "secrets.bin"), cipher)
    expect(again.secrets).toEqual(saved)
    expect(again.revision).toBe(secretRevision)
  })

  it("happens once: a store that already holds this setup's keys is not read from the Keychain again", async () => {
    let reads = 0
    const r = rig(async () => (reads++, JSON.stringify(saved)))
    expect(await r.move()).toBe("moved")
    expect(await r.move()).toBe("already")
    expect(reads).toBe(1)
  })

  it("does nothing, and asks the Keychain nothing, when there is no saved setup", async () => {
    let reads = 0
    const r = rig(async () => (reads++, JSON.stringify(saved)), false)
    expect(await r.move()).toBe("nothing")
    expect(reads).toBe(0)
  })

  it("leaves the store as it was when the Keychain has no such item", async () => {
    const r = rig(async () => null)
    expect(await r.move()).toBe("nothing")
    expect(r.secrets.revision).toBeNull()
    expect(r.secrets.status()).toMatchObject({ discord_token: false })
  })

  it("leaves the store as it was when the item is not what the SwiftUI app saves", async () => {
    for (const text of ["not json", "{}", JSON.stringify({ ...saved, brokers: [{ account_id: "a" }] }), JSON.stringify({ ...saved, discord_token: 5 })]) {
      const r = rig(async () => text)
      expect(await r.move()).toBe("unreadable")
      expect(r.secrets.revision).toBeNull()
    }
  })

  it("lets a refusal by the owner, or by the Keychain, reach the caller, without a key in the message", async () => {
    const r = rig(async () => {
      throw new Error("The Keychain did not give up the saved keys.")
    })
    await expect(r.move()).rejects.toThrow("The Keychain did not give up the saved keys.")
    expect(r.secrets.revision).toBeNull()
  })

  it("keeps a key out of every message it can produce", async () => {
    const r = rig(async () => JSON.stringify({ ...saved, brokers: "SENTINEL" }))
    const result = await r.move().catch((error: Error) => error.message)
    expect(String(result)).not.toContain("SENTINEL-keychain")
  })
})
